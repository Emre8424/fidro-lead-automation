-- 20261022090411 regieflow_daily_integrity_monitor_v1

create table if not exists regieflow_private.integrity_runs (
  id bigint generated always as identity primary key,
  checked_at timestamptz not null default now(),
  ok boolean not null,
  result jsonb not null
);

revoke all on regieflow_private.integrity_runs from public,anon,authenticated;

create or replace function regieflow_private.run_integrity_check()
returns void
language plpgsql
security definer
set search_path=public,regieflow_private
as $$
declare
  v_result jsonb;
begin
  select public.rf_system_integrity_check() into v_result;

  insert into regieflow_private.integrity_runs(ok,result)
  values(coalesce((v_result->>'ok')::boolean,false),v_result);

  delete from regieflow_private.integrity_runs
  where checked_at < now()-interval '90 days';
end
$$;

revoke all on function regieflow_private.run_integrity_check() from public,anon,authenticated;

create or replace function regieflow_private.cleanup_operational_tables()
returns void
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
begin
  delete from regieflow_private.rate_limit_buckets
  where window_start < now()-interval '48 hours';
end
$$;

revoke all on function regieflow_private.cleanup_operational_tables() from public,anon,authenticated;

select cron.schedule(
  'regieflow_daily_integrity',
  '17 2 * * *',
  $$select regieflow_private.run_integrity_check();$$
)
where not exists (
  select 1 from cron.job where jobname='regieflow_daily_integrity'
);

select cron.schedule(
  'regieflow_daily_cleanup',
  '43 2 * * *',
  $$select regieflow_private.cleanup_operational_tables();$$
)
where not exists (
  select 1 from cron.job where jobname='regieflow_daily_cleanup'
);

select regieflow_private.run_integrity_check();

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Automated integrity monitoring and maintenance enabled',
'Enabled daily pg_cron jobs with no external server: rf_system_integrity_check is persisted to private integrity_runs each day with 90-day retention, and stale rate-limit buckets are purged daily. An initial integrity run was executed immediately.');

