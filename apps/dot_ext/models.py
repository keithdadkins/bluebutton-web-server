import hashlib
import itertools
import pytz
import sys
import uuid

from datetime import datetime
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files.storage import default_storage
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q
from django.db.models.signals import post_delete
from django.template.defaultfilters import truncatechars
from django.urls import reverse
from django.utils.dateparse import parse_duration
from django.utils.translation import ugettext_lazy as _
from oauth2_provider.models import (
    AbstractApplication,
    get_access_token_model,
    get_application_model,
)
from oauth2_provider.settings import oauth2_settings
from urllib.parse import urlparse
from waffle import switch_is_active

from apps.capabilities.models import ProtectedCapability
from .utils import is_data_access_type_valid


class Application(AbstractApplication):
    scope = models.ManyToManyField(ProtectedCapability)
    agree = models.BooleanField(default=False)
    created = models.DateTimeField(auto_now_add=True)
    updated = models.DateTimeField(auto_now=True)
    op_tos_uri = models.CharField(default=settings.TOS_URI, blank=True, max_length=512)
    op_policy_uri = models.CharField(default="", blank=True, max_length=512)

    # client_uri is depreciated but will continued to be referenced until it can be removed safely
    client_uri = models.URLField(
        default="",
        blank=True,
        null=True,
        max_length=512,
        verbose_name="Client URI",
        help_text="This is typically a home/download website for the application. "
        "For example, https://www.example.org or http://www.example.org .",
    )

    website_uri = models.URLField(
        default="",
        blank=True,
        null=True,
        max_length=512,
        verbose_name="Website URI",
        help_text="This is typically a home/download website for the application. "
        "For example, https://www.example.org or http://www.example.org .",
    )
    help_text = _(
        "Multiple redirect URIs can"
        " be separated by a space or on"
        " a separate line. Read more"
        " about implementing redirect"
        " URIs in our documentation."
    )
    redirect_uris = models.TextField(help_text=help_text, blank=True)
    logo_uri = models.CharField(
        default="", blank=True, max_length=512, verbose_name="Logo URI"
    )
    tos_uri = models.CharField(
        default="",
        blank=True,
        max_length=512,
        verbose_name="Client's Terms of Service URI",
    )
    policy_uri = models.CharField(
        default="",
        blank=True,
        max_length=512,
        verbose_name="Client's Policy URI",
        help_text="This can be a model privacy notice or other policy document.",
    )
    software_id = models.CharField(
        default="",
        blank=True,
        max_length=128,
        help_text="A unique identifier for an application defined by its creator.",
    )
    contacts = models.TextField(
        default="",
        blank=True,
        max_length=512,
        verbose_name="Client's Contacts",
        help_text="This is typically an email",
    )

    support_email = models.EmailField(blank=True, null=True)

    # FROM https://stackoverflow.com/questions/19130942/whats-the-best-way-to-store-phone-number-in-django-models
    phone_regex = RegexValidator(
        regex=r"^\+?1?\d{9,15}$",
        message="Phone number must be entered in the format: '+999999999'. Up to 15 digits allowed.",
    )

    support_phone_number = models.CharField(
        validators=[phone_regex], max_length=17, blank=True, null=True
    )

    description = models.TextField(
        default="",
        blank=True,
        null=True,
        verbose_name="Application Description",
        help_text="This is plain-text up to 1000 characters in length.",
    )
    active = models.BooleanField(default=True)
    first_active = models.DateTimeField(blank=True, null=True)
    last_active = models.DateTimeField(blank=True, null=True)

    # Does this application need to collect beneficary demographic information? YES = True/Null NO = False
    require_demographic_scopes = models.BooleanField(
        default=True, null=True, verbose_name="Are demographic scopes required?"
    )

    # Type choices related to data access limits.
    APPLICATION_TYPE_CHOICES = (
        ("ONE_TIME", "ONE_TIME - No refresh token needed."),
        ("RESEARCH_STUDY", "RESEARCH_STUDY - Expires on end_date."),
        ("THIRTEEN_MONTH", "THIRTEEN_MONTH - Access expires in 13-months."),
    )

    # Type related to data access limits.
    data_access_type = models.CharField(default="ONE_TIME",
                                        choices=APPLICATION_TYPE_CHOICES,
                                        max_length=16,
                                        null=True,
                                        verbose_name="Data Access Type:")

    # Application end_date related to data access limits.
    end_date = models.DateTimeField(null=True, blank=True,
                                    verbose_name="RESEARCH_STUDY End Date:")

    def scopes(self):
        scope_list = []
        for s in self.scope.all():
            scope_list.append(s.slug)
        return " ".join(scope_list).strip()

    def is_valid(self, scopes=None):
        return self.active and self.allow_scopes(scopes)

    def allow_scopes(self, scopes):
        """
        Check if the token allows the provided scopes
        :param scopes: An iterable containing the scopes to check
        """
        if not scopes:
            return True

        provided_scopes = set(self.scopes().split())
        resource_scopes = set(scopes)

        return resource_scopes.issubset(provided_scopes)

    def get_absolute_url(self):
        return reverse("oauth2_provider:detail", args=[str(self.id)])

    def get_allowed_schemes(self):
        allowed_schemes = []
        redirect_uris = self.redirect_uris.strip().split()
        for uri in redirect_uris:
            scheme = urlparse(uri).scheme
            allowed_schemes.append(scheme)
        return allowed_schemes

    # Save a file to application media storage
    def store_media_file(self, file, filename):
        uri = None
        if file:
            if getattr(file, "name", False):
                file_path = (
                    "applications/"
                    + hashlib.sha256(str(self.pk).encode("utf-8")).hexdigest()
                    + "/"
                    + filename
                )
                if default_storage.exists(file_path):
                    default_storage.delete(file_path)
                default_storage.save(file_path, file)
                if default_storage.exists(file_path):
                    uri = settings.MEDIA_URL + file_path
        return uri

    # Has the research study expired?
    def has_research_study_expired(self):
        if switch_is_active("limit_data_access"):
            if self.data_access_type == "RESEARCH_STUDY":
                if self.end_date:
                    if self.end_date < datetime.now().replace(tzinfo=pytz.UTC):
                        return True

        return False

    # Has one time only type data access?
    def has_one_time_only_data_access(self):
        if switch_is_active("limit_data_access"):
            if self.data_access_type == "ONE_TIME":
                return True

        return False

    # Save override to restrict invalid field combos.
    def save(self, *args, **kwargs):
        # Check data_access_type is in choices tuple
        if not (self.data_access_type in itertools.chain(*self.APPLICATION_TYPE_CHOICES)):
            raise ValueError("Invalid data_access_type: " + self.data_access_type)

        is_valid, mesg = is_data_access_type_valid(self.data_access_type, self.end_date)

        if not is_valid:
            raise ValueError(mesg)

        super().save(*args, **kwargs)


class ApplicationLabel(models.Model):
    name = models.CharField(max_length=255, unique=True)
    slug = models.SlugField(db_index=True, unique=True)
    description = models.TextField()
    applications = models.ManyToManyField(Application, blank=True)

    @property
    def short_description(self):
        return truncatechars(self.description, 80)


class ExpiresInManager(models.Manager):
    """
    Provide a `set_expires_in` and `get_expires_in` methods that
    work as a cache. The key is generated from `client_id` and `user_id`.
    """

    @staticmethod
    def make_key(client_id, user_id):
        """
        Generate a unique key using client_id and user_id args.
        """
        arg = "%s_%s" % (client_id, user_id)
        # Python 3 - avoid TypeError: Unicode-objects
        # must be encoded before hashing
        if sys.version_info > (3, 2):
            arg = arg.encode("utf-8")
        return hashlib.sha256(arg).hexdigest()

    def set_expires_in(self, client_id, user_id, expires_in):
        """
        Set the expires_in value for the key generated with
        client_id and user_id.
        """
        key = self.make_key(client_id, user_id)
        instance, _ = self.update_or_create(
            key=key, defaults={"expires_in": expires_in}
        )

    def get_expires_in(self, client_id, user_id):
        """
        Return the expires_in value for the key generated with
        client_id and user_id. Returns None when the key is not
        found.
        """
        key = self.make_key(client_id, user_id)
        try:
            return self.get(key=key).expires_in
        except self.model.DoesNotExist:
            return None


class Approval(models.Model):
    uuid = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    application = models.ForeignKey(Application, null=True, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)

    @property
    def expired(self):
        return (
            self.created_at
            + parse_duration(
                # Default to 600 seconds, 10 min
                getattr(settings, "AUTHORIZATION_EXPIRATION", "600")
            )
        ).timestamp() < datetime.now().timestamp()


class ArchivedToken(models.Model):

    id = models.BigAutoField(primary_key=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        blank=True,
        null=True,
        db_constraint=False,
        related_name="%(app_label)s_%(class)s",
    )
    token = models.CharField(
        max_length=255,
        unique=True,
    )
    application = models.ForeignKey(
        oauth2_settings.APPLICATION_MODEL,
        on_delete=models.CASCADE,
        blank=True,
        null=True,
        db_constraint=False,
    )
    expires = models.DateTimeField()
    scope = models.TextField(blank=True)

    created = models.DateTimeField()
    updated = models.DateTimeField()
    archived_at = models.DateTimeField(auto_now_add=True)


class ExpiresIn(models.Model):
    """
    This model is used to save the expires_in value selected
    in the allow form view. Then it can be queried when the token is
    issued to the user.
    """

    key = models.CharField(max_length=64, unique=True)
    expires_in = models.IntegerField()

    objects = ExpiresInManager()


def archive_token(sender, instance=None, **kwargs):
    tkn = instance
    ArchivedToken.objects.get_or_create(
        user=tkn.user,
        token=tkn.token,
        application=tkn.application,
        expires=tkn.expires,
        scope=tkn.scope,
        created=tkn.created,
        updated=tkn.updated,
    )


class AuthFlowUuid(models.Model):
    """
    An instance used to persist the beneficiary authorization flow
    auth_uuid across the auth flow when there are breaks in the
    session and for logging the resulting access token that is granted.

    Fields:

    auth_uuid - The beneficiary authorization flow tracing UUID
    state - The state noance used in the Medicare.gov login and callback
    code - The authorization code generated by the authorization server
    client_id - The application client id
    auth_pkce_method - PKCE method used
    auth_crosswalk_action - Action taken with regard to the crosswalk model (retreived/created)
    auth_share_demographic_scopes - Bene demographic sharing choice from consent page/form
    """

    auth_uuid = models.UUIDField(primary_key=True, unique=True)
    state = models.CharField(max_length=64, null=True, unique=True, db_index=True)
    code = models.CharField(
        max_length=255, null=True, unique=True, db_index=True
    )  # code comes from oauthlib
    client_id = models.CharField(max_length=100, null=True)
    auth_pkce_method = models.CharField(max_length=16, null=True)
    created = models.DateTimeField(auto_now_add=True, null=True)
    auth_crosswalk_action = models.CharField(max_length=1, null=True)
    auth_share_demographic_scopes = models.BooleanField(null=True)

    def __str__(self):
        return str(self.auth_uuid)


class AuthFlowUuidCopy(models.Model):
    """
    An instance used to persist the beneficiary authorization flow
    auth_uuid across the auth flow when there are breaks in the
    session and for logging the resulting access token that is granted.

    Fields:

    auth_uuid - The beneficiary authorization flow tracing UUID
    state - The state noance used in the Medicare.gov login and callback
    code - The authorization code generated by the authorization server
    client_id - The application client id
    auth_pkce_method - PKCE method used
    auth_crosswalk_action - Action taken with regard to the crosswalk model (retreived/created)
    auth_share_demographic_scopes - Bene demographic sharing choice from consent page/form
    """

    auth_uuid = models.UUIDField(primary_key=True, unique=True)
    state = models.CharField(max_length=64, null=True, unique=True, db_index=True)
    code = models.CharField(
        max_length=255, null=True, unique=True, db_index=True
    )  # code comes from oauthlib
    client_id = models.CharField(max_length=100, null=True)
    auth_pkce_method = models.CharField(max_length=16, null=True)
    created = models.DateTimeField(null=True)
    auth_crosswalk_action = models.CharField(max_length=1, null=True)
    auth_share_demographic_scopes = models.BooleanField(null=True)

    def __str__(self):
        return str(self.auth_uuid)


def get_application_counts():
    """
    Get the active and inactive counts of applications.
    """
    Application = get_application_model()

    try:
        active_cnt = Application.objects.filter(active=True).count()
        inactive_cnt = Application.objects.filter(active=False).count()
        return {
            "active_cnt": active_cnt,
            "inactive_cnt": inactive_cnt,
        }
    except ValueError:
        pass
    except Application.DoesNotExist:
        pass

    return {
        "active_cnt": None,
        "inactive_cnt": None,
    }


def get_application_require_demographic_scopes_count():
    """
    Get the count of active applications requiring demographic scopes.
    """
    Application = get_application_model()

    try:
        cnt = Application.objects.filter(
            Q(active=True) & Q(require_demographic_scopes=True)
        ).count()
        return cnt
    except ValueError:
        pass
    except Application.DoesNotExist:
        pass

    return None


def get_token_bene_counts(application=None):
    """
    Get the access token counts for real/synth benes

    If application != None, the counts are for a specific application.
    """
    # Init counts dict
    counts_returned = {}

    start_time = datetime.utcnow().timestamp()

    AccessToken = get_access_token_model()

    # Setup base queryset
    token_queryset = AccessToken.objects
    archived_token_queryset = ArchivedToken.objects

    if application:
        token_queryset = token_queryset.filter(application=application)
        archived_token_queryset = archived_token_queryset.filter(application=application)

    # Get AccessToken and ArchivedTokentable count
    counts_returned["total"] = token_queryset.count()
    counts_returned["archived_total"] = archived_token_queryset.count()

    token_queryset = token_queryset.order_by("user__id").values("user__id")

    # real/synth bene distinct counts (excludes granted to multiple apps)
    real_token_queryset = token_queryset.filter(
        ~Q(user__crosswalk___fhir_id__startswith="-")
        & ~Q(user__crosswalk___fhir_id="")
        & Q(user__crosswalk___fhir_id__isnull=False)
    )

    synthetic_token_queryset = token_queryset.filter(
        Q(user__crosswalk___fhir_id__startswith="-")
        & ~Q(user__crosswalk___fhir_id="")
        & Q(user__crosswalk___fhir_id__isnull=False)
    )

    counts_returned["real_deduped"] = real_token_queryset.distinct().count()
    counts_returned["synthetic_deduped"] = synthetic_token_queryset.distinct().count()

    # Global real/synth bene and app pair counts. This should match grant counts.
    if not application:
        counts_returned["real_bene_app_pair_deduped"] = real_token_queryset.values("user", "application").distinct().count()
        counts_returned["synthetic_bene_app_pair_deduped"] = synthetic_token_queryset.values(
            "user", "application").distinct().count()

    counts_returned["deduped_elapsed"] = round(
        datetime.utcnow().timestamp() - start_time, 3
    )

    return counts_returned


post_delete.connect(archive_token, sender="oauth2_provider.AccessToken")
