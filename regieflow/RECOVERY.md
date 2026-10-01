# RegieFlow recovery notes

This branch contains the RegieFlow frontend and source snapshots of the active RegieFlow Edge Functions.

## Canonical development deployment

- Frontend: https://regieflow.pages.dev/
- Supabase project ref: `kiihabzzepoehsokglzq`
- RegieFlow shares the Supabase project with DriveLoop during development. RegieFlow public tables use the `rf_` prefix and private server configuration uses the `regieflow_private` schema.
- Do not modify DriveLoop tables/functions while restoring RegieFlow.

## Active Edge Function source snapshots

Stored below `regieflow/supabase/functions/`:
- rf-public-approval
- rf-auth-approval
- rf-create-internal-user
- rf-claim-customer-invite
- rf-customer-signup
- rf-push
- rf-upload-evidence

Secrets are intentionally not committed. VAPID private keys, hook secrets and service-role credentials remain server-side only.

## RegieFlow migration history

- `20261001071253_regieflow_core_tables_v1`
- `20261001071337_regieflow_rls_v1`
- `20261001071456_regieflow_workflows_v1`
- `20261001071545_regieflow_security_hardening_v1`
- `20261001071617_regieflow_private_dev_log_v1`
- `20261001071638_regieflow_storage_rls_v1`
- `20261001071723_regieflow_customer_finalization_v1`
- `20261001072002_regieflow_onboarding_permissions_v1`
- `20261001072153_regieflow_customer_invites_v1`
- `20261001072206_regieflow_internal_account_onboarding_v1`
- `20261001072332_regieflow_pricing_catalog_v1`
- `20261001072407_regieflow_storage_evidence_hardening_v1`
- `20261001072451_regieflow_frontend_api_v1`
- `20261001072539_regieflow_customer_request_flow_v1`
- `20261001072608_regieflow_owner_safety_v1`
- `20261001072708_regieflow_regie_creation_revision_v1`
- `20261001072923_regieflow_privileges_integrity_v1`
- `20261001073013_regieflow_realtime_v1`
- `20261001073222_regieflow_dev_setup_tokens_v1`
- `20261001073238_regieflow_dev_setup_rpc_v1`
- `20261001074138_regieflow_web_push_foundation_v1`
- `20261001074817_regieflow_customer_request_prepare_v1`
- `20261001074951_regieflow_onboarding_lockdown_v1`
- `20261001075023_regieflow_performance_pass_v1`
- `20261001075623_regieflow_static_web_bucket_v1`
- `20261001085635_regieflow_service_role_permissions_fix_v1`
- `20261001090032_isolate_regieflow_users_from_driveloop_profiles`
- `20261001091548_regieflow_neutral_rapport_wording_v1`
- `20261001092752_regieflow_neutral_external_references_v1`
- `20261001092849_regieflow_close_rpc_compatibility_v1`
- `20261001093014_regieflow_signature_evidence_v2`
- `20261001094803_regieflow_close_regie_v2_v1`
- `20261001094856_regieflow_revoke_unsafe_table_privileges_v1`
- `20261001094910_regieflow_overview_privileges_hardening_v1`
- `20261001094944_regieflow_audit_log_internal_only_v1`
- `20261001095005_regieflow_signature_select_internal_only_v1`
- `20261001095042_regieflow_remove_legacy_rpcs_v1`
- `20261001095124_regieflow_customer_request_approval_permission_v1`
- `20261001095211_regieflow_file_immutability_v1`
- `20261001095235_regieflow_revision_file_state_fix_v1`
- `20261001100556_regieflow_human_notification_status_labels_v1`
- `20261001102042_regieflow_restore_required_client_dml_v1`
- `20261001102443_regieflow_neutralize_overview_columns_v1`
- `20261001102742_regieflow_split_rls_write_policies_v1`
- `20261001102926_regieflow_disable_obsolete_public_web_bucket_v1`
- `20261001102958_regieflow_public_link_first_view_evidence_v1`
- `20261001103125_regieflow_limit_team_directory_visibility_v1`
- `20261001103306_regieflow_lightweight_comments_v1`
- `20261001103511_regieflow_project_input_constraints_v1`
- `20261001103634_regieflow_evidence_uploader_provenance_v1`
- `20261001103849_regieflow_server_side_evidence_registration_v1`

## Production migration note

Before a public paid launch, prefer moving RegieFlow to its own Supabase project. Reapply the RegieFlow migration chain, deploy the Edge Functions, recreate private storage buckets/configuration, set the frontend environment constants, then run the full end-to-end workflow before switching DNS.

The authoritative chronological implementation notes remain in `regieflow_private.dev_log` in Supabase.
