/*
 Query for view:  vw_test_global_state_per_app
 
 This view is used for incremental updates based on 
 min/max report date ranges when selecting from the
 from the bb2.test_global_state_per_app table
 
 NOTE: Use this query when creating or updating this view in Athena.
 */
CREATE
OR REPLACE VIEW vw_test_global_state_per_app AS
/* Set the report_date_range to be selected.

 This is used to select time_of_event records that are
 >= min_report_date AND < max_report_date
 
 This is used for inserting only new records in to 
 bb2.test_global_state_per_app table.
 
 For recovery purposes (like recreating the table), the date
 ranges can be hard coded via uncommenting/commenting the related SQL. 

 Then Restore to the original view after recovery!
 */
WITH report_date_range AS (
  /* Select gets the MIN report_date to select new records from 
   the bb2.events_test_perf_mon table */
  /*
   Use this to HARD CODE the MIN report date for recovery purposes.
   For example, you can use a past date like '2000-01-01'.  */
  /*
   SELECT
   date_trunc('week', CAST('2000-01-01' AS date)) min_report_date,
  */
  /*
   This is normally the maximum/last report_date from the 
   bb2.test_global_state_per_app table via the select below: */
  SELECT
    (
      SELECT
        date_trunc('week', MAX(report_date))
      FROM
        bb2.test_global_state_per_app
    ) AS min_report_date,

    /* Use the following to select the MAX report date.
     
     This can be hard coded for recovery purposes as below: */
    /* 
     date_trunc('week', CAST('2022-08-22' AS date)) max_report_date 
     */
    /* This is normally set to the built-in "current_date" */
    date_trunc('week', current_date) max_report_date
),
report_partitions_range AS (
  SELECT
    CONCAT(
      CAST(YEAR(min_report_date) AS VARCHAR),
      '-',
      LPAD(CAST(MONTH(min_report_date) AS VARCHAR), 2, '0'),
      '-',
      LPAD(CAST(DAY(min_report_date) AS VARCHAR), 2, '0')
    ) AS min_partition_date
  FROM
    (
      select
        min_report_date
      FROM
        report_date_range
    )
),
/* Sub-select for V1 FHIR events */
v1_fhir_events AS (
  select
    time_of_event,
    path,
    fhir_id,
    req_qparam_lastupdated,
    application,
    auth_app_name,
    req_app_name,
    resp_app_name,
    app_name
  from
    "bb2"."events_test_perf_mon"
  WHERE
    (
      type = 'request_response_middleware'
      and vpc = 'test'
      and request_method = 'GET'
      and path LIKE '/v1/fhir%'
      and response_code = 200
      and cast("from_iso8601_timestamp"(time_of_event) AS date) >= (
        select
          min_report_date
        FROM
          report_date_range
      )
      and cast("from_iso8601_timestamp"(time_of_event) AS date) < (
        select
          max_report_date
        FROM
          report_date_range
      )
      /* NOTE: Below is for future query tuning after
         the Glue table is partitioned
         and to utilize the partition indexing.
      */
       AND concat(dt, '-', partition_1, '-', partition_2) >= (
       SELECT
       min_partition_date
       FROM
       report_partitions_range
       )
    )
),
/* Sub-select for V2 FHIR events */
v2_fhir_events AS (
  select
    time_of_event,
    path,
    fhir_id,
    req_qparam_lastupdated,
    application,
    auth_app_name,
    req_app_name,
    resp_app_name,
    app_name
  from
    "bb2"."events_test_perf_mon"
  WHERE
    (
      type = 'request_response_middleware'
      and vpc = 'test'
      and request_method = 'GET'
      and path LIKE '/v2/fhir%'
      and response_code = 200
      and cast("from_iso8601_timestamp"(time_of_event) AS date) >= (
        select
          min_report_date
        FROM
          report_date_range
      )
      and cast("from_iso8601_timestamp"(time_of_event) AS date) < (
        select
          max_report_date
        FROM
          report_date_range
      )
      AND concat(dt, '-', partition_1, '-', partition_2) >= (
        SELECT
          min_partition_date
        FROM
          report_partitions_range
      )
    )
),
/* Sub-select for AUTH events */
auth_events AS (
  select
    time_of_event,
    auth_app_name,
    auth_require_demographic_scopes,
    auth_crosswalk_action,
    auth_share_demographic_scopes,
    auth_status,
    application,
    share_demographic_scopes,
    allow,
    json_extract(user, '$.crosswalk.fhir_id') as fhir_id
  from
    "bb2"."events_test_perf_mon"
  WHERE
    (
      type = 'Authorization'
      and vpc = 'test'
      and cast("from_iso8601_timestamp"(time_of_event) AS date) >= (
        select
          min_report_date
        FROM
          report_date_range
      )
      and cast("from_iso8601_timestamp"(time_of_event) AS date) < (
        select
          max_report_date
        FROM
          report_date_range
      )
      AND concat(dt, '-', partition_1, '-', partition_2) >= (
        SELECT
          min_partition_date
        FROM
          report_partitions_range
      )
    )
),
/* Sub-select for Token events */
token_events AS (
  select
    time_of_event,
    action,
    auth_app_name,
    auth_require_demographic_scopes,
    auth_crosswalk_action,
    auth_share_demographic_scopes,
    auth_grant_type,
    application,
    crosswalk
  from
    "bb2"."events_test_perf_mon"
  WHERE
    (
      type = 'AccessToken'
      and vpc = 'test'
      and cast("from_iso8601_timestamp"(time_of_event) AS date) >= (
        select
          min_report_date
        FROM
          report_date_range
      )
      and cast("from_iso8601_timestamp"(time_of_event) AS date) < (
        select
          max_report_date
        FROM
          report_date_range
      )
      AND concat(dt, '-', partition_1, '-', partition_2) >= (
        SELECT
          min_partition_date
        FROM
          report_partitions_range
      )
    )
),
/* Sub-select for token request events */
token_request_events AS (
  select
    time_of_event,
    path,
    auth_grant_type,
    auth_crosswalk_action,
    resp_fhir_id,
    response_code,
    auth_app_name,
    application,
    req_app_name,
    resp_app_name,
    app_name
  from
    "bb2"."events_test_perf_mon"
  WHERE
    (
      type = 'request_response_middleware'
      and vpc = 'test'
      and request_method = 'POST'
      and path LIKE '/v%/o/token%/'
      and cast("from_iso8601_timestamp"(time_of_event) AS date) >= (
        select
          min_report_date
        FROM
          report_date_range
      )
      and cast("from_iso8601_timestamp"(time_of_event) AS date) < (
        select
          max_report_date
        FROM
          report_date_range
      )
      AND concat(dt, '-', partition_1, '-', partition_2) >= (
        SELECT
          min_partition_date
        FROM
          report_partitions_range
      )
    )
)
SELECT
  t1.vpc,
  t1.start_date,
  t1.end_date,
  t1.report_date,
  t1.max_group_timestamp,
  t1.max_real_bene_cnt,
  t1.max_synth_bene_cnt,
  t1.max_crosswalk_real_bene_count,
  t1.max_crosswalk_synthetic_bene_count,
  t1.max_crosswalk_table_count,
  t1.max_crosswalk_archived_table_count,
  t1.max_grant_real_bene_count,
  t1.max_grant_synthetic_bene_count,
  t1.max_grant_table_count,
  t1.max_grant_archived_table_count,
  t1.max_grant_real_bene_deduped_count,
  t1.max_grant_synthetic_bene_deduped_count,
  t1.max_grantarchived_real_bene_deduped_count,
  t1.max_grantarchived_synthetic_bene_deduped_count,
  t1.max_grant_and_archived_real_bene_deduped_count,
  t1.max_grant_and_archived_synthetic_bene_deduped_count,
  t1.max_token_real_bene_deduped_count,
  t1.max_token_synthetic_bene_deduped_count,
  t1.max_token_table_count,
  t1.max_token_archived_table_count,
  t1.max_global_apps_active_cnt,
  t1.max_global_apps_inactive_cnt,
  t1.max_global_apps_require_demographic_scopes_cnt,
  t1.max_global_developer_count,
  t1.max_global_developer_distinct_organization_name_count,
  t1.max_global_developer_with_first_api_call_count,
  t1.max_global_developer_with_registered_app_count,
  t2.name app_name,
  t2.id app_id,
  t2.created app_created,
  t2.updated app_updated,
  t2.active app_active,
  t2.first_active app_first_active,
  t2.last_active app_last_active,
  t2.require_demographic_scopes app_require_demographic_scopes,
  t2.user_organization app_user_organization,
  t2.user_id app_user_id,
  t2.user_username app_user_username,
  t2.user_date_joined app_user_date_joined,
  t2.user_last_login app_user_last_login,
  t2.real_bene_cnt app_real_bene_cnt,
  t2.synth_bene_cnt app_synth_bene_cnt,
  t2.grant_real_bene_count app_grant_real_bene_count,
  t2.grant_synthetic_bene_count app_grant_synthetic_bene_count,
  t2.grant_table_count app_grant_table_count,
  t2.grant_archived_table_count app_grant_archived_table_count,
  t2.grantarchived_real_bene_deduped_count app_grantarchived_real_bene_deduped_count,
  t2.grantarchived_synthetic_bene_deduped_count app_grantarchived_synthetic_bene_deduped_count,
  t2.grant_and_archived_real_bene_deduped_count app_grant_and_archived_real_bene_deduped_count,
  t2.grant_and_archived_synthetic_bene_deduped_count app_grant_and_archived_synthetic_bene_deduped_count,
  t2.token_real_bene_count app_token_real_bene_count,
  t2.token_synthetic_bene_count app_token_synthetic_bene_count,
  t2.token_table_count app_token_table_count,
  t2.token_archived_table_count app_token_archived_table_count,
  /* V1 FHIR resource stats per application */
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v1_call_real_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v1_call_synthetic_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v1_eob_call_real_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v1_eob_call_synthetic_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v1_coverage_call_real_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v1_coverage_call_synthetic_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/Patient%'
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v1_patient_call_real_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/Patient%'
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v1_patient_call_synthetic_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/metadata%'
      )
  ) as app_fhir_v1_metadata_call_count,
  /* V1 since (lastUpdated) stats top level */
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) >= 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v1_eob_since_call_real_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) < 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v1_eob_since_call_synthetic_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) >= 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v1_coverage_since_call_real_count,
  (
    select
      count(*)
    from
      v1_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v1/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) < 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v1_coverage_since_call_synthetic_count,
  /* V2 FHIR resource stats per application */
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v2_call_real_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v2_call_synthetic_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v2_eob_call_real_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v2_eob_call_synthetic_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v2_coverage_call_real_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v2_coverage_call_synthetic_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/Patient%'
        and try_cast(fhir_id as BIGINT) >= 0
      )
  ) as app_fhir_v2_patient_call_real_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/Patient%'
        and try_cast(fhir_id as BIGINT) < 0
      )
  ) as app_fhir_v2_patient_call_synthetic_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/metadata%'
      )
  ) as app_fhir_v2_metadata_call_count,
  /* V2 since (lastUpdated) stats top level */
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) >= 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v2_eob_since_call_real_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/ExplanationOfBenefit%'
        and try_cast(fhir_id as BIGINT) < 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v2_eob_since_call_synthetic_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) >= 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v2_coverage_since_call_real_count,
  (
    select
      count(*)
    from
      v2_fhir_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        and path LIKE '/v2/fhir/Coverage%'
        and try_cast(fhir_id as BIGINT) < 0
        and req_qparam_lastupdated != ''
      )
  ) as app_fhir_v2_coverage_since_call_synthetic_count,
  /* AUTH and demographic scopes stats per application */
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
        and auth_status = 'OK'
        and allow = True
      )
  ) as app_auth_ok_real_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) < 0
        and auth_status = 'OK'
        and allow = True
      )
  ) as app_auth_ok_synthetic_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
        and auth_status = 'FAIL'
      )
  ) as app_auth_fail_or_deny_real_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) < 0
        and auth_status = 'FAIL'
      )
  ) as app_auth_fail_or_deny_synthetic_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
        and auth_status = 'OK'
        and allow = True
        and auth_require_demographic_scopes = 'True'
        and share_demographic_scopes = 'True'
      )
  ) as app_auth_demoscope_required_choice_sharing_real_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) < 0
        and auth_status = 'OK'
        and allow = True
        and auth_require_demographic_scopes = 'True'
        and share_demographic_scopes = 'True'
      )
  ) as app_auth_demoscope_required_choice_sharing_synthetic_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
        and auth_status = 'OK'
        and allow = True
        and auth_require_demographic_scopes = 'True'
        and share_demographic_scopes = 'False'
      )
  ) as app_auth_demoscope_required_choice_not_sharing_real_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) < 0
        and auth_status = 'OK'
        and allow = True
        and auth_require_demographic_scopes = 'True'
        and share_demographic_scopes = 'False'
      )
  ) as app_auth_demoscope_required_choice_not_sharing_synthetic_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
        and allow = False
        and auth_require_demographic_scopes = 'True'
      )
  ) as app_auth_demoscope_required_choice_deny_real_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) < 0
        and allow = False
        and auth_require_demographic_scopes = 'True'
      )
  ) as app_auth_demoscope_required_choice_deny_synthetic_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
        and auth_status = 'OK'
        and allow = True
        and auth_require_demographic_scopes = 'False'
      )
  ) as app_auth_demoscope_not_required_not_sharing_real_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) < 0
        and auth_status = 'OK'
        and allow = True
        and auth_require_demographic_scopes = 'False'
      )
  ) as app_auth_demoscope_not_required_not_sharing_synthetic_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) >= 0
        and allow = False
        and auth_require_demographic_scopes = 'False'
      )
  ) as app_auth_demoscope_not_required_deny_real_bene_count,
  (
    select
      count(*)
    from
      auth_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (application.name, auth_app_name)
        and try_cast(fhir_id as BIGINT) < 0
        and allow = False
        and auth_require_demographic_scopes = 'False'
      )
  ) as app_auth_demoscope_not_required_deny_synthetic_bene_count,
  /* Token stats per application */
  (
    select
      count(*)
    from
      token_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND action = 'authorized'
        AND auth_grant_type = 'refresh_token'
        and application.name = t2.name
        and try_cast(crosswalk.fhir_id as BIGINT) >= 0
      )
  ) as app_token_refresh_for_real_bene_count,
  (
    select
      count(*)
    from
      token_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND action = 'authorized'
        AND auth_grant_type = 'refresh_token'
        and application.name = t2.name
        and try_cast(crosswalk.fhir_id as BIGINT) < 0
      )
  ) as app_token_refresh_for_synthetic_bene_count,
  (
    select
      count(*)
    from
      token_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND auth_grant_type = 'authorization_code'
        and application.name = t2.name
        and try_cast(crosswalk.fhir_id as BIGINT) >= 0
      )
  ) as app_token_authorization_code_for_real_bene_count,
  (
    select
      count(*)
    from
      token_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND auth_grant_type = 'authorization_code'
        and application.name = t2.name
        and try_cast(crosswalk.fhir_id as BIGINT) < 0
      )
  ) as app_token_authorization_code_for_synthetic_bene_count,
  /* Token request stats per application */
  (
    select
      count(*)
    from
      token_request_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        AND auth_grant_type = 'refresh_token'
        AND response_code >= 200
        AND response_code < 300
      )
  ) as app_token_refresh_response_2xx_count,
  (
    select
      count(*)
    from
      token_request_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        AND auth_grant_type = 'refresh_token'
        AND response_code >= 400
        AND response_code < 500
      )
  ) as app_token_refresh_response_4xx_count,
  (
    select
      count(*)
    from
      token_request_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        AND auth_grant_type = 'refresh_token'
        AND response_code >= 500
      )
  ) as app_token_refresh_response_5xx_count,
  (
    select
      count(*)
    from
      token_request_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        AND auth_grant_type = 'authorization_code'
        AND response_code >= 200
        AND response_code < 300
      )
  ) as app_token_authorization_code_2xx_count,
  (
    select
      count(*)
    from
      token_request_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        AND auth_grant_type = 'authorization_code'
        AND response_code >= 400
        AND response_code < 500
      )
  ) as app_token_authorization_code_4xx_count,
  (
    select
      count(*)
    from
      token_request_events
    WHERE
      (
        cast("from_iso8601_timestamp"(time_of_event) AS date) >= t1.start_date
        and cast("from_iso8601_timestamp"(time_of_event) AS date) <= t1.end_date
        AND t2.name IN (app_name, application.name, auth_app_name, req_app_name, resp_app_name)
        AND auth_grant_type = 'authorization_code'
        AND response_code >= 500
      )
  ) as app_token_authorization_code_5xx_count
FROM
  (
    (
      SELECT
        vpc,
        e_start_date start_date,
        e_end_date end_date,
        "max"(e_date) + INTERVAL '1' DAY report_date,
        "max"(group_timestamp) max_group_timestamp,
        "max"(real_bene_cnt) max_real_bene_cnt,
        "max"(synth_bene_cnt) max_synth_bene_cnt,
        "max"(crosswalk_real_bene_count) max_crosswalk_real_bene_count,
        "max"(crosswalk_synthetic_bene_count) max_crosswalk_synthetic_bene_count,
        "max"(crosswalk_table_count) max_crosswalk_table_count,
        "max"(crosswalk_archived_table_count) max_crosswalk_archived_table_count,
        "max"(grant_real_bene_count) max_grant_real_bene_count,
        "max"(grant_synthetic_bene_count) max_grant_synthetic_bene_count,
        "max"(grant_table_count) max_grant_table_count,
        "max"(grant_archived_table_count) max_grant_archived_table_count,
        "max"(grant_real_bene_deduped_count) max_grant_real_bene_deduped_count,
        "max"(grant_synthetic_bene_deduped_count) max_grant_synthetic_bene_deduped_count,
        "max"(grantarchived_real_bene_deduped_count) max_grantarchived_real_bene_deduped_count,
        "max"(grantarchived_synthetic_bene_deduped_count) max_grantarchived_synthetic_bene_deduped_count,
        "max"(grant_and_archived_real_bene_deduped_count) max_grant_and_archived_real_bene_deduped_count,
        "max"(grant_and_archived_synthetic_bene_deduped_count) max_grant_and_archived_synthetic_bene_deduped_count,
        "max"(token_real_bene_deduped_count) max_token_real_bene_deduped_count,
        "max"(token_synthetic_bene_deduped_count) max_token_synthetic_bene_deduped_count,
        "max"(token_table_count) max_token_table_count,
        "max"(token_archived_table_count) max_token_archived_table_count,
        "max"(global_apps_active_cnt) max_global_apps_active_cnt,
        "max"(global_apps_inactive_cnt) max_global_apps_inactive_cnt,
        "max"(
          global_apps_require_demographic_scopes_cnt
        ) max_global_apps_require_demographic_scopes_cnt,
        "max"(global_developer_count) max_global_developer_count,
        "max"(
          global_developer_distinct_organization_name_count
        ) max_global_developer_distinct_organization_name_count,
        "max"(global_developer_with_first_api_call_count) max_global_developer_with_first_api_call_count,
        "max"(global_developer_with_registered_app_count) max_global_developer_with_registered_app_count
      FROM
        (
          SELECT
            DISTINCT vpc,
            CAST(
              "from_iso8601_timestamp"(time_of_event) AS date
            ) e_date,
            date_trunc(
              'week',
              CAST(
                "from_iso8601_timestamp"(time_of_event) AS date
              )
            ) e_start_date,
            date_trunc(
              'week',
              CAST(
                "from_iso8601_timestamp"(time_of_event) AS date
              )
            ) + INTERVAL '6' DAY e_end_date,
            group_timestamp,
            real_bene_cnt,
            synth_bene_cnt,
            crosswalk_real_bene_count,
            crosswalk_synthetic_bene_count,
            crosswalk_table_count,
            crosswalk_archived_table_count,
            grant_real_bene_count,
            grant_synthetic_bene_count,
            grant_table_count,
            grant_archived_table_count,
            grant_real_bene_deduped_count,
            grant_synthetic_bene_deduped_count,
            grantarchived_real_bene_deduped_count,
            grantarchived_synthetic_bene_deduped_count,
            grant_and_archived_real_bene_deduped_count,
            grant_and_archived_synthetic_bene_deduped_count,
            token_real_bene_deduped_count,
            token_synthetic_bene_deduped_count,
            token_table_count,
            token_archived_table_count,
            global_apps_active_cnt,
            global_apps_inactive_cnt,
            global_apps_require_demographic_scopes_cnt,
            global_developer_count,
            global_developer_distinct_organization_name_count,
            global_developer_with_first_api_call_count,
            global_developer_with_registered_app_count
          FROM
            bb2.events_test_perf_mon
          WHERE
            (
              type = 'global_state_metrics'
              AND vpc = 'test'
              AND cast("from_iso8601_timestamp"(time_of_event) AS date) >= (
                select
                  min_report_date
                FROM
                  report_date_range
              )
              AND cast("from_iso8601_timestamp"(time_of_event) AS date) < (
                select
                  max_report_date
                FROM
                  report_date_range
              )
              AND concat(dt, '-', partition_1, '-', partition_2) >= (
                SELECT
                  min_partition_date
                FROM
                  report_partitions_range
              )
            )
        )
      GROUP BY
        vpc,
        e_start_date,
        e_end_date
    ) t1
    INNER JOIN (
      SELECT
        DISTINCT group_timestamp,
        vpc,
        name,
        id,
        created,
        updated,
        active,
        first_active,
        last_active,
        require_demographic_scopes,
        user_organization,
        user_id,
        user_username,
        user_date_joined,
        user_last_login,
        real_bene_cnt,
        synth_bene_cnt,
        grant_real_bene_count,
        grant_synthetic_bene_count,
        grant_table_count,
        grant_archived_table_count,
        grantarchived_real_bene_deduped_count,
        grantarchived_synthetic_bene_deduped_count,
        grant_and_archived_real_bene_deduped_count,
        grant_and_archived_synthetic_bene_deduped_count,
        token_real_bene_count,
        token_synthetic_bene_count,
        token_table_count,
        token_archived_table_count
      FROM
        bb2.events_test_perf_mon
      WHERE
        (
          type = 'global_state_metrics_per_app'
          AND vpc = 'test'
          AND cast("from_iso8601_timestamp"(time_of_event) AS date) >= (
            select
              min_report_date
            FROM
              report_date_range
          )
          AND cast("from_iso8601_timestamp"(time_of_event) AS date) < (
            select
              max_report_date
            FROM
              report_date_range
          )
          AND concat(dt, '-', partition_1, '-', partition_2) >= (
            SELECT
              min_partition_date
            FROM
              report_partitions_range
          )
        )
    ) t2 ON (
      t1.max_group_timestamp = t2.group_timestamp
      AND t1.vpc = t2.vpc
      AND t2.name <> 'TestApp'
      AND t2.name <> 'BlueButton Client (Test - Internal Use Only)'
      AND t2.name <> 'MyMedicare PROD'
      AND t2.name <> 'new-relic'
    )
  )
