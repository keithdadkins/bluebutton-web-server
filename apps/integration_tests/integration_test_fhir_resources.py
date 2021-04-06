import json
import jsonschema
from jsonschema import validate

from django.conf import settings
from django.contrib.staticfiles.testing import StaticLiveServerTestCase
from oauth2_provider.models import AccessToken
from rest_framework.test import APIClient
from waffle.testutils import override_switch

from apps.test import BaseApiTest

from .endpoint_schemas import (USERINFO_SCHEMA, PATIENT_READ_SCHEMA, PATIENT_SEARCH_SCHEMA,
                               COVERAGE_READ_SCHEMA, COVERAGE_SEARCH_SCHEMA,
                               EOB_READ_SCHEMA, EOB_SEARCH_SCHEMA)


class IntegrationTestFhirApiResources(StaticLiveServerTestCase):
    '''
    This sets up a live server in the background to test with.
    For more details, see https://docs.djangoproject.com/en/3.1/topics/testing/tools/#liveservertestcase
    This uses APIClient to test the BB2 FHIR API endpoints with the default (Fred) access token.
    '''
    fixtures = ['scopes.json']

    def _setup_apiclient(self, client):
        # Setup token in APIClient
        '''
        TODO: Perform auth flow here --- when selenium is included later.
              For now, creating user thru access token using BaseApiTest for now.
        '''
        # Setup instance of BaseApiTest
        base_api_test = BaseApiTest()

        # Setup client for BaseApiTest client
        base_api_test.client = client

        # Setup read/write capability for create_token()
        base_api_test.read_capability = base_api_test._create_capability('Read', [])
        base_api_test.write_capability = base_api_test._create_capability('Write', [])

        # create user, app, and access token
        first_name = "John"
        last_name = "Doe"
        access_token = base_api_test.create_token(first_name, last_name)

        # Test scope in access_token
        at = AccessToken.objects.get(token=access_token)

        # Setup Bearer token:
        client.credentials(HTTP_AUTHORIZATION="Bearer " + at.token)

    def _validateJsonSchema(self, schema, content):
        try:
            validate(instance=content, schema=schema)
        except jsonschema.exceptions.ValidationError as e:
            # Show error info for debugging
            print("jsonschema.exceptions.ValidationError: ", e)
            return False
        return True

    @override_switch('require-scopes', active=True)
    def test_userinfo_endpoint(self):
        base_path = "/v1/connect/userinfo"
        client = APIClient()

        # 1. Test unauthenticated request
        url = self.live_server_url + base_path
        response = client.get(url)
        self.assertEqual(response.status_code, 401)

        # Authenticate
        self._setup_apiclient(client)

        # 2. Test authenticated request
        response = client.get(url)
        self.assertEqual(response.status_code, 200)
        #     Validate JSON Schema
        content = json.loads(response.content)
        self.assertEqual(self._validateJsonSchema(USERINFO_SCHEMA, content), True)

    @override_switch('require-scopes', active=True)
    def test_patient_endpoint(self):
        base_path = "/v1/fhir/Patient"
        client = APIClient()

        # 1. Test unauthenticated request
        url = self.live_server_url + base_path
        response = client.get(url)
        self.assertEqual(response.status_code, 401)

        # Authenticate
        self._setup_apiclient(client)

        # 2. Test SEARCH VIEW endpoint
        url = self.live_server_url + base_path
        response = client.get(url)
        self.assertEqual(response.status_code, 200)
        #     Validate JSON Schema
        content = json.loads(response.content)
        self.assertEqual(self._validateJsonSchema(PATIENT_SEARCH_SCHEMA, content), True)

        # 3. Test READ VIEW endpoint
        url = self.live_server_url + base_path + "/" + settings.DEFAULT_SAMPLE_FHIR_ID
        response = client.get(url)
        self.assertEqual(response.status_code, 200)
        #     Validate JSON Schema
        content = json.loads(response.content)
        self.assertEqual(self._validateJsonSchema(PATIENT_READ_SCHEMA, content), True)

        # 4. Test unauthorized READ request
        url = self.live_server_url + base_path + "/" + "99999999999999"
        response = client.get(url)
        self.assertEqual(response.status_code, 404)

    @override_switch('require-scopes', active=True)
    def test_coverage_endpoint(self):
        base_path = "/v1/fhir/Coverage"
        client = APIClient()

        # 1. Test unauthenticated request
        url = self.live_server_url + base_path
        response = client.get(url)
        self.assertEqual(response.status_code, 401)

        # Authenticate
        self._setup_apiclient(client)

        # 2. Test SEARCH VIEW endpoint
        url = self.live_server_url + base_path
        response = client.get(url)
        self.assertEqual(response.status_code, 200)
        #     Validate JSON Schema
        content = json.loads(response.content)
        self.assertEqual(self._validateJsonSchema(COVERAGE_SEARCH_SCHEMA, content), True)

        # 3. Test READ VIEW endpoint
        url = self.live_server_url + base_path + "/part-a-" + settings.DEFAULT_SAMPLE_FHIR_ID
        response = client.get(url)
        self.assertEqual(response.status_code, 200)
        #     Validate JSON Schema
        content = json.loads(response.content)
        self.assertEqual(self._validateJsonSchema(COVERAGE_READ_SCHEMA, content), True)

        # 4. Test unauthorized READ request
        url = self.live_server_url + base_path + "/part-a-" + "99999999999999"
        response = client.get(url)
        self.assertEqual(response.status_code, 404)

    @override_switch('require-scopes', active=True)
    def test_eob_endpoint(self):
        base_path = "/v1/fhir/ExplanationOfBenefit"
        client = APIClient()

        # 1. Test unauthenticated request
        url = self.live_server_url + base_path
        response = client.get(url)
        self.assertEqual(response.status_code, 401)

        # Authenticate
        self._setup_apiclient(client)

        # 2. Test SEARCH VIEW endpoint
        url = self.live_server_url + base_path
        response = client.get(url)
        self.assertEqual(response.status_code, 200)
        #     Validate JSON Schema
        content = json.loads(response.content)
        self.assertEqual(self._validateJsonSchema(EOB_SEARCH_SCHEMA, content), True)

        # 3. Test READ VIEW endpoint
        url = self.live_server_url + base_path + "/carrier--22639159481"
        response = client.get(url)
        self.assertEqual(response.status_code, 200)
        #     Validate JSON Schema
        content = json.loads(response.content)
        self.assertEqual(self._validateJsonSchema(EOB_READ_SCHEMA, content), True)

        # 4. Test unauthorized READ request
        url = self.live_server_url + base_path + "/carrier-23017401521"
        response = client.get(url)
        self.assertEqual(response.status_code, 404)