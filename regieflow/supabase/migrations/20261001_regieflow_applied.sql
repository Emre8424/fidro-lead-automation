-- 20261001072206 regieflow_internal_account_onboarding_v1

alter table public.rf_memberships
  add column must_change_password boolean not null default false;

insert into regieflow_private.dev_log(kind,title,content)
values('decision','Internal account onboarding','New internal accounts created by the Owner/authorized user receive a generated temporary password and are marked must_change_password=true. Existing Supabase users linked into a RegieFlow company keep their existing credentials and are not forced to change them.');


-- 20261001102926 regieflow_disable_obsolete_public_web_bucket_v1

update storage.buckets
set public=false
where id='rf-web';

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Obsolete rf-web bucket made private',
'The temporary Supabase Storage frontend bucket from the failed hosting experiment still existed as public with three stale objects. It is no longer used because Cloudflare Pages is canonical hosting. The bucket was switched to private to remove unnecessary public surface without deleting evidence or files.');


-- 20261001071253 regieflow_core_tables_v1

create or replace function public.rf_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end
$$;

create table public.rf_companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 160),
  primary_owner_user_id uuid not null references auth.users(id) on delete restrict,
  logo_path text,
  accent_color text not null default '#111827' check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  legal_name text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.rf_roles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  permissions text[] not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, name)
);

create table public.rf_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 120),
  role_id uuid references public.rf_roles(id) on delete set null,
  permission_overrides jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, user_id)
);

create table public.rf_customer_contacts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete cascade,
  auth_user_id uuid references auth.users(id) on delete set null,
  full_name text not null check (char_length(trim(full_name)) between 1 and 160),
  email text,
  phone text,
  organization_name text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index rf_customer_auth_per_company_uidx
  on public.rf_customer_contacts(company_id, auth_user_id)
  where auth_user_id is not null;

create table public.rf_projects (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete restrict,
  project_number text not null,
  messerli_project_number text,
  name text not null check (char_length(trim(name)) between 1 and 180),
  address text,
  client_name text,
  approval_workflow text not null default 'office_then_customer'
    check (approval_workflow in ('office_then_customer','parallel_office_customer')),
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, project_number)
);

create table public.rf_project_customer_access (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.rf_projects(id) on delete cascade,
  customer_contact_id uuid not null references public.rf_customer_contacts(id) on delete cascade,
  can_sign boolean not null default false,
  label text,
  created_at timestamptz not null default now(),
  unique(project_id, customer_contact_id)
);

create table public.rf_regies (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete restrict,
  project_id uuid not null references public.rf_projects(id) on delete restrict,
  regie_code text unique,
  source text not null default 'internal' check (source in ('internal','customer')),
  status text not null default 'draft' check (
    status in (
      'draft','customer_request','submitted','internal_review','awaiting_customer',
      'approved','rejected','in_execution','work_completed','awaiting_rapport','closed'
    )
  ),
  created_by_user_id uuid references auth.users(id) on delete set null,
  requested_by_customer_contact_id uuid references public.rf_customer_contacts(id) on delete set null,
  assigned_monteur_user_id uuid references auth.users(id) on delete set null,
  current_version_no integer not null default 0 check (current_version_no >= 0),
  messerli_rapport_number text,
  work_completed_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index rf_regies_project_idx on public.rf_regies(project_id);
create index rf_regies_company_status_idx on public.rf_regies(company_id, status);

create table public.rf_regie_versions (
  id uuid primary key default gen_random_uuid(),
  regie_id uuid not null references public.rf_regies(id) on delete restrict,
  version_no integer not null check (version_no > 0),
  description text not null check (char_length(trim(description)) between 1 and 6000),
  estimate_label text not null check (char_length(trim(estimate_label)) between 1 and 200),
  estimate_minutes integer check (estimate_minutes is null or estimate_minutes > 0),
  estimate_disclaimer text not null default 'Unverbindliche Schätzung. Abrechnung nach effektivem Aufwand.',
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  locked_at timestamptz,
  unique(regie_id, version_no)
);
create index rf_regie_versions_regie_idx on public.rf_regie_versions(regie_id, version_no desc);

create table public.rf_regie_files (
  id uuid primary key default gen_random_uuid(),
  regie_id uuid not null references public.rf_regies(id) on delete restrict,
  version_id uuid references public.rf_regie_versions(id) on delete restrict,
  kind text not null check (kind in ('before','after','attachment')),
  storage_path text not null,
  original_filename text,
  mime_type text,
  byte_size bigint check (byte_size is null or byte_size >= 0),
  sha256 text,
  sort_order integer not null default 0,
  uploaded_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (kind <> 'before' or version_id is not null)
);
create index rf_regie_files_regie_idx on public.rf_regie_files(regie_id, kind);

create table public.rf_internal_reviews (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.rf_regie_versions(id) on delete restrict,
  reviewer_user_id uuid not null references auth.users(id) on delete restrict,
  decision text not null check (decision in ('approved','rejected')),
  reviewed_at timestamptz not null default now(),
  note text
);

create table public.rf_customer_signatures (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.rf_regie_versions(id) on delete restrict,
  customer_contact_id uuid references public.rf_customer_contacts(id) on delete restrict,
  signer_user_id uuid references auth.users(id) on delete set null,
  signer_name text not null check (char_length(trim(signer_name)) between 1 and 180),
  decision text not null check (decision in ('approved','rejected')),
  signature_storage_path text,
  document_sha256 text,
  auth_method text not null default 'account_or_secure_link',
  ip_address inet,
  user_agent text,
  signed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (
    (decision = 'approved' and signature_storage_path is not null)
    or decision = 'rejected'
  )
);
create unique index rf_customer_signature_approved_once_uidx
  on public.rf_customer_signatures(version_id)
  where decision = 'approved';

create table public.rf_documents (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.rf_regie_versions(id) on delete restrict,
  document_type text not null default 'signed_regie_pdf' check (document_type in ('signed_regie_pdf','evidence_export')),
  storage_path text not null,
  file_name text not null,
  mime_type text not null default 'application/pdf',
  byte_size bigint check (byte_size is null or byte_size >= 0),
  sha256 text not null,
  generated_at timestamptz not null default now(),
  locked_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index rf_documents_version_idx on public.rf_documents(version_id);

create table public.rf_regie_comments (
  id uuid primary key default gen_random_uuid(),
  regie_id uuid not null references public.rf_regies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_customer_contact_id uuid references public.rf_customer_contacts(id) on delete set null,
  body text not null check (char_length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now(),
  check ((actor_user_id is not null) <> (actor_customer_contact_id is not null))
);

create table public.rf_notifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete cascade,
  recipient_user_id uuid references auth.users(id) on delete cascade,
  recipient_customer_contact_id uuid references public.rf_customer_contacts(id) on delete cascade,
  regie_id uuid references public.rf_regies(id) on delete cascade,
  type text not null,
  title text not null,
  body text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check ((recipient_user_id is not null) <> (recipient_customer_contact_id is not null))
);
create index rf_notifications_user_idx
  on public.rf_notifications(recipient_user_id, read_at, created_at desc);
create index rf_notifications_customer_idx
  on public.rf_notifications(recipient_customer_contact_id, read_at, created_at desc);

create table public.rf_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  customer_contact_id uuid references public.rf_customer_contacts(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((user_id is not null) <> (customer_contact_id is not null))
);

create table public.rf_audit_log (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.rf_companies(id) on delete restrict,
  project_id uuid references public.rf_projects(id) on delete restrict,
  regie_id uuid references public.rf_regies(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_customer_contact_id uuid references public.rf_customer_contacts(id) on delete set null,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index rf_audit_company_created_idx on public.rf_audit_log(company_id, created_at desc);
create index rf_audit_regie_created_idx on public.rf_audit_log(regie_id, created_at desc);

create table public.rf_company_billing (
  company_id uuid primary key references public.rf_companies(id) on delete cascade,
  plan text not null default 'development' check (plan in ('development','starter','team','business','enterprise')),
  included_internal_profiles integer not null default 999999 check (included_internal_profiles >= 0),
  additional_profile_price_chf numeric(8,2),
  stripe_customer_id text,
  stripe_subscription_id text,
  subscription_status text not null default 'development',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.rf_assign_regie_code()
returns trigger language plpgsql as $$
begin
  if new.regie_code is null or btrim(new.regie_code) = '' then
    new.regie_code := 'RF-' || to_char(now(),'YYYY') || '-' ||
      upper(substr(replace(new.id::text,'-',''),1,8));
  end if;
  return new;
end
$$;

create trigger rf_assign_regie_code_trg
before insert on public.rf_regies
for each row execute function public.rf_assign_regie_code();

create or replace function public.rf_validate_regie_company()
returns trigger language plpgsql as $$
declare
  p_company uuid;
begin
  select company_id into p_company from public.rf_projects where id = new.project_id;
  if p_company is null then raise exception 'Unknown project'; end if;
  if p_company <> new.company_id then raise exception 'Regie company must match project company'; end if;
  if new.requested_by_customer_contact_id is not null and not exists (
    select 1 from public.rf_customer_contacts c
    where c.id = new.requested_by_customer_contact_id and c.company_id = new.company_id
  ) then
    raise exception 'Customer contact must belong to the same company';
  end if;
  return new;
end
$$;

create trigger rf_validate_regie_company_trg
before insert or update of company_id, project_id, requested_by_customer_contact_id
on public.rf_regies
for each row execute function public.rf_validate_regie_company();

create or replace function public.rf_block_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'This record is append-only and cannot be modified or deleted';
end
$$;

create trigger rf_customer_signatures_immutable
before update or delete on public.rf_customer_signatures
for each row execute function public.rf_block_mutation();

create trigger rf_documents_immutable
before update or delete on public.rf_documents
for each row execute function public.rf_block_mutation();

create trigger rf_audit_immutable
before update or delete on public.rf_audit_log
for each row execute function public.rf_block_mutation();

create or replace function public.rf_protect_locked_version()
returns trigger language plpgsql as $$
begin
  if old.locked_at is not null then
    raise exception 'Locked Regie versions are immutable';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

create trigger rf_locked_version_immutable
before update or delete on public.rf_regie_versions
for each row execute function public.rf_protect_locked_version();

create trigger rf_companies_updated_at before update on public.rf_companies
for each row execute function public.rf_set_updated_at();
create trigger rf_roles_updated_at before update on public.rf_roles
for each row execute function public.rf_set_updated_at();
create trigger rf_memberships_updated_at before update on public.rf_memberships
for each row execute function public.rf_set_updated_at();
create trigger rf_customer_contacts_updated_at before update on public.rf_customer_contacts
for each row execute function public.rf_set_updated_at();
create trigger rf_projects_updated_at before update on public.rf_projects
for each row execute function public.rf_set_updated_at();
create trigger rf_regies_updated_at before update on public.rf_regies
for each row execute function public.rf_set_updated_at();
create trigger rf_push_subscriptions_updated_at before update on public.rf_push_subscriptions
for each row execute function public.rf_set_updated_at();
create trigger rf_company_billing_updated_at before update on public.rf_company_billing
for each row execute function public.rf_set_updated_at();

create or replace function public.rf_is_internal_member(p_company uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.rf_companies c
    where c.id = p_company and c.primary_owner_user_id = auth.uid()
  ) or exists (
    select 1 from public.rf_memberships m
    where m.company_id = p_company and m.user_id = auth.uid() and m.active
  );
$$;

create or replace function public.rf_has_permission(p_company uuid, p_permission text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_override jsonb;
  v_permissions text[];
begin
  if exists (
    select 1 from public.rf_companies c
    where c.id = p_company and c.primary_owner_user_id = auth.uid()
  ) then
    return true;
  end if;

  select m.permission_overrides, coalesce(r.permissions, '{}'::text[])
    into v_override, v_permissions
  from public.rf_memberships m
  left join public.rf_roles r on r.id = m.role_id
  where m.company_id = p_company and m.user_id = auth.uid() and m.active
  limit 1;

  if not found then return false; end if;
  if v_override ? p_permission then
    return coalesce((v_override ->> p_permission)::boolean, false);
  end if;
  return p_permission = any(v_permissions);
end
$$;

create or replace function public.rf_customer_contact_for_company(p_company uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select c.id from public.rf_customer_contacts c
  where c.company_id = p_company and c.auth_user_id = auth.uid() and c.active
  limit 1;
$$;

create or replace function public.rf_customer_has_project(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.rf_project_customer_access a
    join public.rf_customer_contacts c on c.id = a.customer_contact_id
    where a.project_id = p_project and c.auth_user_id = auth.uid() and c.active
  );
$$;

create or replace function public.rf_customer_can_sign_project(p_project uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.rf_project_customer_access a
    join public.rf_customer_contacts c on c.id = a.customer_contact_id
    where a.project_id = p_project and a.can_sign and c.auth_user_id = auth.uid() and c.active
  );
$$;

grant execute on function public.rf_is_internal_member(uuid) to authenticated;
grant execute on function public.rf_has_permission(uuid,text) to authenticated;
grant execute on function public.rf_customer_contact_for_company(uuid) to authenticated;
grant execute on function public.rf_customer_has_project(uuid) to authenticated;
grant execute on function public.rf_customer_can_sign_project(uuid) to authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values
  ('rf-private','rf-private',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf']),
  ('rf-branding','rf-branding',false,5242880,array['image/jpeg','image/png','image/webp','image/svg+xml'])
on conflict (id) do nothing;


-- 20261001071337 regieflow_rls_v1

alter table public.rf_companies enable row level security;
alter table public.rf_roles enable row level security;
alter table public.rf_memberships enable row level security;
alter table public.rf_customer_contacts enable row level security;
alter table public.rf_projects enable row level security;
alter table public.rf_project_customer_access enable row level security;
alter table public.rf_regies enable row level security;
alter table public.rf_regie_versions enable row level security;
alter table public.rf_regie_files enable row level security;
alter table public.rf_internal_reviews enable row level security;
alter table public.rf_customer_signatures enable row level security;
alter table public.rf_documents enable row level security;
alter table public.rf_regie_comments enable row level security;
alter table public.rf_notifications enable row level security;
alter table public.rf_push_subscriptions enable row level security;
alter table public.rf_audit_log enable row level security;
alter table public.rf_company_billing enable row level security;

create policy rf_companies_select on public.rf_companies
for select to authenticated
using (
  public.rf_is_internal_member(id)
  or public.rf_customer_contact_for_company(id) is not null
);
create policy rf_companies_update on public.rf_companies
for update to authenticated
using (public.rf_has_permission(id,'company.manage'))
with check (public.rf_has_permission(id,'company.manage'));

create policy rf_roles_select on public.rf_roles
for select to authenticated
using (public.rf_is_internal_member(company_id));
create policy rf_roles_write on public.rf_roles
for all to authenticated
using (public.rf_has_permission(company_id,'roles.manage'))
with check (public.rf_has_permission(company_id,'roles.manage'));

create policy rf_memberships_select on public.rf_memberships
for select to authenticated
using (public.rf_is_internal_member(company_id));
create policy rf_memberships_write on public.rf_memberships
for all to authenticated
using (public.rf_has_permission(company_id,'users.manage'))
with check (public.rf_has_permission(company_id,'users.manage'));

create policy rf_customer_contacts_select on public.rf_customer_contacts
for select to authenticated
using (
  public.rf_has_permission(company_id,'projects.view')
  or auth_user_id = auth.uid()
);
create policy rf_customer_contacts_write on public.rf_customer_contacts
for all to authenticated
using (public.rf_has_permission(company_id,'projects.manage'))
with check (public.rf_has_permission(company_id,'projects.manage'));

create policy rf_projects_select on public.rf_projects
for select to authenticated
using (
  public.rf_has_permission(company_id,'projects.view')
  or public.rf_customer_has_project(id)
);
create policy rf_projects_write on public.rf_projects
for all to authenticated
using (public.rf_has_permission(company_id,'projects.manage'))
with check (public.rf_has_permission(company_id,'projects.manage'));

create policy rf_project_customer_access_select on public.rf_project_customer_access
for select to authenticated
using (
  exists (
    select 1 from public.rf_projects p
    where p.id = project_id
      and public.rf_has_permission(p.company_id,'projects.view')
  )
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id = customer_contact_id and c.auth_user_id = auth.uid()
  )
);
create policy rf_project_customer_access_write on public.rf_project_customer_access
for all to authenticated
using (
  exists (
    select 1 from public.rf_projects p
    where p.id = project_id
      and public.rf_has_permission(p.company_id,'projects.manage')
  )
)
with check (
  exists (
    select 1 from public.rf_projects p
    where p.id = project_id
      and public.rf_has_permission(p.company_id,'projects.manage')
  )
);

create policy rf_regies_select on public.rf_regies
for select to authenticated
using (
  public.rf_has_permission(company_id,'regies.view')
  or public.rf_customer_has_project(project_id)
);
create policy rf_regies_insert on public.rf_regies
for insert to authenticated
with check (
  public.rf_has_permission(company_id,'regies.create')
  or (
    source = 'customer'
    and status = 'customer_request'
    and public.rf_customer_has_project(project_id)
    and requested_by_customer_contact_id = public.rf_customer_contact_for_company(company_id)
  )
);
create policy rf_regies_update_internal on public.rf_regies
for update to authenticated
using (
  public.rf_has_permission(company_id,'regies.create')
  or public.rf_has_permission(company_id,'regies.review')
  or public.rf_has_permission(company_id,'regies.complete')
  or public.rf_has_permission(company_id,'regies.close')
)
with check (
  public.rf_has_permission(company_id,'regies.create')
  or public.rf_has_permission(company_id,'regies.review')
  or public.rf_has_permission(company_id,'regies.complete')
  or public.rf_has_permission(company_id,'regies.close')
);

create policy rf_versions_select on public.rf_regie_versions
for select to authenticated
using (
  exists (
    select 1 from public.rf_regies r
    where r.id = regie_id
      and (
        public.rf_has_permission(r.company_id,'regies.view')
        or public.rf_customer_has_project(r.project_id)
      )
  )
);
create policy rf_versions_insert on public.rf_regie_versions
for insert to authenticated
with check (
  exists (
    select 1 from public.rf_regies r
    where r.id = regie_id and (
      public.rf_has_permission(r.company_id,'regies.create')
      or (
        r.source = 'customer'
        and r.status = 'customer_request'
        and r.requested_by_customer_contact_id = public.rf_customer_contact_for_company(r.company_id)
      )
    )
  )
);
create policy rf_versions_update_unlocked on public.rf_regie_versions
for update to authenticated
using (
  locked_at is null
  and exists (
    select 1 from public.rf_regies r
    where r.id = regie_id
      and public.rf_has_permission(r.company_id,'regies.create')
  )
)
with check (
  locked_at is null
  and exists (
    select 1 from public.rf_regies r
    where r.id = regie_id
      and public.rf_has_permission(r.company_id,'regies.create')
  )
);

create policy rf_files_select on public.rf_regie_files
for select to authenticated
using (
  exists (
    select 1 from public.rf_regies r
    where r.id = regie_id
      and (
        public.rf_has_permission(r.company_id,'regies.view')
        or public.rf_customer_has_project(r.project_id)
      )
  )
);
create policy rf_files_insert on public.rf_regie_files
for insert to authenticated
with check (
  exists (
    select 1 from public.rf_regies r
    where r.id = regie_id
      and (
        public.rf_has_permission(r.company_id,'regies.create')
        or (
          r.source='customer'
          and r.status='customer_request'
          and r.requested_by_customer_contact_id = public.rf_customer_contact_for_company(r.company_id)
        )
      )
  )
);

create policy rf_internal_reviews_select on public.rf_internal_reviews
for select to authenticated
using (
  exists (
    select 1 from public.rf_regie_versions v
    join public.rf_regies r on r.id=v.regie_id
    where v.id=version_id and public.rf_is_internal_member(r.company_id)
  )
);
create policy rf_internal_reviews_insert on public.rf_internal_reviews
for insert to authenticated
with check (
  reviewer_user_id = auth.uid()
  and exists (
    select 1 from public.rf_regie_versions v
    join public.rf_regies r on r.id=v.regie_id
    where v.id=version_id and public.rf_has_permission(r.company_id,'regies.review')
  )
);

create policy rf_customer_signatures_select on public.rf_customer_signatures
for select to authenticated
using (
  exists (
    select 1 from public.rf_regie_versions v
    join public.rf_regies r on r.id=v.regie_id
    where v.id=version_id
      and (
        public.rf_has_permission(r.company_id,'documents.view')
        or public.rf_customer_has_project(r.project_id)
      )
  )
);
create policy rf_customer_signatures_insert on public.rf_customer_signatures
for insert to authenticated
with check (
  signer_user_id = auth.uid()
  and exists (
    select 1 from public.rf_regie_versions v
    join public.rf_regies r on r.id=v.regie_id
    where v.id=version_id
      and public.rf_customer_can_sign_project(r.project_id)
  )
);

create policy rf_documents_select on public.rf_documents
for select to authenticated
using (
  exists (
    select 1 from public.rf_regie_versions v
    join public.rf_regies r on r.id=v.regie_id
    where v.id=version_id
      and (
        public.rf_has_permission(r.company_id,'documents.view')
        or public.rf_customer_has_project(r.project_id)
      )
  )
);

create policy rf_comments_select on public.rf_regie_comments
for select to authenticated
using (
  exists (
    select 1 from public.rf_regies r
    where r.id=regie_id
      and (
        public.rf_has_permission(r.company_id,'regies.view')
        or public.rf_customer_has_project(r.project_id)
      )
  )
);
create policy rf_comments_insert on public.rf_regie_comments
for insert to authenticated
with check (
  (actor_user_id = auth.uid() and exists (
    select 1 from public.rf_regies r
    where r.id=regie_id and public.rf_is_internal_member(r.company_id)
  ))
  or
  (actor_customer_contact_id is not null and exists (
    select 1 from public.rf_regies r
    join public.rf_customer_contacts c on c.id=actor_customer_contact_id
    where r.id=regie_id
      and c.auth_user_id=auth.uid()
      and public.rf_customer_has_project(r.project_id)
  ))
);

create policy rf_notifications_select on public.rf_notifications
for select to authenticated
using (
  recipient_user_id = auth.uid()
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=recipient_customer_contact_id and c.auth_user_id=auth.uid()
  )
);
create policy rf_notifications_update on public.rf_notifications
for update to authenticated
using (
  recipient_user_id = auth.uid()
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=recipient_customer_contact_id and c.auth_user_id=auth.uid()
  )
)
with check (
  recipient_user_id = auth.uid()
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=recipient_customer_contact_id and c.auth_user_id=auth.uid()
  )
);

create policy rf_push_subscriptions_own on public.rf_push_subscriptions
for all to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=customer_contact_id and c.auth_user_id=auth.uid()
  )
)
with check (
  user_id = auth.uid()
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=customer_contact_id and c.auth_user_id=auth.uid()
  )
);

create policy rf_audit_select on public.rf_audit_log
for select to authenticated
using (
  public.rf_has_permission(company_id,'documents.view')
  or (
    project_id is not null and public.rf_customer_has_project(project_id)
  )
);

create policy rf_billing_select on public.rf_company_billing
for select to authenticated
using (public.rf_has_permission(company_id,'billing.manage'));
create policy rf_billing_write on public.rf_company_billing
for all to authenticated
using (public.rf_has_permission(company_id,'billing.manage'))
with check (public.rf_has_permission(company_id,'billing.manage'));


-- 20261001071456 regieflow_workflows_v1

alter table public.rf_regies
  add column request_description text,
  add column request_created_at timestamptz;

alter table public.rf_regies
  add constraint rf_customer_request_description_chk
  check (
    source <> 'customer'
    or (request_description is not null and char_length(trim(request_description)) between 1 and 6000)
  );

create table public.rf_public_approval_links (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete restrict,
  version_id uuid not null references public.rf_regie_versions(id) on delete restrict,
  customer_contact_id uuid references public.rf_customer_contacts(id) on delete restrict,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index rf_public_approval_links_version_idx
  on public.rf_public_approval_links(version_id, expires_at desc);
alter table public.rf_public_approval_links enable row level security;

create policy rf_public_links_internal_select on public.rf_public_approval_links
for select to authenticated
using (public.rf_has_permission(company_id,'regies.view'));

create or replace function public.rf_submit_regie_version(p_regie_id uuid, p_version_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version public.rf_regie_versions%rowtype;
  v_workflow text;
  v_next_status text;
begin
  select * into v_regie from public.rf_regies where id=p_regie_id for update;
  if not found then raise exception 'Regie not found'; end if;

  if not public.rf_has_permission(v_regie.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;

  select * into v_version
  from public.rf_regie_versions
  where id=p_version_id and regie_id=p_regie_id
  for update;
  if not found then raise exception 'Version not found'; end if;
  if v_version.locked_at is not null then raise exception 'Version already locked'; end if;

  if not exists (
    select 1 from public.rf_regie_files f
    where f.regie_id=p_regie_id
      and f.version_id=p_version_id
      and f.kind='before'
  ) then
    raise exception 'At least one before-work photo is required';
  end if;

  update public.rf_regie_versions
  set submitted_at=now(), locked_at=now()
  where id=p_version_id;

  select approval_workflow into v_workflow
  from public.rf_projects where id=v_regie.project_id;

  if v_workflow='office_then_customer' then
    v_next_status := 'internal_review';
  else
    v_next_status := 'awaiting_customer';
  end if;

  update public.rf_regies
  set status=v_next_status,
      current_version_no=v_version.version_no,
      updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values (
    v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),
    'regie_version_submitted',
    jsonb_build_object('version_id',p_version_id,'version_no',v_version.version_no,'workflow',v_workflow)
  );

  return v_next_status;
end
$$;
grant execute on function public.rf_submit_regie_version(uuid,uuid) to authenticated;

create or replace function public.rf_review_regie_version(
  p_version_id uuid,
  p_decision text,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_status text;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select r.* into v_regie
  from public.rf_regies r
  join public.rf_regie_versions v on v.regie_id=r.id
  where v.id=p_version_id
  for update of r;

  if not found then raise exception 'Version not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.review') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'internal_review' then
    raise exception 'Regie is not awaiting internal review';
  end if;

  insert into public.rf_internal_reviews(version_id,reviewer_user_id,decision,note)
  values(p_version_id,auth.uid(),p_decision,p_note);

  v_status := case when p_decision='approved' then 'awaiting_customer' else 'rejected' end;

  update public.rf_regies
  set status=v_status,updated_at=now()
  where id=v_regie.id;

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values(v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
         'internal_review_'||p_decision,
         jsonb_build_object('version_id',p_version_id));

  return v_status;
end
$$;
grant execute on function public.rf_review_regie_version(uuid,text,text) to authenticated;

create or replace function public.rf_start_execution(p_regie_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
begin
  select * into v_regie from public.rf_regies where id=p_regie_id for update;
  if not found then raise exception 'Regie not found'; end if;
  if not (
    public.rf_has_permission(v_regie.company_id,'regies.create')
    or public.rf_has_permission(v_regie.company_id,'regies.complete')
  ) then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'approved' then
    raise exception 'Regie must be approved first';
  end if;

  update public.rf_regies set status='in_execution',updated_at=now() where id=p_regie_id;
  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type)
  values(v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),'work_started');

  return 'in_execution';
end
$$;
grant execute on function public.rf_start_execution(uuid) to authenticated;

create or replace function public.rf_mark_work_completed(p_regie_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
begin
  select * into v_regie from public.rf_regies where id=p_regie_id for update;
  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.complete') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status not in ('approved','in_execution') then
    raise exception 'Regie is not in an executable state';
  end if;

  update public.rf_regies
  set status='awaiting_rapport', work_completed_at=now(), updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type)
  values(v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),'work_completed');

  return 'awaiting_rapport';
end
$$;
grant execute on function public.rf_mark_work_completed(uuid) to authenticated;

create or replace function public.rf_close_regie(p_regie_id uuid, p_messerli_rapport_number text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
begin
  if p_messerli_rapport_number is null or btrim(p_messerli_rapport_number)='' then
    raise exception 'Messerli rapport number is required';
  end if;

  select * into v_regie from public.rf_regies where id=p_regie_id for update;
  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.close') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_rapport' then
    raise exception 'Regie is not awaiting a rapport number';
  end if;

  update public.rf_regies
  set messerli_rapport_number=btrim(p_messerli_rapport_number),
      status='closed',closed_at=now(),updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values(v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),'regie_closed',
         jsonb_build_object('messerli_rapport_number',btrim(p_messerli_rapport_number)));

  return 'closed';
end
$$;
grant execute on function public.rf_close_regie(uuid,text) to authenticated;

create or replace function public.rf_create_public_approval_link(
  p_version_id uuid,
  p_customer_contact_id uuid,
  p_valid_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_token text;
begin
  if p_valid_hours < 1 or p_valid_hours > 720 then
    raise exception 'Link validity must be between 1 and 720 hours';
  end if;

  select r.* into v_regie
  from public.rf_regies r
  join public.rf_regie_versions v on v.regie_id=r.id
  where v.id=p_version_id;

  if not found then raise exception 'Version not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_customer' then
    raise exception 'Regie is not awaiting customer approval';
  end if;
  if not exists (
    select 1 from public.rf_project_customer_access a
    where a.project_id=v_regie.project_id
      and a.customer_contact_id=p_customer_contact_id
      and a.can_sign
  ) then
    raise exception 'Customer is not authorized to sign this project';
  end if;

  v_token := encode(gen_random_bytes(32),'hex');

  insert into public.rf_public_approval_links(
    company_id,version_id,customer_contact_id,token_hash,expires_at,created_by_user_id
  )
  values(
    v_regie.company_id,p_version_id,p_customer_contact_id,
    encode(digest(v_token,'sha256'),'hex'),
    now() + make_interval(hours => p_valid_hours),
    auth.uid()
  );

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values(v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
         'public_approval_link_created',
         jsonb_build_object('version_id',p_version_id,'valid_hours',p_valid_hours));

  return v_token;
end
$$;
grant execute on function public.rf_create_public_approval_link(uuid,uuid,integer) to authenticated;

create or replace function public.rf_notify_regie_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' or new.status is not distinct from old.status then
    return new;
  end if;

  if new.status in ('customer_request','internal_review','awaiting_customer','approved','rejected','awaiting_rapport','closed') then
    insert into public.rf_notifications(company_id,recipient_user_id,regie_id,type,title,body)
    select new.company_id, x.user_id, new.id, 'regie_status',
           'Regie '||coalesce(new.regie_code,'')||': '||new.status,
           'Der Status wurde auf "'||new.status||'" geändert.'
    from (
      select c.primary_owner_user_id as user_id
      from public.rf_companies c where c.id=new.company_id
      union
      select m.user_id
      from public.rf_memberships m
      left join public.rf_roles rr on rr.id=m.role_id
      where m.company_id=new.company_id and m.active
        and (
          (m.permission_overrides ? 'regies.review' and (m.permission_overrides->>'regies.review')::boolean)
          or 'regies.review'=any(coalesce(rr.permissions,'{}'::text[]))
          or m.user_id=new.assigned_monteur_user_id
        )
    ) x
    where x.user_id is not null
    on conflict do nothing;
  end if;

  if new.status='awaiting_customer' then
    insert into public.rf_notifications(company_id,recipient_customer_contact_id,regie_id,type,title,body)
    select new.company_id, a.customer_contact_id, new.id, 'approval_required',
           'Freigabe erforderlich',
           'Eine Regie wartet auf Ihre Freigabe.'
    from public.rf_project_customer_access a
    where a.project_id=new.project_id and a.can_sign;
  elsif new.status in ('approved','rejected','closed') then
    insert into public.rf_notifications(company_id,recipient_customer_contact_id,regie_id,type,title,body)
    select new.company_id, a.customer_contact_id, new.id, 'regie_status',
           'Regie '||coalesce(new.regie_code,'')||': '||new.status,
           'Der Status wurde auf "'||new.status||'" geändert.'
    from public.rf_project_customer_access a
    where a.project_id=new.project_id;
  end if;

  return new;
end
$$;

create trigger rf_notify_regie_status_change_trg
after update of status on public.rf_regies
for each row execute function public.rf_notify_regie_status_change();


-- 20261001071545 regieflow_security_hardening_v1

alter function public.rf_set_updated_at() set search_path = public;
alter function public.rf_assign_regie_code() set search_path = public;
alter function public.rf_validate_regie_company() set search_path = public;
alter function public.rf_block_mutation() set search_path = public;
alter function public.rf_protect_locked_version() set search_path = public;

revoke all on function public.rf_set_updated_at() from public, anon, authenticated;
revoke all on function public.rf_assign_regie_code() from public, anon, authenticated;
revoke all on function public.rf_validate_regie_company() from public, anon, authenticated;
revoke all on function public.rf_block_mutation() from public, anon, authenticated;
revoke all on function public.rf_protect_locked_version() from public, anon, authenticated;
revoke all on function public.rf_notify_regie_status_change() from public, anon, authenticated;

revoke all on function public.rf_is_internal_member(uuid) from public, anon;
revoke all on function public.rf_has_permission(uuid,text) from public, anon;
revoke all on function public.rf_customer_contact_for_company(uuid) from public, anon;
revoke all on function public.rf_customer_has_project(uuid) from public, anon;
revoke all on function public.rf_customer_can_sign_project(uuid) from public, anon;
revoke all on function public.rf_submit_regie_version(uuid,uuid) from public, anon;
revoke all on function public.rf_review_regie_version(uuid,text,text) from public, anon;
revoke all on function public.rf_start_execution(uuid) from public, anon;
revoke all on function public.rf_mark_work_completed(uuid) from public, anon;
revoke all on function public.rf_close_regie(uuid,text) from public, anon;
revoke all on function public.rf_create_public_approval_link(uuid,uuid,integer) from public, anon;

grant execute on function public.rf_is_internal_member(uuid) to authenticated;
grant execute on function public.rf_has_permission(uuid,text) to authenticated;
grant execute on function public.rf_customer_contact_for_company(uuid) to authenticated;
grant execute on function public.rf_customer_has_project(uuid) to authenticated;
grant execute on function public.rf_customer_can_sign_project(uuid) to authenticated;
grant execute on function public.rf_submit_regie_version(uuid,uuid) to authenticated;
grant execute on function public.rf_review_regie_version(uuid,text,text) to authenticated;
grant execute on function public.rf_start_execution(uuid) to authenticated;
grant execute on function public.rf_mark_work_completed(uuid) to authenticated;
grant execute on function public.rf_close_regie(uuid,text) to authenticated;
grant execute on function public.rf_create_public_approval_link(uuid,uuid,integer) to authenticated;

drop policy if exists rf_customer_signatures_insert on public.rf_customer_signatures;

create index if not exists rf_companies_owner_idx on public.rf_companies(primary_owner_user_id);
create index if not exists rf_memberships_user_idx on public.rf_memberships(user_id);
create index if not exists rf_memberships_role_idx on public.rf_memberships(role_id);
create index if not exists rf_customer_contacts_auth_idx on public.rf_customer_contacts(auth_user_id);
create index if not exists rf_project_access_customer_idx on public.rf_project_customer_access(customer_contact_id);
create index if not exists rf_regies_creator_idx on public.rf_regies(created_by_user_id);
create index if not exists rf_regies_requester_idx on public.rf_regies(requested_by_customer_contact_id);
create index if not exists rf_regies_monteur_idx on public.rf_regies(assigned_monteur_user_id);
create index if not exists rf_versions_creator_idx on public.rf_regie_versions(created_by_user_id);
create index if not exists rf_files_version_idx on public.rf_regie_files(version_id);
create index if not exists rf_files_uploader_idx on public.rf_regie_files(uploaded_by_user_id);
create index if not exists rf_comments_regie_idx on public.rf_regie_comments(regie_id);
create index if not exists rf_notifications_company_idx on public.rf_notifications(company_id);
create index if not exists rf_notifications_regie_idx on public.rf_notifications(regie_id);
create index if not exists rf_public_links_company_idx on public.rf_public_approval_links(company_id);
create index if not exists rf_public_links_customer_idx on public.rf_public_approval_links(customer_contact_id);


-- 20261001071617 regieflow_private_dev_log_v1

create schema if not exists regieflow_private;

create table if not exists regieflow_private.dev_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  kind text not null check (kind in ('requirements','decision','completed','next','note')),
  title text not null,
  content text not null
);

revoke all on schema regieflow_private from public, anon, authenticated;
revoke all on all tables in schema regieflow_private from public, anon, authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('requirements','RegieFlow product requirements snapshot 2026-10-01',
'RegieFlow is a simple but unrestricted web app for digital Regie approval and evidence management, intended as an extension alongside Messerli/Bexio.

AREAS
- Büro, Monteur, Kunde.
- Customers are always free and do not count as paid profiles.
- Customers have accounts/dashboard and may create Regie requests inside assigned existing projects, but cannot create projects.

ACCOUNTS / RIGHTS
- Each company has one Primary Owner.
- Owner manually creates internal users.
- Roles are not hard-coded; Owner freely names roles and assigns granular permissions.
- Project-specific authorized approvers are configured per construction site/project.

PROJECTS / WORKFLOW
- Every Regie belongs to a project.
- Project metadata mirrors Messerli where relevant, including Bauherr and Messerli project number.
- Workflow varies per project:
  A) Monteur -> Büro review -> Kunde signs
  B) Monteur -> Büro and Kunde simultaneously -> Kunde signs.
- Customer-created request must be internally confirmed by Büro or a Monteur with approval rights.
- Before closing a completed Regie, Messerli Rapportnummer is mandatory.

REGIE CONTENT
- At least one mandatory before-work photo.
- Description.
- Estimated duration explicitly non-binding.
- Multiple before photos allowed.
- After-work photos optional.
- Once submitted, that version cannot be edited; changes require a new version and approval cycle.
- Rejection does not require a reason.

CUSTOMER EXPERIENCE
- In-app/push notifications only for Regie workflow, no SMS/email workflow.
- Customer dashboard: Open, In progress, Archive.
- Customer can open archived signed PDFs and review before/after photos.
- Customer may sign from account or secure external approval link.

DOCUMENT / SECURITY
- Signed PDF immutable/read-only after approval.
- PDF must include Regie-ID, project/project number, company, company logo/branding, Monteur, description, images, non-binding estimate, customer name, signature, date/time, document version.
- PDF must be portable and suitable for upload into Messerli, Bexio and comparable systems.
- Store SHA-256/document integrity information and append-only audit trail.
- Signed versions are never overwritten.

STATE MODEL
Draft -> Submitted -> optional Internal review -> Awaiting customer -> Approved/Signed or Rejected -> In execution -> Work completed -> Awaiting Messerli rapport number -> Closed.

PRICING
- Starter: 3 internal profiles, target CHF 29/month.
- Team: 10 internal profiles, target CHF 59/month.
- Business: 50 internal profiles, target CHF 199/month.
- Extra internal profiles approx CHF 6/5/4 depending on tier/volume.
- Customers, projects, Regien and customer archive are not usage-metered.
- Stripe billing only after core product is ready.
- Keep development/hosting effectively free until paying customers exist.'),

('completed','Backend foundation created in shared DriveLoop Supabase project',
'RegieFlow is isolated from DriveLoop using rf_ prefixed public tables and regieflow_private internal schema. Core company, role, membership, customer, project, Regie, version, file, review, signature, document, comments, notifications, push subscription, audit and billing tables created. RLS enabled. Secure helper functions and workflow RPCs created. Private Storage buckets rf-private and rf-branding created. Secure external approval link token table and token creation RPC created. Signed evidence tables are append-only; locked versions are immutable. Regie submission enforces at least one before-work photo. Messerli rapport number required by close RPC.'),

('completed','Security hardening pass',
'Revoked anonymous access to SECURITY DEFINER functions, set safe search_path on trigger functions, removed direct customer signature INSERT policy so signatures must go through controlled finalization logic, and added key foreign-key/query indexes.'),

('next','Next build steps',
'1. Add Storage RLS policies for Regie photos/PDFs and company branding.
2. Add controlled customer-signature finalization path and secure public approval Edge Function.
3. Generate immutable branded PDF server-side and hash it before finalization.
4. Add authenticated customer approval Edge Function.
5. Build company bootstrap/onboarding flow and user invitation/creation flow.
6. Wire production frontend to Supabase.
7. Add PWA push service worker and push subscription delivery.
8. Test complete workflows with seeded dev data.
9. Stripe last.');


-- 20261001071638 regieflow_storage_rls_v1

create or replace function public.rf_storage_segment_uuid(p_name text, p_pos integer)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
declare
  v text;
begin
  if p_pos < 1 then return null; end if;
  v := split_part(p_name,'/',p_pos);
  begin
    return v::uuid;
  exception when others then
    return null;
  end;
end
$$;

revoke all on function public.rf_storage_segment_uuid(text,integer) from public, anon;
grant execute on function public.rf_storage_segment_uuid(text,integer) to authenticated;

create policy rf_private_select
on storage.objects for select to authenticated
using (
  bucket_id='rf-private'
  and exists (
    select 1
    from public.rf_regies r
    where r.company_id = public.rf_storage_segment_uuid(name,1)
      and r.id = public.rf_storage_segment_uuid(name,2)
      and (
        public.rf_has_permission(r.company_id,'regies.view')
        or public.rf_customer_has_project(r.project_id)
      )
  )
);

create policy rf_private_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='rf-private'
  and exists (
    select 1
    from public.rf_regies r
    where r.company_id = public.rf_storage_segment_uuid(name,1)
      and r.id = public.rf_storage_segment_uuid(name,2)
      and (
        public.rf_has_permission(r.company_id,'regies.create')
        or public.rf_has_permission(r.company_id,'regies.complete')
        or (
          r.source='customer'
          and r.status='customer_request'
          and r.requested_by_customer_contact_id = public.rf_customer_contact_for_company(r.company_id)
          and public.rf_customer_has_project(r.project_id)
        )
      )
  )
);

create policy rf_branding_select
on storage.objects for select to authenticated
using (
  bucket_id='rf-branding'
  and (
    public.rf_is_internal_member(public.rf_storage_segment_uuid(name,1))
    or public.rf_customer_contact_for_company(public.rf_storage_segment_uuid(name,1)) is not null
  )
);

create policy rf_branding_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='rf-branding'
  and public.rf_has_permission(public.rf_storage_segment_uuid(name,1),'company.manage')
);

create policy rf_branding_update
on storage.objects for update to authenticated
using (
  bucket_id='rf-branding'
  and public.rf_has_permission(public.rf_storage_segment_uuid(name,1),'company.manage')
)
with check (
  bucket_id='rf-branding'
  and public.rf_has_permission(public.rf_storage_segment_uuid(name,1),'company.manage')
);

create policy rf_branding_delete
on storage.objects for delete to authenticated
using (
  bucket_id='rf-branding'
  and public.rf_has_permission(public.rf_storage_segment_uuid(name,1),'company.manage')
);


-- 20261001071723 regieflow_customer_finalization_v1

create or replace function public.rf_finalize_customer_decision(
  p_version_id uuid,
  p_customer_contact_id uuid,
  p_signer_user_id uuid,
  p_signer_name text,
  p_decision text,
  p_signature_storage_path text,
  p_document_storage_path text,
  p_document_file_name text,
  p_document_sha256 text,
  p_document_byte_size bigint,
  p_auth_method text,
  p_ip_address text,
  p_user_agent text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version public.rf_regie_versions%rowtype;
  v_contact public.rf_customer_contacts%rowtype;
  v_ip inet;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select v.* into v_version
  from public.rf_regie_versions v
  where v.id=p_version_id;

  if not found then raise exception 'Version not found'; end if;
  if v_version.locked_at is null then raise exception 'Version is not locked/submitted'; end if;

  select * into v_regie
  from public.rf_regies
  where id=v_version.regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status <> 'awaiting_customer' then
    raise exception 'Regie is not awaiting customer approval';
  end if;

  select * into v_contact
  from public.rf_customer_contacts
  where id=p_customer_contact_id
    and company_id=v_regie.company_id
    and active;

  if not found then raise exception 'Customer contact not found'; end if;

  if not exists (
    select 1 from public.rf_project_customer_access a
    where a.project_id=v_regie.project_id
      and a.customer_contact_id=p_customer_contact_id
      and a.can_sign
  ) then
    raise exception 'Customer is not authorized to sign this project';
  end if;

  if p_signer_user_id is not null
     and v_contact.auth_user_id is distinct from p_signer_user_id then
    raise exception 'Signer account does not match customer contact';
  end if;

  if p_signer_name is null or btrim(p_signer_name)='' then
    raise exception 'Signer name is required';
  end if;

  if p_decision='approved' then
    if p_signature_storage_path is null or btrim(p_signature_storage_path)='' then
      raise exception 'Signature is required for approval';
    end if;
    if p_document_storage_path is null or p_document_sha256 is null or p_document_file_name is null then
      raise exception 'Final PDF and hash are required for approval';
    end if;
  end if;

  begin
    if p_ip_address is not null and btrim(p_ip_address)<>'' then
      v_ip := split_part(p_ip_address, ',', 1)::inet;
    end if;
  exception when others then
    v_ip := null;
  end;

  insert into public.rf_customer_signatures(
    version_id,customer_contact_id,signer_user_id,signer_name,decision,
    signature_storage_path,document_sha256,auth_method,ip_address,user_agent
  )
  values(
    p_version_id,p_customer_contact_id,p_signer_user_id,btrim(p_signer_name),p_decision,
    p_signature_storage_path,p_document_sha256,coalesce(nullif(p_auth_method,''),'unknown'),
    v_ip,p_user_agent
  );

  if p_decision='approved' then
    insert into public.rf_documents(
      version_id,document_type,storage_path,file_name,mime_type,byte_size,sha256
    )
    values(
      p_version_id,'signed_regie_pdf',p_document_storage_path,p_document_file_name,
      'application/pdf',p_document_byte_size,p_document_sha256
    );

    update public.rf_regies
    set status='approved',updated_at=now()
    where id=v_regie.id;
  else
    update public.rf_regies
    set status='rejected',updated_at=now()
    where id=v_regie.id;
  end if;

  if p_auth_method='secure_link' then
    update public.rf_public_approval_links
    set used_at=coalesce(used_at,now())
    where version_id=p_version_id
      and customer_contact_id=p_customer_contact_id
      and used_at is null
      and revoked_at is null;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,p_signer_user_id,p_customer_contact_id,
    'customer_'||p_decision,
    jsonb_build_object(
      'version_id',p_version_id,
      'version_no',v_version.version_no,
      'auth_method',p_auth_method,
      'document_sha256',p_document_sha256
    )
  );

  return case when p_decision='approved' then 'approved' else 'rejected' end;
end
$$;

revoke all on function public.rf_finalize_customer_decision(
  uuid,uuid,uuid,text,text,text,text,text,text,bigint,text,text,text
) from public, anon, authenticated;
grant execute on function public.rf_finalize_customer_decision(
  uuid,uuid,uuid,text,text,text,text,text,text,bigint,text,text,text
) to service_role;

insert into regieflow_private.dev_log(kind,title,content)
values('completed','Controlled customer finalization RPC added',
'Customer approval/rejection finalization is now service-role-only. It validates the locked submitted version, project-specific signing authority, signer identity, required signature/PDF/hash for approvals, records immutable signature evidence, stores immutable PDF metadata, updates Regie status and appends audit evidence. Direct customer INSERT into signature records remains disabled.');


-- 20261001072002 regieflow_onboarding_permissions_v1

create table public.rf_permission_catalog (
  key text primary key,
  category text not null,
  label_de text not null,
  description_de text not null,
  sort_order integer not null default 0
);
alter table public.rf_permission_catalog enable row level security;
create policy rf_permission_catalog_read on public.rf_permission_catalog
for select to authenticated using (true);

insert into public.rf_permission_catalog(key,category,label_de,description_de,sort_order) values
('company.manage','Firma','Firmeneinstellungen verwalten','Firmenname, Logo, Branding und Grundeinstellungen ändern.',10),
('users.manage','Benutzer','Benutzer verwalten','Interne Benutzer erstellen, deaktivieren und Rollen zuweisen.',20),
('roles.manage','Benutzer','Rollen & Rechte verwalten','Eigene Rollen erstellen, benennen und Berechtigungen festlegen.',30),
('projects.view','Projekte','Projekte ansehen','Projekte und zugeordnete Kundendaten ansehen.',40),
('projects.manage','Projekte','Projekte verwalten','Projekte erstellen, bearbeiten und Kunden/Freigabepersonen zuordnen.',50),
('regies.view','Regien','Regien ansehen','Regieaufträge, Versionen, Bilder und Status ansehen.',60),
('regies.create','Regien','Regien erstellen','Regieaufträge und neue Versionen erstellen und absenden.',70),
('regies.review','Regien','Regien intern bestätigen','Interne Büro-/Projektleiterprüfung durchführen.',80),
('regies.complete','Regien','Ausführung abschliessen','Ausführung starten/abschliessen und Nachherbilder hinzufügen.',90),
('regies.close','Regien','Regien schliessen','Messerli-Rapportnummer erfassen und Regien endgültig abschliessen.',100),
('documents.view','Dokumente','Dokumente ansehen','Signierte PDFs, Audit-Nachweise und Dokumenthistorie ansehen.',110),
('documents.export','Dokumente','Dokumente exportieren','PDFs für Messerli, Bexio und andere Systeme herunterladen/exportieren.',120),
('billing.manage','Abo','Abo & Abrechnung verwalten','Tarif, interne Profile und später Stripe-Abrechnung verwalten.',130);

create or replace function public.rf_bootstrap_company(p_company_name text, p_owner_display_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_company uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_company_name is null or btrim(p_company_name)='' then raise exception 'Company name required'; end if;
  if p_owner_display_name is null or btrim(p_owner_display_name)='' then raise exception 'Owner display name required'; end if;

  insert into public.rf_companies(name,primary_owner_user_id)
  values(btrim(p_company_name),v_uid)
  returning id into v_company;

  insert into public.rf_memberships(company_id,user_id,display_name,active,created_by)
  values(v_company,v_uid,btrim(p_owner_display_name),true,v_uid);

  insert into public.rf_company_billing(company_id,plan,included_internal_profiles,subscription_status)
  values(v_company,'development',999999,'development');

  insert into public.rf_audit_log(company_id,actor_user_id,event_type,metadata)
  values(v_company,v_uid,'company_created',jsonb_build_object('company_name',btrim(p_company_name)));

  return v_company;
end
$$;
revoke all on function public.rf_bootstrap_company(text,text) from public, anon;
grant execute on function public.rf_bootstrap_company(text,text) to authenticated;

drop policy if exists rf_regies_insert on public.rf_regies;
create policy rf_regies_insert_internal on public.rf_regies
for insert to authenticated
with check (public.rf_has_permission(company_id,'regies.create'));

create or replace function public.rf_create_customer_request(
  p_project_id uuid,
  p_description text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_contact uuid;
  v_company uuid;
  v_regie uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_description is null or char_length(btrim(p_description)) < 1 then
    raise exception 'Description required';
  end if;

  select p.company_id, c.id
    into v_company, v_contact
  from public.rf_projects p
  join public.rf_project_customer_access a on a.project_id=p.id
  join public.rf_customer_contacts c on c.id=a.customer_contact_id
  where p.id=p_project_id
    and p.active
    and c.auth_user_id=v_uid
    and c.active
  limit 1;

  if v_company is null or v_contact is null then
    raise exception 'Project not available to this customer';
  end if;

  insert into public.rf_regies(
    company_id,project_id,source,status,requested_by_customer_contact_id,
    request_description,request_created_at
  )
  values(
    v_company,p_project_id,'customer','customer_request',v_contact,
    btrim(p_description),now()
  )
  returning id into v_regie;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_company,p_project_id,v_regie,v_contact,'customer_request_created',
    jsonb_build_object('description',btrim(p_description))
  );

  return v_regie;
end
$$;
revoke all on function public.rf_create_customer_request(uuid,text) from public, anon;
grant execute on function public.rf_create_customer_request(uuid,text) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Onboarding and permission catalog',
'Added a UI-ready granular permission catalog with no hard-coded job roles. Added authenticated company bootstrap RPC that creates the Primary Owner membership, development/free billing record and audit event. Added controlled customer-request RPC so customers can create requests only inside projects assigned to their account; direct customer Regie INSERT was removed to keep audit/state transitions controlled.');


-- 20261001072153 regieflow_customer_invites_v1

create table public.rf_customer_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.rf_companies(id) on delete cascade,
  customer_contact_id uuid not null references public.rf_customer_contacts(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index rf_customer_invites_contact_idx on public.rf_customer_invites(customer_contact_id, expires_at desc);
alter table public.rf_customer_invites enable row level security;

create policy rf_customer_invites_internal_select on public.rf_customer_invites
for select to authenticated
using (
  public.rf_has_permission(company_id,'projects.manage')
  or public.rf_has_permission(company_id,'users.manage')
);

create or replace function public.rf_create_customer_invite(
  p_customer_contact_id uuid,
  p_valid_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_contact public.rf_customer_contacts%rowtype;
  v_token text;
begin
  if p_valid_hours < 1 or p_valid_hours > 720 then
    raise exception 'Invite validity must be between 1 and 720 hours';
  end if;

  select * into v_contact
  from public.rf_customer_contacts
  where id=p_customer_contact_id and active;

  if not found then raise exception 'Customer contact not found'; end if;

  if not (
    public.rf_has_permission(v_contact.company_id,'projects.manage')
    or public.rf_has_permission(v_contact.company_id,'users.manage')
  ) then
    raise exception 'Not allowed';
  end if;

  if v_contact.auth_user_id is not null then
    raise exception 'Customer already has an account';
  end if;

  v_token := encode(gen_random_bytes(32),'hex');

  insert into public.rf_customer_invites(
    company_id,customer_contact_id,token_hash,expires_at,created_by_user_id
  )
  values(
    v_contact.company_id,p_customer_contact_id,
    encode(digest(v_token,'sha256'),'hex'),
    now()+make_interval(hours=>p_valid_hours),
    auth.uid()
  );

  return v_token;
end
$$;

revoke all on function public.rf_create_customer_invite(uuid,integer) from public, anon;
grant execute on function public.rf_create_customer_invite(uuid,integer) to authenticated;

create or replace function public.rf_find_auth_user_by_email(p_email text)
returns uuid
language sql
security definer
set search_path = auth, public
as $$
  select u.id
  from auth.users u
  where lower(u.email)=lower(trim(p_email))
  limit 1;
$$;
revoke all on function public.rf_find_auth_user_by_email(text) from public, anon, authenticated;
grant execute on function public.rf_find_auth_user_by_email(text) to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Customer account invitation foundation',
'Added hashed one-time customer invite tokens. Office/authorized internal users can create an invite for an existing customer contact; the customer will later sign up for a free account and claim the invite. Added a service-role-only auth-user lookup by email to support internal account creation without duplicating users already present in the shared Supabase Auth project.');


-- 20261001072332 regieflow_pricing_catalog_v1

create table public.rf_plan_catalog (
  plan text primary key check (plan in ('starter','team','business')),
  label text not null,
  included_internal_profiles integer not null check (included_internal_profiles > 0),
  monthly_price_chf numeric(8,2) not null check (monthly_price_chf >= 0),
  extra_profile_price_chf numeric(8,2) not null check (extra_profile_price_chf >= 0),
  active boolean not null default true,
  sort_order integer not null
);
alter table public.rf_plan_catalog enable row level security;
create policy rf_plan_catalog_read on public.rf_plan_catalog
for select to authenticated using (true);

insert into public.rf_plan_catalog(plan,label,included_internal_profiles,monthly_price_chf,extra_profile_price_chf,sort_order) values
('starter','Starter',3,29.00,6.00,10),
('team','Team',10,59.00,5.00,20),
('business','Business',50,199.00,4.00,30);

create or replace function public.rf_billing_preview(p_company_id uuid)
returns table(
  plan text,
  active_internal_profiles bigint,
  included_internal_profiles integer,
  extra_profiles bigint,
  base_price_chf numeric,
  extra_price_chf numeric,
  estimated_monthly_chf numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with b as (
    select cb.plan, pc.included_internal_profiles, pc.monthly_price_chf, pc.extra_profile_price_chf
    from public.rf_company_billing cb
    left join public.rf_plan_catalog pc on pc.plan=cb.plan
    where cb.company_id=p_company_id
  ),
  seats as (
    select count(*)::bigint as n
    from public.rf_memberships m
    where m.company_id=p_company_id and m.active
  )
  select
    b.plan,
    seats.n,
    coalesce(b.included_internal_profiles, 999999),
    greatest(seats.n - coalesce(b.included_internal_profiles,999999),0),
    coalesce(b.monthly_price_chf,0),
    coalesce(b.extra_profile_price_chf,0),
    coalesce(b.monthly_price_chf,0) +
      greatest(seats.n - coalesce(b.included_internal_profiles,999999),0) * coalesce(b.extra_profile_price_chf,0)
  from b cross join seats
  where public.rf_has_permission(p_company_id,'billing.manage');
$$;

revoke all on function public.rf_billing_preview(uuid) from public, anon;
grant execute on function public.rf_billing_preview(uuid) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Pricing catalog wired into backend',
'Added fixed Starter CHF 29 / 3 profiles / CHF 6 extra, Team CHF 59 / 10 profiles / CHF 5 extra, Business CHF 199 / 50 profiles / CHF 4 extra. Added billing preview calculation based only on active internal memberships. Customer accounts never count as paid profiles. Development companies remain on the special development plan with effectively unlimited internal profiles and CHF 0 until commercial billing is enabled.');


-- 20261001072407 regieflow_storage_evidence_hardening_v1

drop policy if exists rf_private_select on storage.objects;
drop policy if exists rf_private_insert on storage.objects;

create policy rf_private_select
on storage.objects for select to authenticated
using (
  bucket_id='rf-private'
  and exists (
    select 1
    from public.rf_regies r
    where r.company_id = public.rf_storage_segment_uuid(name,1)
      and r.id = public.rf_storage_segment_uuid(name,2)
      and (
        (
          split_part(name,'/',3) in ('documents','signatures')
          and (
            public.rf_has_permission(r.company_id,'documents.view')
            or public.rf_customer_has_project(r.project_id)
          )
        )
        or
        (
          split_part(name,'/',3) not in ('documents','signatures')
          and (
            public.rf_has_permission(r.company_id,'regies.view')
            or public.rf_customer_has_project(r.project_id)
          )
        )
      )
  )
);

create policy rf_private_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='rf-private'
  and split_part(name,'/',3) in ('before','after','attachments','customer-request')
  and exists (
    select 1
    from public.rf_regies r
    where r.company_id = public.rf_storage_segment_uuid(name,1)
      and r.id = public.rf_storage_segment_uuid(name,2)
      and (
        (
          split_part(name,'/',3)='before'
          and public.rf_has_permission(r.company_id,'regies.create')
        )
        or
        (
          split_part(name,'/',3)='after'
          and (
            public.rf_has_permission(r.company_id,'regies.complete')
            or public.rf_has_permission(r.company_id,'regies.create')
          )
        )
        or
        (
          split_part(name,'/',3)='attachments'
          and public.rf_has_permission(r.company_id,'regies.create')
        )
        or
        (
          split_part(name,'/',3)='customer-request'
          and r.source='customer'
          and r.status='customer_request'
          and r.requested_by_customer_contact_id = public.rf_customer_contact_for_company(r.company_id)
          and public.rf_customer_has_project(r.project_id)
        )
      )
  )
);

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Storage evidence hardening',
'Client uploads into rf-private are now limited to before/after/attachment/customer-request folders. Clients cannot upload or overwrite generated signatures or signed PDFs; only service-role finalization can create those. Internal viewing of document/signature evidence now requires documents.view, while ordinary project photos use regies.view. Customers retain access only through their assigned project.');


-- 20261001072451 regieflow_frontend_api_v1

create or replace view public.rf_regie_overview
with (security_invoker = true)
as
select
  r.id,
  r.company_id,
  r.project_id,
  r.regie_code,
  r.source,
  r.status,
  r.created_by_user_id,
  r.requested_by_customer_contact_id,
  r.assigned_monteur_user_id,
  r.current_version_no,
  r.messerli_rapport_number,
  r.work_completed_at,
  r.closed_at,
  r.created_at,
  r.updated_at,
  p.project_number,
  p.messerli_project_number,
  p.name as project_name,
  p.address as project_address,
  p.client_name,
  p.approval_workflow,
  coalesce(v.description,r.request_description) as description,
  v.estimate_label,
  v.estimate_disclaimer,
  v.id as current_version_id,
  v.locked_at as current_version_locked_at,
  exists (
    select 1 from public.rf_documents d where d.version_id=v.id
  ) as has_final_pdf,
  (
    select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.kind='before'
  ) as before_photo_count,
  (
    select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.kind='after'
  ) as after_photo_count
from public.rf_regies r
join public.rf_projects p on p.id=r.project_id
left join public.rf_regie_versions v
  on v.regie_id=r.id and v.version_no=r.current_version_no;

grant select on public.rf_regie_overview to authenticated;

create or replace function public.rf_my_context()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
with uid as (
  select auth.uid() as id
),
internal_access as (
  select
    c.id as company_id,
    c.name as company_name,
    m.display_name,
    (c.primary_owner_user_id=(select id from uid)) as is_primary_owner,
    r.name as role_name,
    coalesce(r.permissions,'{}'::text[]) as role_permissions,
    coalesce(m.permission_overrides,'{}'::jsonb) as permission_overrides,
    m.must_change_password
  from public.rf_companies c
  join public.rf_memberships m
    on m.company_id=c.id
   and m.user_id=(select id from uid)
   and m.active
  left join public.rf_roles r on r.id=m.role_id
),
customer_access as (
  select
    c.id as company_id,
    c.name as company_name,
    cc.id as customer_contact_id,
    cc.full_name,
    cc.organization_name,
    (
      select count(*)::integer
      from public.rf_project_customer_access a
      where a.customer_contact_id=cc.id
    ) as project_count
  from public.rf_customer_contacts cc
  join public.rf_companies c on c.id=cc.company_id
  where cc.auth_user_id=(select id from uid)
    and cc.active
)
select jsonb_build_object(
  'internal',coalesce((
    select jsonb_agg(jsonb_build_object(
      'companyId',company_id,
      'companyName',company_name,
      'displayName',display_name,
      'isPrimaryOwner',is_primary_owner,
      'roleName',role_name,
      'rolePermissions',role_permissions,
      'permissionOverrides',permission_overrides,
      'mustChangePassword',must_change_password
    ) order by company_name)
    from internal_access
  ),'[]'::jsonb),
  'customer',coalesce((
    select jsonb_agg(jsonb_build_object(
      'companyId',company_id,
      'companyName',company_name,
      'customerContactId',customer_contact_id,
      'fullName',full_name,
      'organizationName',organization_name,
      'projectCount',project_count
    ) order by company_name)
    from customer_access
  ),'[]'::jsonb)
);
$$;

revoke all on function public.rf_my_context() from public, anon;
grant execute on function public.rf_my_context() to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Frontend-oriented API simplification',
'Added security-invoker rf_regie_overview view so Büro, Monteur and Kunde can render Regie lists from one RLS-safe joined source. Added rf_my_context() for post-login routing and permission-aware UI: it returns internal company access/role/overrides/owner status and free customer-account context without exposing other tenants.');


-- 20261001072539 regieflow_customer_request_flow_v1

alter table public.rf_regie_files
  drop constraint rf_regie_files_kind_check,
  add constraint rf_regie_files_kind_check
    check (kind in ('before','after','attachment','customer_request'));

create or replace function public.rf_decide_customer_request(
  p_regie_id uuid,
  p_decision text,
  p_assigned_monteur_user_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_status text;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.source <> 'customer' or v_regie.status <> 'customer_request' then
    raise exception 'Regie is not an open customer request';
  end if;

  if not (
    public.rf_has_permission(v_regie.company_id,'regies.review')
    or public.rf_has_permission(v_regie.company_id,'regies.create')
  ) then
    raise exception 'Not allowed';
  end if;

  if p_decision='approved' then
    if p_assigned_monteur_user_id is not null and not exists (
      select 1 from public.rf_memberships m
      where m.company_id=v_regie.company_id
        and m.user_id=p_assigned_monteur_user_id
        and m.active
    ) then
      raise exception 'Assigned Monteur is not an active internal user';
    end if;

    v_status := 'draft';
    update public.rf_regies
      set status='draft',
          assigned_monteur_user_id=p_assigned_monteur_user_id,
          updated_at=now()
    where id=p_regie_id;
  else
    v_status := 'rejected';
    update public.rf_regies
      set status='rejected',updated_at=now()
    where id=p_regie_id;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
    'customer_request_'||p_decision,
    jsonb_build_object('assigned_monteur_user_id',p_assigned_monteur_user_id)
  );

  if v_regie.requested_by_customer_contact_id is not null then
    insert into public.rf_notifications(
      company_id,recipient_customer_contact_id,regie_id,type,title,body
    )
    values(
      v_regie.company_id,v_regie.requested_by_customer_contact_id,v_regie.id,
      'customer_request_'||p_decision,
      case when p_decision='approved' then 'Auftrag wurde übernommen' else 'Auftrag wurde abgelehnt' end,
      case when p_decision='approved'
        then 'Ihre Anfrage wurde vom Betrieb übernommen.'
        else 'Ihre Anfrage wurde vom Betrieb abgelehnt.'
      end
    );
  end if;

  if p_decision='approved' and p_assigned_monteur_user_id is not null then
    insert into public.rf_notifications(
      company_id,recipient_user_id,regie_id,type,title,body
    )
    values(
      v_regie.company_id,p_assigned_monteur_user_id,v_regie.id,
      'customer_request_assigned',
      'Neuer Kundenauftrag',
      'Eine Kundenanfrage wurde Ihnen zugewiesen.'
    );
  end if;

  return v_status;
end
$$;

revoke all on function public.rf_decide_customer_request(uuid,text,uuid) from public, anon;
grant execute on function public.rf_decide_customer_request(uuid,text,uuid) to authenticated;

create or replace function public.rf_notify_new_customer_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source='customer' and new.status='customer_request' then
    insert into public.rf_notifications(company_id,recipient_user_id,regie_id,type,title,body)
    select new.company_id,x.user_id,new.id,'customer_request',
           'Neue Kundenanfrage',
           'Ein Kunde hat einen neuen Auftrag angefragt.'
    from (
      select c.primary_owner_user_id as user_id
      from public.rf_companies c where c.id=new.company_id
      union
      select m.user_id
      from public.rf_memberships m
      left join public.rf_roles r on r.id=m.role_id
      where m.company_id=new.company_id and m.active
        and (
          (m.permission_overrides ? 'regies.review' and (m.permission_overrides->>'regies.review')::boolean)
          or 'regies.review'=any(coalesce(r.permissions,'{}'::text[]))
        )
    ) x
    where x.user_id is not null;
  end if;
  return new;
end
$$;

revoke all on function public.rf_notify_new_customer_request() from public, anon, authenticated;

create trigger rf_notify_new_customer_request_trg
after insert on public.rf_regies
for each row execute function public.rf_notify_new_customer_request();

create or replace view public.rf_regie_overview
with (security_invoker = true)
as
select
  r.id,
  r.company_id,
  r.project_id,
  r.regie_code,
  r.source,
  r.status,
  r.created_by_user_id,
  r.requested_by_customer_contact_id,
  r.assigned_monteur_user_id,
  r.current_version_no,
  r.messerli_rapport_number,
  r.work_completed_at,
  r.closed_at,
  r.created_at,
  r.updated_at,
  p.project_number,
  p.messerli_project_number,
  p.name as project_name,
  p.address as project_address,
  p.client_name,
  p.approval_workflow,
  coalesce(v.description,r.request_description) as description,
  v.estimate_label,
  v.estimate_disclaimer,
  v.id as current_version_id,
  v.locked_at as current_version_locked_at,
  exists (
    select 1 from public.rf_documents d where d.version_id=v.id
  ) as has_final_pdf,
  (
    select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.kind='before'
  ) as before_photo_count,
  (
    select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.kind='after'
  ) as after_photo_count,
  (
    select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.kind='customer_request'
  ) as customer_request_photo_count
from public.rf_regies r
join public.rf_projects p on p.id=r.project_id
left join public.rf_regie_versions v
  on v.regie_id=r.id and v.version_no=r.current_version_no;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Customer request lifecycle completed',
'Customer request photos now have their own file kind and remain optional. New customer requests notify Owner/authorized reviewers. Büro or an internal user with review/create permission can approve the request into an internal draft and optionally assign a Monteur, or reject it without a mandatory reason. The customer is notified of the decision and the assigned Monteur is notified when applicable. The overview API now exposes customer-request photo counts.');


-- 20261001072608 regieflow_owner_safety_v1

create or replace function public.rf_protect_primary_owner_membership()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select primary_owner_user_id into v_owner
  from public.rf_companies
  where id=old.company_id;

  if old.user_id=v_owner then
    if tg_op='DELETE' then
      raise exception 'Primary Owner membership cannot be deleted';
    end if;
    if new.active=false then
      raise exception 'Primary Owner membership cannot be deactivated';
    end if;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

revoke all on function public.rf_protect_primary_owner_membership() from public, anon, authenticated;

create trigger rf_protect_primary_owner_membership_trg
before update or delete on public.rf_memberships
for each row execute function public.rf_protect_primary_owner_membership();

create or replace function public.rf_transfer_primary_owner(
  p_company_id uuid,
  p_new_owner_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_owner uuid;
begin
  select primary_owner_user_id into v_old_owner
  from public.rf_companies
  where id=p_company_id
  for update;

  if not found then raise exception 'Company not found'; end if;
  if v_old_owner is distinct from auth.uid() then
    raise exception 'Only the current Primary Owner can transfer ownership';
  end if;
  if p_new_owner_user_id=v_old_owner then return true; end if;

  if not exists (
    select 1 from public.rf_memberships
    where company_id=p_company_id
      and user_id=p_new_owner_user_id
      and active
  ) then
    raise exception 'New Primary Owner must already be an active internal user';
  end if;

  update public.rf_companies
  set primary_owner_user_id=p_new_owner_user_id,updated_at=now()
  where id=p_company_id;

  insert into public.rf_audit_log(
    company_id,actor_user_id,event_type,metadata
  )
  values(
    p_company_id,v_old_owner,'primary_owner_transferred',
    jsonb_build_object('old_owner_user_id',v_old_owner,'new_owner_user_id',p_new_owner_user_id)
  );

  return true;
end
$$;

revoke all on function public.rf_transfer_primary_owner(uuid,uuid) from public, anon;
grant execute on function public.rf_transfer_primary_owner(uuid,uuid) to authenticated;

create or replace function public.rf_ack_password_changed(p_company_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.rf_memberships
  set must_change_password=false,updated_at=now()
  where company_id=p_company_id
    and user_id=auth.uid()
    and active;

  if not found then raise exception 'Active membership not found'; end if;
  return true;
end
$$;

revoke all on function public.rf_ack_password_changed(uuid) from public, anon;
grant execute on function public.rf_ack_password_changed(uuid) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Primary Owner safety',
'Primary Owner membership can no longer be deleted or deactivated accidentally. Added explicit Primary Owner transfer RPC that only the current Primary Owner may call and only to an existing active internal user. Added self-service acknowledgement after an internal user changes an initial temporary password.');


-- 20261001072708 regieflow_regie_creation_revision_v1

create or replace function public.rf_create_internal_regie(
  p_project_id uuid,
  p_description text,
  p_estimate_label text,
  p_estimate_minutes integer default null,
  p_assigned_monteur_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project public.rf_projects%rowtype;
  v_regie_id uuid;
  v_version_id uuid;
  v_monteur uuid;
begin
  select * into v_project
  from public.rf_projects
  where id=p_project_id and active;

  if not found then raise exception 'Project not found or inactive'; end if;
  if not public.rf_has_permission(v_project.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;
  if p_description is null or btrim(p_description)='' then raise exception 'Description required'; end if;
  if p_estimate_label is null or btrim(p_estimate_label)='' then raise exception 'Estimate required'; end if;
  if p_estimate_minutes is not null and p_estimate_minutes <= 0 then raise exception 'Estimate minutes must be positive'; end if;

  v_monteur := coalesce(p_assigned_monteur_user_id,auth.uid());
  if not exists (
    select 1 from public.rf_memberships m
    where m.company_id=v_project.company_id
      and m.user_id=v_monteur
      and m.active
  ) and v_monteur is distinct from (
    select primary_owner_user_id from public.rf_companies where id=v_project.company_id
  ) then
    raise exception 'Assigned Monteur is not an active internal user';
  end if;

  insert into public.rf_regies(
    company_id,project_id,source,status,created_by_user_id,assigned_monteur_user_id,current_version_no
  )
  values(
    v_project.company_id,p_project_id,'internal','draft',auth.uid(),v_monteur,1
  )
  returning id into v_regie_id;

  insert into public.rf_regie_versions(
    regie_id,version_no,description,estimate_label,estimate_minutes,created_by_user_id
  )
  values(
    v_regie_id,1,btrim(p_description),btrim(p_estimate_label),p_estimate_minutes,auth.uid()
  )
  returning id into v_version_id;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_project.company_id,p_project_id,v_regie_id,auth.uid(),'regie_created',
    jsonb_build_object('version_id',v_version_id,'version_no',1,'assigned_monteur_user_id',v_monteur)
  );

  return jsonb_build_object('regieId',v_regie_id,'versionId',v_version_id,'versionNo',1);
end
$$;

revoke all on function public.rf_create_internal_regie(uuid,text,text,integer,uuid) from public, anon;
grant execute on function public.rf_create_internal_regie(uuid,text,text,integer,uuid) to authenticated;

create or replace function public.rf_create_regie_revision(
  p_regie_id uuid,
  p_description text,
  p_estimate_label text,
  p_estimate_minutes integer default null,
  p_copy_before_photos boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_next integer;
  v_prev_version uuid;
  v_new_version uuid;
begin
  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status='closed' then raise exception 'Closed Regie cannot be revised'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then raise exception 'Not allowed'; end if;
  if p_description is null or btrim(p_description)='' then raise exception 'Description required'; end if;
  if p_estimate_label is null or btrim(p_estimate_label)='' then raise exception 'Estimate required'; end if;

  select coalesce(max(version_no),0)+1 into v_next
  from public.rf_regie_versions
  where regie_id=p_regie_id;

  select id into v_prev_version
  from public.rf_regie_versions
  where regie_id=p_regie_id
  order by version_no desc
  limit 1;

  insert into public.rf_regie_versions(
    regie_id,version_no,description,estimate_label,estimate_minutes,created_by_user_id
  )
  values(
    p_regie_id,v_next,btrim(p_description),btrim(p_estimate_label),p_estimate_minutes,auth.uid()
  )
  returning id into v_new_version;

  if p_copy_before_photos and v_prev_version is not null then
    insert into public.rf_regie_files(
      regie_id,version_id,kind,storage_path,original_filename,mime_type,byte_size,sha256,sort_order,uploaded_by_user_id
    )
    select
      regie_id,v_new_version,'before',storage_path,original_filename,mime_type,byte_size,sha256,sort_order,auth.uid()
    from public.rf_regie_files
    where regie_id=p_regie_id
      and version_id=v_prev_version
      and kind='before';
  end if;

  update public.rf_public_approval_links pal
  set revoked_at=coalesce(revoked_at,now())
  where pal.version_id in (
    select id from public.rf_regie_versions where regie_id=p_regie_id and id<>v_new_version
  )
    and pal.used_at is null
    and pal.revoked_at is null;

  update public.rf_regies
  set status='draft',current_version_no=v_next,updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),'regie_revision_created',
    jsonb_build_object(
      'new_version_id',v_new_version,
      'new_version_no',v_next,
      'copied_before_photos',p_copy_before_photos
    )
  );

  return jsonb_build_object('regieId',p_regie_id,'versionId',v_new_version,'versionNo',v_next);
end
$$;

revoke all on function public.rf_create_regie_revision(uuid,text,text,integer,boolean) from public, anon;
grant execute on function public.rf_create_regie_revision(uuid,text,text,integer,boolean) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Simple Monteur creation and revision API',
'Added one-call internal Regie creation for the Monteur/Büro UI: select project, enter description and non-binding estimate, receive Regie/version IDs, then upload the mandatory before photo and submit. Added controlled revision creation for any non-closed Regie; it creates a new immutable version number, optionally reuses the previous before-photo evidence, revokes unused old approval links and sends the Regie back to Draft for a new approval cycle.');


-- 20261001072923 regieflow_privileges_integrity_v1

create or replace function public.rf_validate_membership_role_company()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.role_id is not null and not exists (
    select 1 from public.rf_roles r
    where r.id=new.role_id and r.company_id=new.company_id
  ) then
    raise exception 'Role must belong to the same company';
  end if;
  return new;
end
$$;
revoke all on function public.rf_validate_membership_role_company() from public, anon, authenticated;

create trigger rf_validate_membership_role_company_trg
before insert or update of company_id,role_id on public.rf_memberships
for each row execute function public.rf_validate_membership_role_company();

create or replace function public.rf_validate_project_customer_company()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_project_company uuid;
  v_customer_company uuid;
begin
  select company_id into v_project_company from public.rf_projects where id=new.project_id;
  select company_id into v_customer_company from public.rf_customer_contacts where id=new.customer_contact_id;
  if v_project_company is null or v_customer_company is null or v_project_company<>v_customer_company then
    raise exception 'Project and customer contact must belong to the same company';
  end if;
  return new;
end
$$;
revoke all on function public.rf_validate_project_customer_company() from public, anon, authenticated;

create trigger rf_validate_project_customer_company_trg
before insert or update of project_id,customer_contact_id on public.rf_project_customer_access
for each row execute function public.rf_validate_project_customer_company();

create or replace function public.rf_validate_regie_file_links()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.version_id is not null and not exists (
    select 1 from public.rf_regie_versions v
    where v.id=new.version_id and v.regie_id=new.regie_id
  ) then
    raise exception 'File version must belong to the same Regie';
  end if;
  return new;
end
$$;
revoke all on function public.rf_validate_regie_file_links() from public, anon, authenticated;

create trigger rf_validate_regie_file_links_trg
before insert or update of regie_id,version_id on public.rf_regie_files
for each row execute function public.rf_validate_regie_file_links();

create or replace function public.rf_guard_primary_owner_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.primary_owner_user_id is distinct from old.primary_owner_user_id
     and auth.uid() is distinct from old.primary_owner_user_id then
    raise exception 'Only the current Primary Owner can transfer ownership';
  end if;
  return new;
end
$$;
revoke all on function public.rf_guard_primary_owner_change() from public, anon, authenticated;

create trigger rf_guard_primary_owner_change_trg
before update of primary_owner_user_id on public.rf_companies
for each row execute function public.rf_guard_primary_owner_change();

drop policy if exists rf_billing_write on public.rf_company_billing;

revoke all privileges on all tables in schema public from anon;
revoke all privileges on all sequences in schema public from anon;

revoke insert, update, delete on public.rf_regies from authenticated;
revoke insert, delete on public.rf_regie_versions from authenticated;
revoke update on public.rf_regie_versions from authenticated;
revoke insert, update, delete on public.rf_customer_signatures from authenticated;
revoke insert, update, delete on public.rf_documents from authenticated;
revoke insert, update, delete on public.rf_internal_reviews from authenticated;
revoke insert, update, delete on public.rf_audit_log from authenticated;
revoke insert, update, delete on public.rf_company_billing from authenticated;
revoke insert, update, delete on public.rf_customer_invites from authenticated;
revoke insert, update, delete on public.rf_public_approval_links from authenticated;
revoke insert, update, delete on public.rf_permission_catalog from authenticated;
revoke insert, update, delete on public.rf_plan_catalog from authenticated;

grant select on public.rf_companies to authenticated;
grant update (name,logo_path,accent_color,legal_name,address,updated_at) on public.rf_companies to authenticated;

grant select,insert,delete on public.rf_roles to authenticated;
grant update (name,permissions,updated_at) on public.rf_roles to authenticated;

grant select on public.rf_memberships to authenticated;
grant update (display_name,role_id,permission_overrides,active,updated_at) on public.rf_memberships to authenticated;

grant select on public.rf_customer_contacts to authenticated;
grant insert (company_id,full_name,email,phone,organization_name,active) on public.rf_customer_contacts to authenticated;
grant update (full_name,email,phone,organization_name,active,updated_at) on public.rf_customer_contacts to authenticated;

grant select on public.rf_projects to authenticated;
grant insert (company_id,project_number,messerli_project_number,name,address,client_name,approval_workflow,active,created_by) on public.rf_projects to authenticated;
grant update (project_number,messerli_project_number,name,address,client_name,approval_workflow,active,updated_at) on public.rf_projects to authenticated;

grant select,insert,delete on public.rf_project_customer_access to authenticated;
grant update (can_sign,label) on public.rf_project_customer_access to authenticated;

grant select on public.rf_regies to authenticated;

grant select on public.rf_regie_versions to authenticated;
grant update (description,estimate_label,estimate_minutes) on public.rf_regie_versions to authenticated;

grant select,insert on public.rf_regie_files to authenticated;

grant select on public.rf_internal_reviews to authenticated;
grant select on public.rf_customer_signatures to authenticated;
grant select on public.rf_documents to authenticated;

grant select,insert on public.rf_regie_comments to authenticated;

grant select on public.rf_notifications to authenticated;
grant update (read_at) on public.rf_notifications to authenticated;

grant select,insert,delete on public.rf_push_subscriptions to authenticated;
grant update (endpoint,p256dh,auth_key,updated_at) on public.rf_push_subscriptions to authenticated;

grant select on public.rf_audit_log to authenticated;
grant select on public.rf_company_billing to authenticated;
grant select on public.rf_permission_catalog to authenticated;
grant select on public.rf_plan_catalog to authenticated;
grant select on public.rf_customer_invites to authenticated;
grant select on public.rf_public_approval_links to authenticated;
grant select on public.rf_regie_overview to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Database privilege and tenant-integrity hardening',
'Added tenant-integrity triggers: role must match membership company, customer contact must match project company, Regie file version must belong to the same Regie, and Primary Owner changes are guarded. Removed client write access to billing/signatures/documents/audit/reviews/workflow roots. Regie workflow changes now occur only through controlled RPCs/Edge Functions. Authenticated clients receive only the minimum table/column grants needed by the UI: draft text edits, project/customer/role administration, comments, file metadata, read-state notifications and push subscription management. Anonymous table access was revoked.');


-- 20261001073013 regieflow_realtime_v1

alter publication supabase_realtime add table public.rf_notifications;
alter publication supabase_realtime add table public.rf_regies;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Realtime dashboard updates enabled',
'Enabled Supabase Realtime for Regie status rows and RegieFlow notifications. Logged-in Büro/Monteur/Kunde clients can now receive RLS-filtered live dashboard updates without polling. Background browser push still requires the PWA service worker/VAPID layer in the frontend phase.');


-- 20261001073222 regieflow_dev_setup_tokens_v1

create table if not exists regieflow_private.setup_tokens (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
revoke all on regieflow_private.setup_tokens from public,anon,authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Free customer signup endpoint',
'Deployed rf-customer-signup. A customer with a valid one-time RegieFlow invite can create a free Supabase Auth account without changing the shared DriveLoop Auth settings. New customer accounts are email-confirmed by the controlled endpoint, linked only to the invited customer contact and audited. Existing shared Supabase users are told to log in and claim the invite instead.');


-- 20261001073238 regieflow_dev_setup_rpc_v1

create or replace function public.rf_dev_validate_setup_token(p_token_hash text)
returns boolean
language sql
security definer
set search_path = regieflow_private, public
as $$
  select exists (
    select 1
    from regieflow_private.setup_tokens
    where token_hash=p_token_hash
      and used_at is null
      and expires_at>now()
  );
$$;
revoke all on function public.rf_dev_validate_setup_token(text) from public,anon,authenticated;
grant execute on function public.rf_dev_validate_setup_token(text) to service_role;

create or replace function public.rf_dev_consume_setup_token(p_token_hash text)
returns boolean
language plpgsql
security definer
set search_path = regieflow_private, public
as $$
begin
  update regieflow_private.setup_tokens
  set used_at=now()
  where token_hash=p_token_hash
    and used_at is null
    and expires_at>now();
  return found;
end
$$;
revoke all on function public.rf_dev_consume_setup_token(text) from public,anon,authenticated;
grant execute on function public.rf_dev_consume_setup_token(text) to service_role;


-- 20261001074138 regieflow_web_push_foundation_v1

create extension if not exists pg_net with schema extensions;

create table if not exists regieflow_private.push_config (
  singleton boolean primary key default true check (singleton),
  hook_secret text not null,
  vapid_public text,
  vapid_private text,
  updated_at timestamptz not null default now()
);
revoke all on regieflow_private.push_config from public,anon,authenticated;

insert into regieflow_private.push_config(singleton,hook_secret)
values(true,encode(gen_random_bytes(32),'hex'))
on conflict(singleton) do nothing;

create or replace function public.rf_push_get_config()
returns jsonb
language sql
security definer
set search_path = regieflow_private, public
as $$
  select jsonb_build_object(
    'hook_secret',hook_secret,
    'vapid_public',vapid_public,
    'vapid_private',vapid_private
  )
  from regieflow_private.push_config
  where singleton=true;
$$;
revoke all on function public.rf_push_get_config() from public,anon,authenticated;
grant execute on function public.rf_push_get_config() to service_role;

create or replace function public.rf_push_set_vapid(p_public text,p_private text)
returns boolean
language plpgsql
security definer
set search_path = regieflow_private, public
as $$
begin
  if p_public is null or btrim(p_public)='' or p_private is null or btrim(p_private)='' then
    raise exception 'VAPID keys required';
  end if;
  update regieflow_private.push_config
  set vapid_public=p_public,vapid_private=p_private,updated_at=now()
  where singleton=true;
  return found;
end
$$;
revoke all on function public.rf_push_set_vapid(text,text) from public,anon,authenticated;
grant execute on function public.rf_push_set_vapid(text,text) to service_role;

create or replace function regieflow_private.dispatch_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public,regieflow_private,extensions
as $$
declare
  v_secret text;
  v_has_subscription boolean;
begin
  select exists (
    select 1
    from public.rf_push_subscriptions s
    where (new.recipient_user_id is not null and s.user_id=new.recipient_user_id)
       or (new.recipient_customer_contact_id is not null and s.customer_contact_id=new.recipient_customer_contact_id)
  ) into v_has_subscription;

  if not v_has_subscription then
    return new;
  end if;

  select hook_secret into v_secret
  from regieflow_private.push_config
  where singleton=true;

  perform net.http_post(
    url := 'https://kiihabzzepoehsokglzq.supabase.co/functions/v1/rf-push',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-regieflow-hook',v_secret
    ),
    body := jsonb_build_object('notificationId',new.id)
  );

  return new;
end
$$;
revoke all on function regieflow_private.dispatch_push_notification() from public,anon,authenticated;

drop trigger if exists rf_dispatch_push_notification_trg on public.rf_notifications;
create trigger rf_dispatch_push_notification_trg
after insert on public.rf_notifications
for each row execute function regieflow_private.dispatch_push_notification();

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Web Push server foundation',
'Installed pg_net and created inaccessible private push configuration with a random webhook secret. Every new RegieFlow in-app notification now asynchronously dispatches to the rf-push Edge endpoint only when the recipient has a saved browser push subscription. VAPID keys are generated lazily by the push endpoint and stored server-side; clients receive only the public key.');


-- 20261001074817 regieflow_customer_request_prepare_v1

create or replace function public.rf_prepare_customer_request_draft(
  p_regie_id uuid,
  p_description text,
  p_estimate_label text,
  p_estimate_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version uuid;
begin
  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.source <> 'customer' or v_regie.status <> 'draft' or v_regie.current_version_no <> 0 then
    raise exception 'Customer request is not ready to be prepared';
  end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;
  if p_description is null or btrim(p_description)='' then raise exception 'Description required'; end if;
  if p_estimate_label is null or btrim(p_estimate_label)='' then raise exception 'Estimate required'; end if;
  if p_estimate_minutes is not null and p_estimate_minutes <= 0 then raise exception 'Estimate minutes must be positive'; end if;

  insert into public.rf_regie_versions(
    regie_id,version_no,description,estimate_label,estimate_minutes,created_by_user_id
  )
  values(
    p_regie_id,1,btrim(p_description),btrim(p_estimate_label),p_estimate_minutes,auth.uid()
  )
  returning id into v_version;

  update public.rf_regies
  set current_version_no=1,updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),
    'customer_request_prepared_as_regie',
    jsonb_build_object('version_id',v_version,'version_no',1)
  );

  return jsonb_build_object('regieId',p_regie_id,'versionId',v_version,'versionNo',1);
end
$$;

revoke all on function public.rf_prepare_customer_request_draft(uuid,text,text,integer) from public,anon;
grant execute on function public.rf_prepare_customer_request_draft(uuid,text,text,integer) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Customer request handoff to Monteur',
'Added controlled preparation step after a customer request is accepted. An internal user with regies.create can turn the accepted request into Version 1 by confirming/editing the description and adding the non-binding time estimate. The mandatory before photo is then uploaded and the normal submission workflow begins.');


-- 20261001074951 regieflow_onboarding_lockdown_v1

revoke execute on function public.rf_bootstrap_company(text,text) from authenticated;
grant execute on function public.rf_bootstrap_company(text,text) to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Pre-launch onboarding locked down',
'Direct authenticated access to company bootstrap was removed. Before Stripe/public commercial onboarding exists, new RegieFlow companies cannot be created arbitrarily by other users of the shared DriveLoop Auth project. The initial founder company is created only through the private one-time setup-token endpoint.');


-- 20261001075023 regieflow_performance_pass_v1

create index if not exists rf_audit_actor_customer_idx on public.rf_audit_log(actor_customer_contact_id);
create index if not exists rf_audit_actor_user_idx on public.rf_audit_log(actor_user_id);
create index if not exists rf_audit_project_idx on public.rf_audit_log(project_id);
create index if not exists rf_customer_invites_company_idx on public.rf_customer_invites(company_id);
create index if not exists rf_customer_invites_creator_idx on public.rf_customer_invites(created_by_user_id);
create index if not exists rf_customer_signatures_contact_idx on public.rf_customer_signatures(customer_contact_id);
create index if not exists rf_customer_signatures_user_idx on public.rf_customer_signatures(signer_user_id);
create index if not exists rf_internal_reviews_reviewer_idx on public.rf_internal_reviews(reviewer_user_id);
create index if not exists rf_internal_reviews_version_idx on public.rf_internal_reviews(version_id);
create index if not exists rf_memberships_created_by_idx on public.rf_memberships(created_by);
create index if not exists rf_projects_created_by_idx on public.rf_projects(created_by);
create index if not exists rf_public_links_created_by_idx on public.rf_public_approval_links(created_by_user_id);
create index if not exists rf_push_customer_idx on public.rf_push_subscriptions(customer_contact_id);
create index if not exists rf_push_user_idx on public.rf_push_subscriptions(user_id);
create index if not exists rf_comments_customer_idx on public.rf_regie_comments(actor_customer_contact_id);
create index if not exists rf_comments_user_idx on public.rf_regie_comments(actor_user_id);
create index if not exists rf_roles_created_by_idx on public.rf_roles(created_by);

drop policy if exists rf_customer_contacts_select on public.rf_customer_contacts;
create policy rf_customer_contacts_select on public.rf_customer_contacts
for select to authenticated
using (
  public.rf_has_permission(company_id,'projects.view')
  or auth_user_id = (select auth.uid())
);

drop policy if exists rf_project_customer_access_select on public.rf_project_customer_access;
create policy rf_project_customer_access_select on public.rf_project_customer_access
for select to authenticated
using (
  exists (
    select 1 from public.rf_projects p
    where p.id = project_id
      and public.rf_has_permission(p.company_id,'projects.view')
  )
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id = customer_contact_id and c.auth_user_id = (select auth.uid())
  )
);

drop policy if exists rf_internal_reviews_insert on public.rf_internal_reviews;
create policy rf_internal_reviews_insert on public.rf_internal_reviews
for insert to authenticated
with check (
  reviewer_user_id = (select auth.uid())
  and exists (
    select 1 from public.rf_regie_versions v
    join public.rf_regies r on r.id=v.regie_id
    where v.id=version_id and public.rf_has_permission(r.company_id,'regies.review')
  )
);

drop policy if exists rf_comments_insert on public.rf_regie_comments;
create policy rf_comments_insert on public.rf_regie_comments
for insert to authenticated
with check (
  (actor_user_id = (select auth.uid()) and exists (
    select 1 from public.rf_regies r
    where r.id=regie_id and public.rf_is_internal_member(r.company_id)
  ))
  or
  (actor_customer_contact_id is not null and exists (
    select 1 from public.rf_regies r
    join public.rf_customer_contacts c on c.id=actor_customer_contact_id
    where r.id=regie_id
      and c.auth_user_id=(select auth.uid())
      and public.rf_customer_has_project(r.project_id)
  ))
);

drop policy if exists rf_notifications_select on public.rf_notifications;
create policy rf_notifications_select on public.rf_notifications
for select to authenticated
using (
  recipient_user_id = (select auth.uid())
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=recipient_customer_contact_id and c.auth_user_id=(select auth.uid())
  )
);

drop policy if exists rf_notifications_update on public.rf_notifications;
create policy rf_notifications_update on public.rf_notifications
for update to authenticated
using (
  recipient_user_id = (select auth.uid())
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=recipient_customer_contact_id and c.auth_user_id=(select auth.uid())
  )
)
with check (
  recipient_user_id = (select auth.uid())
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=recipient_customer_contact_id and c.auth_user_id=(select auth.uid())
  )
);

drop policy if exists rf_push_subscriptions_own on public.rf_push_subscriptions;
create policy rf_push_subscriptions_own on public.rf_push_subscriptions
for all to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=customer_contact_id and c.auth_user_id=(select auth.uid())
  )
)
with check (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.rf_customer_contacts c
    where c.id=customer_contact_id and c.auth_user_id=(select auth.uid())
  )
);

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Database performance pass',
'Added covering indexes for all RegieFlow foreign keys flagged by Supabase advisor and rewrote direct auth.uid() checks in hot RLS policies using init-plan-safe SELECT wrappers. This reduces per-row auth evaluation and improves scale without changing permissions.');


-- 20261001075623 regieflow_static_web_bucket_v1

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'rf-web','rf-web',true,5242880,
  array['text/html','application/javascript','application/manifest+json','text/css','image/png','image/jpeg','image/webp','image/svg+xml']
)
on conflict (id) do update
set public=true,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Static web hosting workaround prepared',
'Supabase Edge Functions force HTML responses to text/plain with a sandbox CSP, so browsers show raw source. Created a dedicated public rf-web Storage bucket for the frontend. Supabase remains the backend; only static HTML/JS/PWA assets move to Storage so browsers receive renderable web content.');


-- 20261001085635 regieflow_service_role_permissions_fix_v1

grant usage on schema public to service_role;
grant select, insert, update, delete on
  public.rf_companies,
  public.rf_roles,
  public.rf_memberships,
  public.rf_customer_contacts,
  public.rf_projects,
  public.rf_project_customer_access,
  public.rf_regies,
  public.rf_regie_versions,
  public.rf_regie_files,
  public.rf_internal_reviews,
  public.rf_customer_signatures,
  public.rf_documents,
  public.rf_regie_comments,
  public.rf_notifications,
  public.rf_push_subscriptions,
  public.rf_audit_log,
  public.rf_company_billing,
  public.rf_public_approval_links,
  public.rf_permission_catalog,
  public.rf_customer_invites,
  public.rf_plan_catalog
to service_role;

grant usage, select on all sequences in schema public to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Fixed service-role DML permissions',
'The RegieFlow server-side Edge Functions use the Supabase service role. Earlier privilege hardening left service_role without normal DML privileges on rf_* tables, causing founder setup to fail with permission denied for rf_companies. Explicit SELECT/INSERT/UPDATE/DELETE privileges were restored for service_role on all RegieFlow public tables and sequence access was granted. Client roles remain restricted by their existing grants/RLS.');


-- 20261001091548 regieflow_neutral_rapport_wording_v1

create or replace function public.rf_close_regie(p_regie_id uuid, p_messerli_rapport_number text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
begin
  if p_messerli_rapport_number is null or btrim(p_messerli_rapport_number)='' then
    raise exception 'Rapportnummer ist erforderlich';
  end if;

  select * into v_regie from public.rf_regies where id=p_regie_id for update;
  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.close') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_rapport' then
    raise exception 'Regie wartet nicht auf eine Rapportnummer';
  end if;

  update public.rf_regies
  set messerli_rapport_number=btrim(p_messerli_rapport_number),
      status='closed',closed_at=now(),updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values(
    v_regie.company_id,
    v_regie.project_id,
    p_regie_id,
    auth.uid(),
    'regie_closed',
    jsonb_build_object('rapport_number',btrim(p_messerli_rapport_number))
  );

  return 'closed';
end
$$;

insert into regieflow_private.dev_log(kind,title,content) values
('decision','RegieFlow is system-neutral, not Messerli-specific',
'Removed the second visible Messerli project number from the project UI. RegieFlow now uses one project number only. The product must remain compatible with Messerli, Bexio and other ERP/rapport systems without presenting itself as an extension of one specific vendor. The closeout field is shown neutrally as Rapportnummer. Existing internal database column names may remain temporarily for migration compatibility, but must not surface in customer-facing UI.');


-- 20261001092752 regieflow_neutral_external_references_v1

alter table public.rf_projects
  rename column messerli_project_number to external_project_reference;

alter table public.rf_regies
  rename column messerli_rapport_number to rapport_number;

drop function if exists public.rf_close_regie(uuid,text);

create function public.rf_close_regie(p_regie_id uuid, p_rapport_number text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
begin
  if p_rapport_number is null or btrim(p_rapport_number)='' then
    raise exception 'Rapportnummer ist erforderlich';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.close') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_rapport' then
    raise exception 'Regie wartet nicht auf eine Rapportnummer';
  end if;

  update public.rf_regies
  set rapport_number=btrim(p_rapport_number),
      status='closed',
      closed_at=now(),
      updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,
    v_regie.project_id,
    p_regie_id,
    auth.uid(),
    'regie_closed',
    jsonb_build_object('rapport_number',btrim(p_rapport_number))
  );

  return 'closed';
end
$$;

revoke all on function public.rf_close_regie(uuid,text) from public,anon;
grant execute on function public.rf_close_regie(uuid,text) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Removed Messerli-specific database naming',
'Renamed the internal project reference column to external_project_reference and Regie closeout field to rapport_number. Recreated rf_close_regie with neutral p_rapport_number naming. RegieFlow is now system-neutral in both visible UI and core schema; integrations with Messerli, Bexio or other ERP/rapport systems can map to generic references.');


-- 20261001102443 regieflow_neutralize_overview_columns_v1

alter view public.rf_regie_overview
  rename column messerli_rapport_number to rapport_number;

alter view public.rf_regie_overview
  rename column messerli_project_number to external_project_reference;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Removed final Messerli-specific overview aliases',
'The rf_regie_overview view still exposed two legacy Messerli-named aliases even though base tables had already been neutralized. Renamed them to rapport_number and external_project_reference. The view remains security_invoker=true, so underlying RLS applies to every query.');


-- 20261001092849 regieflow_close_rpc_compatibility_v1

drop function if exists public.rf_close_regie(uuid,text);

create function public.rf_close_regie(p_regie_id uuid, p_messerli_rapport_number text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
begin
  if p_messerli_rapport_number is null or btrim(p_messerli_rapport_number)='' then
    raise exception 'Rapportnummer ist erforderlich';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.close') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_rapport' then
    raise exception 'Regie wartet nicht auf eine Rapportnummer';
  end if;

  update public.rf_regies
  set rapport_number=btrim(p_messerli_rapport_number),
      status='closed',
      closed_at=now(),
      updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,
    v_regie.project_id,
    p_regie_id,
    auth.uid(),
    'regie_closed',
    jsonb_build_object('rapport_number',btrim(p_messerli_rapport_number))
  );

  return 'closed';
end
$$;

revoke all on function public.rf_close_regie(uuid,text) from public,anon;
grant execute on function public.rf_close_regie(uuid,text) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('note','Temporary RPC parameter compatibility',
'Core database columns are system-neutral (external_project_reference, rapport_number). The rf_close_regie RPC temporarily retains the legacy parameter name p_messerli_rapport_number only for compatibility with the currently deployed frontend. It is not visible in the UI and should be renamed when the frontend call is migrated.');


-- 20261001093014 regieflow_signature_evidence_v2

alter table public.rf_customer_signatures
  add column if not exists signature_sha256 text,
  add column if not exists consent_text text,
  add column if not exists consent_version text;

create or replace function public.rf_finalize_customer_decision_v2(
  p_version_id uuid,
  p_customer_contact_id uuid,
  p_signer_user_id uuid,
  p_signer_name text,
  p_decision text,
  p_signature_storage_path text,
  p_signature_sha256 text,
  p_document_storage_path text,
  p_document_file_name text,
  p_document_sha256 text,
  p_document_byte_size bigint,
  p_auth_method text,
  p_ip_address text,
  p_user_agent text,
  p_consent_text text,
  p_consent_version text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version public.rf_regie_versions%rowtype;
  v_contact public.rf_customer_contacts%rowtype;
  v_ip inet;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select * into v_version
  from public.rf_regie_versions
  where id=p_version_id;

  if not found then raise exception 'Version not found'; end if;
  if v_version.locked_at is null then raise exception 'Version is not locked/submitted'; end if;

  select * into v_regie
  from public.rf_regies
  where id=v_version.regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status <> 'awaiting_customer' then
    raise exception 'Regie is not awaiting customer approval';
  end if;

  select * into v_contact
  from public.rf_customer_contacts
  where id=p_customer_contact_id
    and company_id=v_regie.company_id
    and active;

  if not found then raise exception 'Customer contact not found'; end if;

  if not exists (
    select 1
    from public.rf_project_customer_access a
    where a.project_id=v_regie.project_id
      and a.customer_contact_id=p_customer_contact_id
      and a.can_sign
  ) then
    raise exception 'Customer is not authorized to sign this project';
  end if;

  if p_signer_user_id is not null
     and v_contact.auth_user_id is distinct from p_signer_user_id then
    raise exception 'Signer account does not match customer contact';
  end if;

  if p_signer_name is null or btrim(p_signer_name)='' then
    raise exception 'Signer name is required';
  end if;

  if p_decision='approved' then
    if p_signature_storage_path is null or btrim(p_signature_storage_path)='' then
      raise exception 'Signature is required for approval';
    end if;
    if p_signature_sha256 is null or btrim(p_signature_sha256)='' then
      raise exception 'Signature integrity hash is required';
    end if;
    if p_document_storage_path is null
       or p_document_sha256 is null
       or p_document_file_name is null then
      raise exception 'Final PDF and hash are required for approval';
    end if;
    if p_consent_text is null or btrim(p_consent_text)='' then
      raise exception 'Explicit approval consent is required';
    end if;
  end if;

  begin
    if p_ip_address is not null and btrim(p_ip_address)<>'' then
      v_ip := split_part(p_ip_address, ',', 1)::inet;
    end if;
  exception when others then
    v_ip := null;
  end;

  insert into public.rf_customer_signatures(
    version_id,
    customer_contact_id,
    signer_user_id,
    signer_name,
    decision,
    signature_storage_path,
    signature_sha256,
    document_sha256,
    auth_method,
    ip_address,
    user_agent,
    consent_text,
    consent_version
  )
  values(
    p_version_id,
    p_customer_contact_id,
    p_signer_user_id,
    btrim(p_signer_name),
    p_decision,
    p_signature_storage_path,
    p_signature_sha256,
    p_document_sha256,
    coalesce(nullif(p_auth_method,''),'unknown'),
    v_ip,
    p_user_agent,
    p_consent_text,
    p_consent_version
  );

  if p_decision='approved' then
    insert into public.rf_documents(
      version_id,
      document_type,
      storage_path,
      file_name,
      mime_type,
      byte_size,
      sha256
    )
    values(
      p_version_id,
      'signed_regie_pdf',
      p_document_storage_path,
      p_document_file_name,
      'application/pdf',
      p_document_byte_size,
      p_document_sha256
    );

    update public.rf_regies
    set status='approved',updated_at=now()
    where id=v_regie.id;
  else
    update public.rf_regies
    set status='rejected',updated_at=now()
    where id=v_regie.id;
  end if;

  if p_auth_method='secure_link' then
    update public.rf_public_approval_links
    set used_at=coalesce(used_at,now())
    where version_id=p_version_id
      and customer_contact_id=p_customer_contact_id
      and used_at is null
      and revoked_at is null;
  end if;

  insert into public.rf_audit_log(
    company_id,
    project_id,
    regie_id,
    actor_user_id,
    actor_customer_contact_id,
    event_type,
    metadata
  )
  values(
    v_regie.company_id,
    v_regie.project_id,
    v_regie.id,
    p_signer_user_id,
    p_customer_contact_id,
    'customer_'||p_decision,
    jsonb_build_object(
      'version_id',p_version_id,
      'version_no',v_version.version_no,
      'auth_method',p_auth_method,
      'document_sha256',p_document_sha256,
      'signature_sha256',p_signature_sha256,
      'consent_version',p_consent_version
    )
  );

  return case when p_decision='approved' then 'approved' else 'rejected' end;
end
$$;

revoke all on function public.rf_finalize_customer_decision_v2(
  uuid,uuid,uuid,text,text,text,text,text,text,text,bigint,text,text,text,text,text
) from public,anon,authenticated;

grant execute on function public.rf_finalize_customer_decision_v2(
  uuid,uuid,uuid,text,text,text,text,text,text,text,bigint,text,text,text,text,text
) to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Signature evidence strengthened',
'Added immutable signature SHA-256, explicit consent text and consent version to customer approval evidence. New service-only finalization RPC v2 requires these fields for approvals and stores them in both the signature evidence row and audit metadata. This strengthens the evidence chain if a signer later disputes what was approved.');


-- 20261001094803 regieflow_close_regie_v2_v1

create or replace function public.rf_close_regie_v2(p_regie_id uuid, p_rapport_number text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
begin
  if p_rapport_number is null or btrim(p_rapport_number)='' then
    raise exception 'Rapportnummer ist erforderlich';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.close') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_rapport' then
    raise exception 'Regie wartet nicht auf eine Rapportnummer';
  end if;

  update public.rf_regies
  set rapport_number=btrim(p_rapport_number),
      status='closed',
      closed_at=now(),
      updated_at=now()
  where id=p_regie_id;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),
    'regie_closed',
    jsonb_build_object('rapport_number',btrim(p_rapport_number))
  );

  return 'closed';
end
$$;

revoke all on function public.rf_close_regie_v2(uuid,text) from public,anon;
grant execute on function public.rf_close_regie_v2(uuid,text) to authenticated;


-- 20261001094856 regieflow_revoke_unsafe_table_privileges_v1

revoke truncate, references, trigger on
  public.rf_companies,
  public.rf_roles,
  public.rf_memberships,
  public.rf_customer_contacts,
  public.rf_projects,
  public.rf_project_customer_access,
  public.rf_regies,
  public.rf_regie_versions,
  public.rf_regie_files,
  public.rf_internal_reviews,
  public.rf_customer_signatures,
  public.rf_documents,
  public.rf_regie_comments,
  public.rf_notifications,
  public.rf_push_subscriptions,
  public.rf_audit_log,
  public.rf_company_billing,
  public.rf_public_approval_links,
  public.rf_permission_catalog,
  public.rf_customer_invites,
  public.rf_plan_catalog
from authenticated;

revoke all privileges on all sequences in schema public from authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Critical privilege hardening: revoked TRUNCATE/TRIGGER/REFERENCES',
'Security review found authenticated retained PostgreSQL TRUNCATE, TRIGGER and REFERENCES privileges on RegieFlow tables despite DML restrictions. TRUNCATE can bypass row-level row operations and must never be available to app users. Revoked TRUNCATE, TRIGGER and REFERENCES from authenticated on every rf_* table and revoked sequence privileges. Explicit SELECT/INSERT/UPDATE/DELETE grants used by the UI remain unchanged.');


-- 20261001094910 regieflow_overview_privileges_hardening_v1

revoke truncate, references, trigger on public.rf_regie_overview from authenticated;
grant select on public.rf_regie_overview to authenticated;


-- 20261001094944 regieflow_audit_log_internal_only_v1

drop policy if exists rf_audit_select on public.rf_audit_log;
create policy rf_audit_select on public.rf_audit_log
for select to authenticated
using (public.rf_has_permission(company_id,'documents.view'));

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Audit log made internal-only',
'Customers no longer receive direct row-level access to the internal audit_log table merely because they are assigned to a project. Customer-facing evidence remains available through the signed PDF, photos, status history and signature record. Full audit metadata is restricted to internal users with documents.view.');


-- 20261001095005 regieflow_signature_select_internal_only_v1

drop policy if exists rf_customer_signatures_select on public.rf_customer_signatures;
create policy rf_customer_signatures_select on public.rf_customer_signatures
for select to authenticated
using (
  exists (
    select 1
    from public.rf_regie_versions v
    join public.rf_regies r on r.id=v.regie_id
    where v.id=version_id
      and public.rf_has_permission(r.company_id,'documents.view')
  )
);


-- 20261001095042 regieflow_remove_legacy_rpcs_v1

drop function if exists public.rf_close_regie(uuid,text);
drop function if exists public.rf_finalize_customer_decision(
  uuid,uuid,uuid,text,text,text,text,text,text,bigint,text,text,text
);

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Removed legacy approval and close RPCs',
'Cloudflare frontend is now deployed with rf_close_regie_v2 and both customer approval Edge Functions use rf_finalize_customer_decision_v2. The legacy close and customer-finalization RPCs were removed to reduce attack surface and eliminate old vendor-specific parameter naming.');


-- 20261001102742 regieflow_split_rls_write_policies_v1

drop policy if exists rf_customer_contacts_write on public.rf_customer_contacts;
create policy rf_customer_contacts_insert on public.rf_customer_contacts
for insert to authenticated
with check (public.rf_has_permission(company_id,'projects.manage'));
create policy rf_customer_contacts_update on public.rf_customer_contacts
for update to authenticated
using (public.rf_has_permission(company_id,'projects.manage'))
with check (public.rf_has_permission(company_id,'projects.manage'));
create policy rf_customer_contacts_delete on public.rf_customer_contacts
for delete to authenticated
using (public.rf_has_permission(company_id,'projects.manage'));

drop policy if exists rf_memberships_write on public.rf_memberships;
create policy rf_memberships_insert on public.rf_memberships
for insert to authenticated
with check (public.rf_has_permission(company_id,'users.manage'));
create policy rf_memberships_update on public.rf_memberships
for update to authenticated
using (public.rf_has_permission(company_id,'users.manage'))
with check (public.rf_has_permission(company_id,'users.manage'));
create policy rf_memberships_delete on public.rf_memberships
for delete to authenticated
using (public.rf_has_permission(company_id,'users.manage'));

drop policy if exists rf_project_customer_access_write on public.rf_project_customer_access;
create policy rf_project_customer_access_insert on public.rf_project_customer_access
for insert to authenticated
with check (
  exists (
    select 1 from public.rf_projects p
    where p.id=project_id
      and public.rf_has_permission(p.company_id,'projects.manage')
  )
);
create policy rf_project_customer_access_update on public.rf_project_customer_access
for update to authenticated
using (
  exists (
    select 1 from public.rf_projects p
    where p.id=project_id
      and public.rf_has_permission(p.company_id,'projects.manage')
  )
)
with check (
  exists (
    select 1 from public.rf_projects p
    where p.id=project_id
      and public.rf_has_permission(p.company_id,'projects.manage')
  )
);
create policy rf_project_customer_access_delete on public.rf_project_customer_access
for delete to authenticated
using (
  exists (
    select 1 from public.rf_projects p
    where p.id=project_id
      and public.rf_has_permission(p.company_id,'projects.manage')
  )
);

drop policy if exists rf_projects_write on public.rf_projects;
create policy rf_projects_insert on public.rf_projects
for insert to authenticated
with check (public.rf_has_permission(company_id,'projects.manage'));
create policy rf_projects_update on public.rf_projects
for update to authenticated
using (public.rf_has_permission(company_id,'projects.manage'))
with check (public.rf_has_permission(company_id,'projects.manage'));
create policy rf_projects_delete on public.rf_projects
for delete to authenticated
using (public.rf_has_permission(company_id,'projects.manage'));

drop policy if exists rf_roles_write on public.rf_roles;
create policy rf_roles_insert on public.rf_roles
for insert to authenticated
with check (public.rf_has_permission(company_id,'roles.manage'));
create policy rf_roles_update on public.rf_roles
for update to authenticated
using (public.rf_has_permission(company_id,'roles.manage'))
with check (public.rf_has_permission(company_id,'roles.manage'));
create policy rf_roles_delete on public.rf_roles
for delete to authenticated
using (public.rf_has_permission(company_id,'roles.manage'));

insert into regieflow_private.dev_log(kind,title,content) values
('completed','RLS write policies split by operation',
'Replaced broad ALL write policies on customer contacts, memberships, project customer access, projects and roles with separate INSERT/UPDATE/DELETE policies. This removes overlapping permissive SELECT policy evaluation and makes each mutation rule explicit without changing authorization semantics.');


-- 20261001095124 regieflow_customer_request_approval_permission_v1

create or replace function public.rf_decide_customer_request(
  p_regie_id uuid,
  p_decision text,
  p_assigned_monteur_user_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_status text;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.source <> 'customer' or v_regie.status <> 'customer_request' then
    raise exception 'Regie is not an open customer request';
  end if;

  if not public.rf_has_permission(v_regie.company_id,'regies.review') then
    raise exception 'Not allowed';
  end if;

  if p_decision='approved' then
    if p_assigned_monteur_user_id is not null and not exists (
      select 1
      from public.rf_memberships m
      where m.company_id=v_regie.company_id
        and m.user_id=p_assigned_monteur_user_id
        and m.active
    ) then
      raise exception 'Assigned Monteur is not an active internal user';
    end if;

    v_status := 'draft';
    update public.rf_regies
      set status='draft',
          assigned_monteur_user_id=p_assigned_monteur_user_id,
          updated_at=now()
    where id=p_regie_id;
  else
    v_status := 'rejected';
    update public.rf_regies
      set status='rejected',updated_at=now()
    where id=p_regie_id;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
    'customer_request_'||p_decision,
    jsonb_build_object('assigned_monteur_user_id',p_assigned_monteur_user_id)
  );

  if v_regie.requested_by_customer_contact_id is not null then
    insert into public.rf_notifications(
      company_id,recipient_customer_contact_id,regie_id,type,title,body
    )
    values(
      v_regie.company_id,v_regie.requested_by_customer_contact_id,v_regie.id,
      'customer_request_'||p_decision,
      case when p_decision='approved' then 'Auftrag wurde übernommen' else 'Auftrag wurde abgelehnt' end,
      case when p_decision='approved'
        then 'Ihre Anfrage wurde vom Betrieb übernommen.'
        else 'Ihre Anfrage wurde vom Betrieb abgelehnt.'
      end
    );
  end if;

  if p_decision='approved' and p_assigned_monteur_user_id is not null then
    insert into public.rf_notifications(
      company_id,recipient_user_id,regie_id,type,title,body
    )
    values(
      v_regie.company_id,p_assigned_monteur_user_id,v_regie.id,
      'customer_request_assigned',
      'Neuer Kundenauftrag',
      'Eine Kundenanfrage wurde Ihnen zugewiesen.'
    );
  end if;

  return v_status;
end
$$;

revoke all on function public.rf_decide_customer_request(uuid,text,uuid) from public,anon;
grant execute on function public.rf_decide_customer_request(uuid,text,uuid) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Customer-request approval now requires explicit review permission',
'Accepting or rejecting a customer-created request now requires regies.review. Merely having permission to create Regien is no longer enough. This matches the product rule that a Monteur may approve customer requests only when the Owner explicitly grants approval/review rights.');


-- 20261001095211 regieflow_file_immutability_v1

create or replace function public.rf_validate_regie_file_state()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_status text;
  v_locked timestamptz;
begin
  select status into v_status
  from public.rf_regies
  where id=new.regie_id;

  if v_status is null then
    raise exception 'Regie not found';
  end if;

  if new.kind in ('before','attachment') then
    if new.version_id is null then
      raise exception 'Version is required';
    end if;

    select locked_at into v_locked
    from public.rf_regie_versions
    where id=new.version_id
      and regie_id=new.regie_id;

    if not found then
      raise exception 'Version does not belong to Regie';
    end if;

    if v_locked is not null or v_status <> 'draft' then
      raise exception 'Submitted Regie evidence cannot be changed';
    end if;
  elsif new.kind='after' then
    if v_status not in ('approved','in_execution','awaiting_rapport') then
      raise exception 'After-work photos are not allowed in this state';
    end if;
  elsif new.kind='customer_request' then
    if v_status <> 'customer_request' then
      raise exception 'Customer request photo is not allowed in this state';
    end if;
  end if;

  return new;
end
$$;

revoke all on function public.rf_validate_regie_file_state() from public,anon,authenticated;

drop trigger if exists rf_validate_regie_file_state_trg on public.rf_regie_files;
create trigger rf_validate_regie_file_state_trg
before insert or update of regie_id,version_id,kind
on public.rf_regie_files
for each row execute function public.rf_validate_regie_file_state();

drop policy if exists rf_private_insert on storage.objects;
create policy rf_private_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='rf-private'
  and split_part(name,'/',3) in ('before','after','attachments','customer-request')
  and exists (
    select 1
    from public.rf_regies r
    where r.company_id = public.rf_storage_segment_uuid(name,1)
      and r.id = public.rf_storage_segment_uuid(name,2)
      and (
        (
          split_part(name,'/',3)='before'
          and r.status='draft'
          and public.rf_has_permission(r.company_id,'regies.create')
        )
        or
        (
          split_part(name,'/',3)='after'
          and r.status in ('approved','in_execution','awaiting_rapport')
          and (
            public.rf_has_permission(r.company_id,'regies.complete')
            or public.rf_has_permission(r.company_id,'regies.create')
          )
        )
        or
        (
          split_part(name,'/',3)='attachments'
          and r.status='draft'
          and public.rf_has_permission(r.company_id,'regies.create')
        )
        or
        (
          split_part(name,'/',3)='customer-request'
          and r.source='customer'
          and r.status='customer_request'
          and r.requested_by_customer_contact_id = public.rf_customer_contact_for_company(r.company_id)
          and public.rf_customer_has_project(r.project_id)
        )
      )
  )
);

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Submitted Regie photos/evidence made immutable',
'Before-work photos and attachments can now be added only while the Regie is Draft and its version is unlocked. After-work photos are allowed only during approved/execution/awaiting-rapport states. Customer-request photos are limited to the request state. Storage upload rules mirror these lifecycle restrictions, preventing evidence from being added after submission or after final close.');


-- 20261001095235 regieflow_revision_file_state_fix_v1

create or replace function public.rf_create_regie_revision(
  p_regie_id uuid,
  p_description text,
  p_estimate_label text,
  p_estimate_minutes integer default null,
  p_copy_before_photos boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_next integer;
  v_prev_version uuid;
  v_new_version uuid;
begin
  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status='closed' then raise exception 'Closed Regie cannot be revised'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then raise exception 'Not allowed'; end if;
  if p_description is null or btrim(p_description)='' then raise exception 'Description required'; end if;
  if p_estimate_label is null or btrim(p_estimate_label)='' then raise exception 'Estimate required'; end if;

  select coalesce(max(version_no),0)+1 into v_next
  from public.rf_regie_versions
  where regie_id=p_regie_id;

  select id into v_prev_version
  from public.rf_regie_versions
  where regie_id=p_regie_id
  order by version_no desc
  limit 1;

  insert into public.rf_regie_versions(
    regie_id,version_no,description,estimate_label,estimate_minutes,created_by_user_id
  )
  values(
    p_regie_id,v_next,btrim(p_description),btrim(p_estimate_label),p_estimate_minutes,auth.uid()
  )
  returning id into v_new_version;

  update public.rf_regies
  set status='draft',current_version_no=v_next,updated_at=now()
  where id=p_regie_id;

  if p_copy_before_photos and v_prev_version is not null then
    insert into public.rf_regie_files(
      regie_id,version_id,kind,storage_path,original_filename,mime_type,byte_size,sha256,sort_order,uploaded_by_user_id
    )
    select
      regie_id,v_new_version,'before',storage_path,original_filename,mime_type,byte_size,sha256,sort_order,auth.uid()
    from public.rf_regie_files
    where regie_id=p_regie_id
      and version_id=v_prev_version
      and kind='before';
  end if;

  update public.rf_public_approval_links pal
  set revoked_at=coalesce(revoked_at,now())
  where pal.version_id in (
    select id
    from public.rf_regie_versions
    where regie_id=p_regie_id and id<>v_new_version
  )
    and pal.used_at is null
    and pal.revoked_at is null;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),'regie_revision_created',
    jsonb_build_object(
      'new_version_id',v_new_version,
      'new_version_no',v_next,
      'copied_before_photos',p_copy_before_photos
    )
  );

  return jsonb_build_object('regieId',p_regie_id,'versionId',v_new_version,'versionNo',v_next);
end
$$;

revoke all on function public.rf_create_regie_revision(uuid,text,text,integer,boolean) from public,anon;
grant execute on function public.rf_create_regie_revision(uuid,text,text,integer,boolean) to authenticated;


-- 20261001100556 regieflow_human_notification_status_labels_v1

create or replace function public.rf_status_label(p_status text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_status
    when 'draft' then 'Entwurf'
    when 'customer_request' then 'Kundenanfrage'
    when 'submitted' then 'Gesendet'
    when 'internal_review' then 'Büroprüfung'
    when 'awaiting_customer' then 'Wartet auf Kunde'
    when 'approved' then 'Freigegeben'
    when 'rejected' then 'Abgelehnt'
    when 'in_execution' then 'In Ausführung'
    when 'work_completed' then 'Arbeit erledigt'
    when 'awaiting_rapport' then 'Rapportnummer fehlt'
    when 'closed' then 'Abgeschlossen'
    else p_status
  end
$$;

revoke all on function public.rf_status_label(text) from public,anon,authenticated;

create or replace function public.rf_notify_regie_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label text;
begin
  if tg_op <> 'UPDATE' or new.status is not distinct from old.status then
    return new;
  end if;

  v_label := public.rf_status_label(new.status);

  if new.status in ('customer_request','internal_review','awaiting_customer','approved','rejected','awaiting_rapport','closed') then
    insert into public.rf_notifications(company_id,recipient_user_id,regie_id,type,title,body)
    select new.company_id, x.user_id, new.id, 'regie_status',
           'Regie '||coalesce(new.regie_code,'')||': '||v_label,
           'Status: '||v_label||'.'
    from (
      select c.primary_owner_user_id as user_id
      from public.rf_companies c where c.id=new.company_id
      union
      select m.user_id
      from public.rf_memberships m
      left join public.rf_roles rr on rr.id=m.role_id
      where m.company_id=new.company_id and m.active
        and (
          (m.permission_overrides ? 'regies.review' and (m.permission_overrides->>'regies.review')::boolean)
          or 'regies.review'=any(coalesce(rr.permissions,'{}'::text[]))
          or m.user_id=new.assigned_monteur_user_id
        )
    ) x
    where x.user_id is not null
    on conflict do nothing;
  end if;

  if new.status='awaiting_customer' then
    insert into public.rf_notifications(company_id,recipient_customer_contact_id,regie_id,type,title,body)
    select new.company_id, a.customer_contact_id, new.id, 'approval_required',
           'Freigabe erforderlich',
           'Eine Regie wartet auf Ihre Freigabe.'
    from public.rf_project_customer_access a
    where a.project_id=new.project_id and a.can_sign;
  elsif new.status in ('approved','rejected','closed') then
    insert into public.rf_notifications(company_id,recipient_customer_contact_id,regie_id,type,title,body)
    select new.company_id, a.customer_contact_id, new.id, 'regie_status',
           'Regie '||coalesce(new.regie_code,'')||': '||v_label,
           'Status: '||v_label||'.'
    from public.rf_project_customer_access a
    where a.project_id=new.project_id;
  end if;

  return new;
end
$$;

revoke all on function public.rf_notify_regie_status_change() from public,anon,authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Notification status labels humanized',
'Internal status codes such as awaiting_customer are no longer generated into user-facing notification titles/bodies. Backend trigger now stores German human-readable labels; frontend also translates legacy notifications already stored.');


-- 20261001102042 regieflow_restore_required_client_dml_v1

grant update on public.rf_companies to authenticated;
grant insert on public.rf_projects to authenticated;
grant insert on public.rf_customer_contacts to authenticated;
grant update on public.rf_project_customer_access to authenticated;
grant update on public.rf_regie_versions to authenticated;
grant update on public.rf_memberships to authenticated;
grant update on public.rf_notifications to authenticated;
grant update on public.rf_push_subscriptions to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Restored minimum client DML grants after hardening',
'Frontend mutation audit found several RLS-protected operations lost their table-level privileges during earlier grant minimization. Restored only the operations actually used by the app: company settings update, project insert, customer-contact insert, project-customer access update, unlocked draft-version update, membership role update, notification read-state update, and push-subscription upsert update. No direct INSERT/UPDATE privilege was restored on rf_regies; workflow state remains RPC-only.');


-- 20261001102958 regieflow_public_link_first_view_evidence_v1

alter table public.rf_public_approval_links
  add column if not exists first_viewed_at timestamptz,
  add column if not exists first_view_ip inet,
  add column if not exists first_view_user_agent text;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Public approval first-view evidence schema added',
'Secure approval links now have fields for first-view timestamp, first-view IP and first-view user agent. The public approval Edge Function will populate these once, providing additional evidence that the specific secure link was opened before a decision.');


-- 20261001103125 regieflow_limit_team_directory_visibility_v1

drop policy if exists rf_memberships_select on public.rf_memberships;
create policy rf_memberships_select on public.rf_memberships
for select to authenticated
using (
  user_id=(select auth.uid())
  or public.rf_has_permission(company_id,'users.manage')
  or public.rf_has_permission(company_id,'roles.manage')
);

drop policy if exists rf_roles_select on public.rf_roles;
create policy rf_roles_select on public.rf_roles
for select to authenticated
using (
  public.rf_has_permission(company_id,'users.manage')
  or public.rf_has_permission(company_id,'roles.manage')
  or exists (
    select 1
    from public.rf_memberships m
    where m.company_id=rf_roles.company_id
      and m.user_id=(select auth.uid())
      and m.role_id=rf_roles.id
      and m.active
  )
);

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Team directory visibility reduced for Monteure',
'Ordinary internal users no longer gain API-level visibility of every company membership and all roles simply because they belong to the company. A user may read their own membership/role; users.manage or roles.manage may read the team directory. This matches the UI separation between Monteur and Büro/administration.');


-- 20261001103306 regieflow_lightweight_comments_v1

create or replace function public.rf_get_regie_comments(p_regie_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_allowed boolean;
  v_result jsonb;
begin
  select * into v_regie
  from public.rf_regies
  where id=p_regie_id;

  if not found then raise exception 'Regie not found'; end if;

  v_allowed :=
    public.rf_has_permission(v_regie.company_id,'regies.view')
    or public.rf_customer_has_project(v_regie.project_id);

  if not v_allowed then raise exception 'Not allowed'; end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',c.id,
      'body',c.body,
      'createdAt',c.created_at,
      'actorType',case when c.actor_user_id is not null then 'internal' else 'customer' end,
      'actorName',case
        when c.actor_user_id is not null then coalesce((
          select m.display_name
          from public.rf_memberships m
          where m.company_id=v_regie.company_id
            and m.user_id=c.actor_user_id
          limit 1
        ),'Mitarbeiter')
        else coalesce((
          select cc.full_name
          from public.rf_customer_contacts cc
          where cc.id=c.actor_customer_contact_id
          limit 1
        ),'Kunde')
      end
    )
    order by c.created_at
  ),'[]'::jsonb)
  into v_result
  from public.rf_regie_comments c
  where c.regie_id=p_regie_id;

  return v_result;
end
$$;

create or replace function public.rf_add_regie_comment(
  p_regie_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_contact uuid;
  v_id uuid;
begin
  if p_body is null or char_length(btrim(p_body)) < 1 then
    raise exception 'Kommentar darf nicht leer sein';
  end if;
  if char_length(btrim(p_body)) > 4000 then
    raise exception 'Kommentar ist zu lang';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status in ('closed','rejected') then
    raise exception 'Archivierte Regien sind schreibgeschützt';
  end if;

  if public.rf_is_internal_member(v_regie.company_id)
     and public.rf_has_permission(v_regie.company_id,'regies.view') then
    insert into public.rf_regie_comments(regie_id,actor_user_id,body)
    values(p_regie_id,auth.uid(),btrim(p_body))
    returning id into v_id;
  else
    select c.id into v_contact
    from public.rf_project_customer_access a
    join public.rf_customer_contacts c on c.id=a.customer_contact_id
    where a.project_id=v_regie.project_id
      and c.auth_user_id=auth.uid()
      and c.active
    limit 1;

    if v_contact is null then raise exception 'Not allowed'; end if;

    insert into public.rf_regie_comments(regie_id,actor_customer_contact_id,body)
    values(p_regie_id,v_contact,btrim(p_body))
    returning id into v_id;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_regie.company_id,
    v_regie.project_id,
    v_regie.id,
    case when v_contact is null then auth.uid() else null end,
    v_contact,
    'regie_comment_added',
    jsonb_build_object('comment_id',v_id)
  );

  return v_id;
end
$$;

revoke all on function public.rf_get_regie_comments(uuid) from public,anon;
grant execute on function public.rf_get_regie_comments(uuid) to authenticated;
revoke all on function public.rf_add_regie_comment(uuid,text) from public,anon;
grant execute on function public.rf_add_regie_comment(uuid,text) to authenticated;

revoke insert, update, delete on public.rf_regie_comments from authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Lightweight Regie comments backend completed',
'Added controlled comment RPCs. Authorized internal users and assigned project customers can read a simple comment timeline; open Regien can receive comments, while closed/rejected archive items are read-only. Actor names are returned without exposing unnecessary account data. Comment creation is audit-logged and direct client mutations are no longer permitted.');


-- 20261001103511 regieflow_project_input_constraints_v1

alter table public.rf_projects
  add constraint rf_projects_project_number_check
  check (
    char_length(btrim(project_number)) between 1 and 100
  );

alter table public.rf_projects
  add constraint rf_projects_address_check
  check (
    address is null or char_length(btrim(address)) <= 500
  );

alter table public.rf_projects
  add constraint rf_projects_client_name_check
  check (
    client_name is null or char_length(btrim(client_name)) <= 180
  );

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Project input constraints tightened',
'Added database validation for non-empty project numbers and bounded project address/client text. This prevents malformed projects even when requests bypass the browser UI.');


-- 20261001103634 regieflow_evidence_uploader_provenance_v1

alter table public.rf_regie_files
  add column if not exists uploaded_by_customer_contact_id uuid
  references public.rf_customer_contacts(id) on delete set null;

create index if not exists rf_regie_files_customer_uploader_idx
  on public.rf_regie_files(uploaded_by_customer_contact_id)
  where uploaded_by_customer_contact_id is not null;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Evidence uploader provenance extended',
'Regie evidence files can now record the customer contact that uploaded a customer-request image, in addition to the existing internal-user uploader field. This supports server-side evidence registration with precise provenance.');


-- 20261001103849 regieflow_server_side_evidence_registration_v1

drop policy if exists rf_private_insert on storage.objects;
drop policy if exists rf_files_insert on public.rf_regie_files;

revoke insert on public.rf_regie_files from authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Evidence uploads moved behind trusted server endpoint',
'The live frontend now sends before/after/customer-request evidence through rf-upload-evidence. The Edge Function authenticates the user, validates Regie lifecycle and permissions, generates the storage path, uploads the bytes with service credentials, computes SHA-256 server-side, records actual byte size/MIME type and uploader provenance, and removes the object if registration fails. Direct authenticated uploads to rf-private and direct rf_regie_files inserts were disabled, preventing clients from forging evidence hashes or metadata.');


-- 20261001150059 regieflow_evidence_upload_rpc_only_v1

revoke insert on public.rf_regie_files from authenticated;

drop policy if exists rf_private_insert on storage.objects;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Evidence uploads forced through server endpoint',
'The frontend now uses rf-upload-evidence for all before/after/attachment/customer-request files. Direct authenticated INSERT on rf_regie_files and the direct rf-private Storage INSERT policy were removed. The server endpoint validates caller identity, project/Regie lifecycle, file size/type, computes SHA-256, records uploader identity and cleans up failed uploads. This prevents clients from bypassing evidence validation or creating orphan evidence objects.');


-- 20261001104819 regieflow_comment_notifications_v1

create or replace function public.rf_add_regie_comment(
  p_regie_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_contact uuid;
  v_id uuid;
  v_internal boolean := false;
begin
  if p_body is null or char_length(btrim(p_body)) < 1 then
    raise exception 'Kommentar darf nicht leer sein';
  end if;
  if char_length(btrim(p_body)) > 4000 then
    raise exception 'Kommentar ist zu lang';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status in ('closed','rejected') then
    raise exception 'Archivierte Regien sind schreibgeschützt';
  end if;

  if public.rf_is_internal_member(v_regie.company_id)
     and public.rf_has_permission(v_regie.company_id,'regies.view') then
    v_internal := true;
    insert into public.rf_regie_comments(regie_id,actor_user_id,body)
    values(p_regie_id,auth.uid(),btrim(p_body))
    returning id into v_id;
  else
    select c.id into v_contact
    from public.rf_project_customer_access a
    join public.rf_customer_contacts c on c.id=a.customer_contact_id
    where a.project_id=v_regie.project_id
      and c.auth_user_id=auth.uid()
      and c.active
    limit 1;

    if v_contact is null then raise exception 'Not allowed'; end if;

    insert into public.rf_regie_comments(regie_id,actor_customer_contact_id,body)
    values(p_regie_id,v_contact,btrim(p_body))
    returning id into v_id;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_regie.company_id,
    v_regie.project_id,
    v_regie.id,
    case when v_internal then auth.uid() else null end,
    v_contact,
    'regie_comment_added',
    jsonb_build_object('comment_id',v_id)
  );

  if v_internal then
    insert into public.rf_notifications(
      company_id,recipient_customer_contact_id,regie_id,type,title,body
    )
    select
      v_regie.company_id,
      a.customer_contact_id,
      v_regie.id,
      'regie_comment',
      'Neue Notiz · '||coalesce(v_regie.regie_code,'Regie'),
      left(btrim(p_body),240)
    from public.rf_project_customer_access a
    where a.project_id=v_regie.project_id;
  else
    insert into public.rf_notifications(
      company_id,recipient_user_id,regie_id,type,title,body
    )
    select
      v_regie.company_id,
      x.user_id,
      v_regie.id,
      'regie_comment',
      'Neue Kundennotiz · '||coalesce(v_regie.regie_code,'Regie'),
      left(btrim(p_body),240)
    from (
      select c.primary_owner_user_id as user_id
      from public.rf_companies c
      where c.id=v_regie.company_id
      union
      select v_regie.assigned_monteur_user_id
    ) x
    where x.user_id is not null;
  end if;

  return v_id;
end
$$;

revoke all on function public.rf_add_regie_comment(uuid,text) from public,anon;
grant execute on function public.rf_add_regie_comment(uuid,text) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Shared Regie notes now notify the other side',
'Lightweight Regie notes now create in-app/Push-ready notifications: an internal note notifies project customer contacts; a customer note notifies the company Primary Owner and assigned Monteur. No email/SMS is sent. Archived/rejected Regien remain read-only.');


-- 20261001105110 regieflow_role_edit_privilege_v1

grant update on public.rf_roles to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Role editing enabled',
'Authenticated users still require roles.manage through RLS, but now have the table-level UPDATE privilege needed for the role-edit UI. This allows Owners/authorized admins to adjust custom role names and granular permissions after creation.');


-- 20261001105246 regieflow_internal_catalog_visibility_v1

drop policy if exists rf_permission_catalog_read on public.rf_permission_catalog;
create policy rf_permission_catalog_read on public.rf_permission_catalog
for select to authenticated
using (
  exists (
    select 1 from public.rf_memberships m
    where m.user_id=(select auth.uid()) and m.active
  )
);

drop policy if exists rf_plan_catalog_read on public.rf_plan_catalog;
create policy rf_plan_catalog_read on public.rf_plan_catalog
for select to authenticated
using (
  exists (
    select 1 from public.rf_memberships m
    where m.user_id=(select auth.uid()) and m.active
  )
);

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Internal catalogs hidden from customer accounts',
'Permission and commercial plan catalogs are now readable only by active internal members. Customer accounts have no product need for these administrative datasets, so their direct API visibility was removed.');


-- 20261001105619 regieflow_pdf_compatible_branding_formats_v1

update storage.buckets
set allowed_mime_types=array['image/jpeg','image/png']::text[]
where id='rf-branding';

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Company logo formats aligned with PDF generation',
'Branding uploads are now limited to PNG/JPEG, the formats embedded reliably by the RegieFlow PDF generator. WebP/SVG were previously accepted by Storage/browser UI but could be omitted from final signed PDFs.');


-- 20261001105657 regieflow_pdf_compatible_evidence_formats_v1

update storage.buckets
set allowed_mime_types=array['image/jpeg','image/png','application/pdf']::text[]
where id='rf-private';

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Regie photo formats aligned with signed PDF generation',
'Before/after/customer-request photo uploads are being restricted to PNG/JPEG so mandatory evidence can always be embedded into the final PDF. PDF remains allowed for future attachment use. WebP was removed because pdf-lib does not embed it directly.');


-- 20261001123756 regieflow_current_version_integrity_v2

create or replace function public.rf_review_regie_version(
  p_version_id uuid,
  p_decision text,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version public.rf_regie_versions%rowtype;
  v_status text;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select * into v_version
  from public.rf_regie_versions
  where id=p_version_id;

  if not found then raise exception 'Version not found'; end if;

  select * into v_regie
  from public.rf_regies
  where id=v_version.regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.review') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'internal_review' then
    raise exception 'Regie is not awaiting internal review';
  end if;
  if v_version.version_no <> v_regie.current_version_no then
    raise exception 'Only the current Regie version can be reviewed';
  end if;
  if v_version.locked_at is null then
    raise exception 'Current version is not submitted';
  end if;

  insert into public.rf_internal_reviews(version_id,reviewer_user_id,decision,note)
  values(p_version_id,auth.uid(),p_decision,p_note);

  v_status := case when p_decision='approved' then 'awaiting_customer' else 'rejected' end;

  update public.rf_regies
  set status=v_status,updated_at=now()
  where id=v_regie.id;

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
    'internal_review_'||p_decision,
    jsonb_build_object('version_id',p_version_id,'version_no',v_version.version_no)
  );

  return v_status;
end
$$;

revoke all on function public.rf_review_regie_version(uuid,text,text) from public,anon;
grant execute on function public.rf_review_regie_version(uuid,text,text) to authenticated;

create or replace function public.rf_create_public_approval_link(
  p_version_id uuid,
  p_customer_contact_id uuid,
  p_valid_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version public.rf_regie_versions%rowtype;
  v_token text;
begin
  if p_valid_hours < 1 or p_valid_hours > 720 then
    raise exception 'Link validity must be between 1 and 720 hours';
  end if;

  select * into v_version
  from public.rf_regie_versions
  where id=p_version_id;

  if not found then raise exception 'Version not found'; end if;

  select * into v_regie
  from public.rf_regies
  where id=v_version.regie_id;

  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_customer' then
    raise exception 'Regie is not awaiting customer approval';
  end if;
  if v_version.version_no <> v_regie.current_version_no or v_version.locked_at is null then
    raise exception 'Only the current submitted version can be shared for approval';
  end if;
  if not exists (
    select 1
    from public.rf_project_customer_access a
    where a.project_id=v_regie.project_id
      and a.customer_contact_id=p_customer_contact_id
      and a.can_sign
  ) then
    raise exception 'Customer is not authorized to sign this project';
  end if;

  v_token := encode(gen_random_bytes(32),'hex');

  update public.rf_public_approval_links
  set revoked_at=coalesce(revoked_at,now())
  where version_id=p_version_id
    and customer_contact_id=p_customer_contact_id
    and used_at is null
    and revoked_at is null;

  insert into public.rf_public_approval_links(
    company_id,version_id,customer_contact_id,token_hash,expires_at,created_by_user_id
  )
  values(
    v_regie.company_id,p_version_id,p_customer_contact_id,
    encode(digest(v_token,'sha256'),'hex'),
    now()+make_interval(hours=>p_valid_hours),
    auth.uid()
  );

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
    'public_approval_link_created',
    jsonb_build_object('version_id',p_version_id,'version_no',v_version.version_no,'valid_hours',p_valid_hours)
  );

  return v_token;
end
$$;

revoke all on function public.rf_create_public_approval_link(uuid,uuid,integer) from public,anon;
grant execute on function public.rf_create_public_approval_link(uuid,uuid,integer) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Current-version review/link integrity enforced',
'Review and secure-link creation now require the exact current submitted Regie version. This prevents stale historical versions from being reviewed or shared after a later revision exists. Creating a replacement secure link revokes the previous unused link for the same signer/version.');


-- 20261001123824 regieflow_finalize_current_version_integrity_v1

create or replace function public.rf_finalize_customer_decision_v2(
  p_version_id uuid,
  p_customer_contact_id uuid,
  p_signer_user_id uuid,
  p_signer_name text,
  p_decision text,
  p_signature_storage_path text,
  p_signature_sha256 text,
  p_document_storage_path text,
  p_document_file_name text,
  p_document_sha256 text,
  p_document_byte_size bigint,
  p_auth_method text,
  p_ip_address text,
  p_user_agent text,
  p_consent_text text,
  p_consent_version text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version public.rf_regie_versions%rowtype;
  v_contact public.rf_customer_contacts%rowtype;
  v_ip inet;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select * into v_version
  from public.rf_regie_versions
  where id=p_version_id;

  if not found then raise exception 'Version not found'; end if;
  if v_version.locked_at is null then raise exception 'Version is not locked/submitted'; end if;

  select * into v_regie
  from public.rf_regies
  where id=v_version.regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status <> 'awaiting_customer' then
    raise exception 'Regie is not awaiting customer approval';
  end if;
  if v_version.version_no <> v_regie.current_version_no then
    raise exception 'Only the current Regie version can be approved';
  end if;

  select * into v_contact
  from public.rf_customer_contacts
  where id=p_customer_contact_id
    and company_id=v_regie.company_id
    and active;

  if not found then raise exception 'Customer contact not found'; end if;

  if not exists (
    select 1
    from public.rf_project_customer_access a
    where a.project_id=v_regie.project_id
      and a.customer_contact_id=p_customer_contact_id
      and a.can_sign
  ) then
    raise exception 'Customer is not authorized to sign this project';
  end if;

  if p_signer_user_id is not null
     and v_contact.auth_user_id is distinct from p_signer_user_id then
    raise exception 'Signer account does not match customer contact';
  end if;

  if p_signer_name is null or btrim(p_signer_name)='' then
    raise exception 'Signer name is required';
  end if;

  if p_decision='approved' then
    if p_signature_storage_path is null or btrim(p_signature_storage_path)='' then
      raise exception 'Signature is required for approval';
    end if;
    if p_signature_sha256 is null or btrim(p_signature_sha256)='' then
      raise exception 'Signature integrity hash is required';
    end if;
    if p_document_storage_path is null
       or p_document_sha256 is null
       or p_document_file_name is null then
      raise exception 'Final PDF and hash are required for approval';
    end if;
    if p_consent_text is null or btrim(p_consent_text)='' then
      raise exception 'Explicit approval consent is required';
    end if;
  end if;

  begin
    if p_ip_address is not null and btrim(p_ip_address)<>'' then
      v_ip := split_part(p_ip_address, ',', 1)::inet;
    end if;
  exception when others then
    v_ip := null;
  end;

  insert into public.rf_customer_signatures(
    version_id,customer_contact_id,signer_user_id,signer_name,decision,
    signature_storage_path,signature_sha256,document_sha256,auth_method,
    ip_address,user_agent,consent_text,consent_version
  )
  values(
    p_version_id,p_customer_contact_id,p_signer_user_id,btrim(p_signer_name),p_decision,
    p_signature_storage_path,p_signature_sha256,p_document_sha256,
    coalesce(nullif(p_auth_method,''),'unknown'),v_ip,p_user_agent,p_consent_text,p_consent_version
  );

  if p_decision='approved' then
    insert into public.rf_documents(
      version_id,document_type,storage_path,file_name,mime_type,byte_size,sha256
    )
    values(
      p_version_id,'signed_regie_pdf',p_document_storage_path,p_document_file_name,
      'application/pdf',p_document_byte_size,p_document_sha256
    );

    update public.rf_regies
    set status='approved',updated_at=now()
    where id=v_regie.id;
  else
    update public.rf_regies
    set status='rejected',updated_at=now()
    where id=v_regie.id;
  end if;

  if p_auth_method='secure_link' then
    update public.rf_public_approval_links
    set used_at=coalesce(used_at,now())
    where version_id=p_version_id
      and customer_contact_id=p_customer_contact_id
      and used_at is null
      and revoked_at is null;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,p_signer_user_id,p_customer_contact_id,
    'customer_'||p_decision,
    jsonb_build_object(
      'version_id',p_version_id,
      'version_no',v_version.version_no,
      'auth_method',p_auth_method,
      'document_sha256',p_document_sha256,
      'signature_sha256',p_signature_sha256,
      'consent_version',p_consent_version
    )
  );

  return case when p_decision='approved' then 'approved' else 'rejected' end;
end
$$;

revoke all on function public.rf_finalize_customer_decision_v2(
  uuid,uuid,uuid,text,text,text,text,text,text,text,bigint,text,text,text,text,text
) from public,anon,authenticated;

grant execute on function public.rf_finalize_customer_decision_v2(
  uuid,uuid,uuid,text,text,text,text,text,text,text,bigint,text,text,text,text,text
) to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Final customer decision bound to current version',
'The service-only customer-finalization RPC now rejects any historical/non-current version even if the Regie is otherwise awaiting approval. This closes the stale-version approval path for both account and secure-link signing.');


-- 20261001145932 regieflow_restore_file_comment_insert_v1

grant insert on public.rf_regie_files to authenticated;
grant insert on public.rf_regie_comments to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Restored file/comment insert privileges',
'Frontend privilege audit found that authenticated had lost table-level INSERT on rf_regie_files and rf_regie_comments while RLS policies still expected those client operations. Restored INSERT only; UPDATE/DELETE remain unavailable so uploaded evidence and comments stay append-only from the client.');


-- 20261001150005 regieflow_comments_rpc_only_v1

revoke insert on public.rf_regie_comments from authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Comments made RPC-only',
'Frontend uses rf_add_regie_comment rather than direct table inserts. Direct INSERT privilege on rf_regie_comments was revoked again so users cannot bypass archive read-only checks, audit logging, or comment notifications. Comment creation is now forced through the controlled RPC.');


-- 20261001150708 regieflow_column_level_update_hardening_v1

revoke update on public.rf_companies from authenticated;
grant update(name,accent_color,logo_path) on public.rf_companies to authenticated;

revoke update on public.rf_regie_versions from authenticated;
grant update(description,estimate_label,estimate_minutes) on public.rf_regie_versions to authenticated;

revoke update on public.rf_project_customer_access from authenticated;
grant update(can_sign,label) on public.rf_project_customer_access to authenticated;

revoke update on public.rf_notifications from authenticated;
grant update(read_at) on public.rf_notifications to authenticated;

revoke update on public.rf_roles from authenticated;
grant update(name,permissions) on public.rf_roles to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Column-level mutation privileges hardened',
'Reduced direct browser UPDATE privileges to the exact fields used by the UI: company name/accent/logo; unlocked Regie description/estimate; project customer can_sign/label; notification read_at; and role name/permissions. Structural IDs, owner IDs, version numbers, audit fields and other lifecycle-sensitive columns can no longer be changed through direct PostgREST updates.');


-- 20261001150729 regieflow_membership_mutation_rpcs_v1

create or replace function public.rf_set_member_role(
  p_membership_id uuid,
  p_role_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.rf_memberships%rowtype;
  v_owner uuid;
begin
  select * into v_member
  from public.rf_memberships
  where id=p_membership_id
  for update;

  if not found then raise exception 'Membership not found'; end if;
  if not public.rf_has_permission(v_member.company_id,'users.manage') then
    raise exception 'Not allowed';
  end if;

  select primary_owner_user_id into v_owner
  from public.rf_companies
  where id=v_member.company_id;

  if v_member.user_id=v_owner then
    raise exception 'Primary Owner role cannot be changed here';
  end if;

  if v_member.user_id=auth.uid() and auth.uid()<>v_owner then
    raise exception 'You cannot change your own role';
  end if;

  if p_role_id is not null and not exists (
    select 1 from public.rf_roles
    where id=p_role_id and company_id=v_member.company_id
  ) then
    raise exception 'Role does not belong to this company';
  end if;

  update public.rf_memberships
  set role_id=p_role_id,updated_at=now()
  where id=p_membership_id;

  insert into public.rf_audit_log(company_id,actor_user_id,event_type,metadata)
  values(
    v_member.company_id,auth.uid(),'membership_role_changed',
    jsonb_build_object('membership_id',p_membership_id,'user_id',v_member.user_id,'role_id',p_role_id)
  );

  return true;
end
$$;

create or replace function public.rf_set_member_active(
  p_membership_id uuid,
  p_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.rf_memberships%rowtype;
  v_owner uuid;
begin
  select * into v_member
  from public.rf_memberships
  where id=p_membership_id
  for update;

  if not found then raise exception 'Membership not found'; end if;
  if not public.rf_has_permission(v_member.company_id,'users.manage') then
    raise exception 'Not allowed';
  end if;

  select primary_owner_user_id into v_owner
  from public.rf_companies
  where id=v_member.company_id;

  if v_member.user_id=v_owner and not p_active then
    raise exception 'Primary Owner cannot be deactivated';
  end if;

  if v_member.user_id=auth.uid() and not p_active then
    raise exception 'You cannot deactivate your own account';
  end if;

  update public.rf_memberships
  set active=p_active,updated_at=now()
  where id=p_membership_id;

  insert into public.rf_audit_log(company_id,actor_user_id,event_type,metadata)
  values(
    v_member.company_id,auth.uid(),
    case when p_active then 'membership_activated' else 'membership_deactivated' end,
    jsonb_build_object('membership_id',p_membership_id,'user_id',v_member.user_id)
  );

  return true;
end
$$;

revoke all on function public.rf_set_member_role(uuid,uuid) from public,anon;
grant execute on function public.rf_set_member_role(uuid,uuid) to authenticated;

revoke all on function public.rf_set_member_active(uuid,boolean) from public,anon;
grant execute on function public.rf_set_member_active(uuid,boolean) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Controlled membership mutation RPCs added',
'Added controlled RPCs for assigning a role and activating/deactivating internal users. They require users.manage, protect Primary Owner, prevent delegated admins from changing their own role, prevent self-deactivation, validate role tenant ownership, and write audit events.');


-- 20261001150905 regieflow_membership_direct_update_removed_v1

revoke update on public.rf_memberships from authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Direct membership UPDATE removed',
'Cloudflare is live with rf_set_member_role and rf_set_member_active. Direct authenticated UPDATE on rf_memberships is now revoked. This closes self-escalation through permission_overrides or arbitrary membership-column edits; role and activation changes must pass the controlled audited RPCs.');


-- 20261001151231 regieflow_admin_change_audit_triggers_v1

create or replace function public.rf_audit_project_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.rf_audit_log(company_id,project_id,actor_user_id,event_type,metadata)
  values(
    new.company_id,new.id,auth.uid(),
    case when tg_op='INSERT' then 'project_created' else 'project_updated' end,
    jsonb_build_object(
      'project_number',new.project_number,
      'name',new.name,
      'approval_workflow',new.approval_workflow,
      'active',new.active
    )
  );
  return new;
end
$$;

revoke all on function public.rf_audit_project_change() from public,anon,authenticated;
drop trigger if exists rf_audit_project_change_trg on public.rf_projects;
create trigger rf_audit_project_change_trg
after insert or update on public.rf_projects
for each row execute function public.rf_audit_project_change();

create or replace function public.rf_audit_customer_contact_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.rf_audit_log(company_id,actor_user_id,actor_customer_contact_id,event_type,metadata)
  values(
    new.company_id,
    auth.uid(),
    new.id,
    case when tg_op='INSERT' then 'customer_contact_created' else 'customer_contact_updated' end,
    jsonb_build_object(
      'full_name',new.full_name,
      'organization_name',new.organization_name,
      'active',new.active,
      'has_account',new.auth_user_id is not null
    )
  );
  return new;
end
$$;

revoke all on function public.rf_audit_customer_contact_change() from public,anon,authenticated;
drop trigger if exists rf_audit_customer_contact_change_trg on public.rf_customer_contacts;
create trigger rf_audit_customer_contact_change_trg
after insert or update on public.rf_customer_contacts
for each row execute function public.rf_audit_customer_contact_change();

create or replace function public.rf_audit_project_customer_access_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_id uuid;
  v_contact_id uuid;
  v_company_id uuid;
  v_can_sign boolean;
  v_label text;
begin
  v_project_id := case when tg_op='DELETE' then old.project_id else new.project_id end;
  v_contact_id := case when tg_op='DELETE' then old.customer_contact_id else new.customer_contact_id end;
  v_can_sign := case when tg_op='DELETE' then old.can_sign else new.can_sign end;
  v_label := case when tg_op='DELETE' then old.label else new.label end;

  select company_id into v_company_id
  from public.rf_projects
  where id=v_project_id;

  insert into public.rf_audit_log(company_id,project_id,actor_user_id,actor_customer_contact_id,event_type,metadata)
  values(
    v_company_id,v_project_id,auth.uid(),v_contact_id,
    case
      when tg_op='INSERT' then 'project_customer_access_added'
      when tg_op='UPDATE' then 'project_customer_access_changed'
      else 'project_customer_access_removed'
    end,
    jsonb_build_object('customer_contact_id',v_contact_id,'can_sign',v_can_sign,'label',v_label)
  );

  return case when tg_op='DELETE' then old else new end;
end
$$;

revoke all on function public.rf_audit_project_customer_access_change() from public,anon,authenticated;
drop trigger if exists rf_audit_project_customer_access_change_trg on public.rf_project_customer_access;
create trigger rf_audit_project_customer_access_change_trg
after insert or update or delete on public.rf_project_customer_access
for each row execute function public.rf_audit_project_customer_access_change();

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Project/customer authorization changes now audited',
'Added append-only audit events for project creation/updates, customer-contact creation/updates, and project customer-access/signing-right changes. This strengthens later evidence of who was an authorized project signer and when administrative project data changed.');


-- 20261001151251 regieflow_permission_copy_system_neutral_v1

update public.rf_permission_catalog
set description_de='Rapportnummer erfassen und Regien endgültig abschliessen.'
where key='regies.close';

update public.rf_permission_catalog
set description_de='PDFs für ERP-, Rapport- und Abrechnungssysteme herunterladen oder exportieren.'
where key='documents.export';

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Permission descriptions made system-neutral',
'Removed the remaining Messerli-specific wording from role/permission descriptions. Rapport closeout and document export are described generically for ERP, rapport and billing systems.');


-- 20261001151431 regieflow_project_update_rpc_v1

create or replace function public.rf_update_project(
  p_project_id uuid,
  p_project_number text,
  p_name text,
  p_address text,
  p_client_name text,
  p_approval_workflow text,
  p_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project public.rf_projects%rowtype;
begin
  select * into v_project
  from public.rf_projects
  where id=p_project_id
  for update;

  if not found then raise exception 'Project not found'; end if;
  if not public.rf_has_permission(v_project.company_id,'projects.manage') then
    raise exception 'Not allowed';
  end if;

  if p_project_number is null or btrim(p_project_number)='' then
    raise exception 'Project number required';
  end if;
  if p_name is null or btrim(p_name)='' then
    raise exception 'Project name required';
  end if;
  if p_approval_workflow not in ('office_then_customer','parallel_office_customer') then
    raise exception 'Invalid approval workflow';
  end if;

  update public.rf_projects
  set project_number=btrim(p_project_number),
      name=btrim(p_name),
      address=nullif(btrim(coalesce(p_address,'')),''),
      client_name=nullif(btrim(coalesce(p_client_name,'')),''),
      approval_workflow=p_approval_workflow,
      active=coalesce(p_active,true),
      updated_at=now()
  where id=p_project_id;

  return true;
end
$$;

revoke all on function public.rf_update_project(uuid,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.rf_update_project(uuid,text,text,text,text,text,boolean) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Project editing RPC added',
'Added controlled project editing for project number, name, address, client/Bauherr, approval flow and active status. The RPC requires projects.manage and leaves company/ownership identity immutable. Existing project audit trigger records changes.');


-- 20261001215940 regieflow_stripe_checkout_fields_v1

alter table regieflow_private.signup_intents
  add column if not exists stripe_checkout_url text;

alter table public.rf_plan_catalog
  add column if not exists stripe_extra_price_id text;

alter table public.rf_company_billing
  add column if not exists stripe_extra_price_id text,
  add column if not exists stripe_extra_subscription_item_id text;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Stripe checkout and extra-seat fields prepared',
'Added private checkout URL storage for resumable paid onboarding plus Stripe extra-seat Price/item identifiers for later automatic billing of internal profiles above the plan allowance.');


-- 20261001151539 regieflow_active_signer_link_guard_v1

create or replace function public.rf_create_public_approval_link(
  p_version_id uuid,
  p_customer_contact_id uuid,
  p_valid_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_version public.rf_regie_versions%rowtype;
  v_token text;
begin
  if p_valid_hours < 1 or p_valid_hours > 720 then
    raise exception 'Link validity must be between 1 and 720 hours';
  end if;

  select * into v_version
  from public.rf_regie_versions
  where id=p_version_id;

  if not found then raise exception 'Version not found'; end if;

  select * into v_regie
  from public.rf_regies
  where id=v_version.regie_id;

  if not found then raise exception 'Regie not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;
  if v_regie.status <> 'awaiting_customer' then
    raise exception 'Regie is not awaiting customer approval';
  end if;
  if v_version.version_no <> v_regie.current_version_no or v_version.locked_at is null then
    raise exception 'Only the current submitted version can be shared for approval';
  end if;
  if not exists (
    select 1
    from public.rf_project_customer_access a
    join public.rf_customer_contacts c on c.id=a.customer_contact_id
    where a.project_id=v_regie.project_id
      and a.customer_contact_id=p_customer_contact_id
      and a.can_sign
      and c.active
      and c.company_id=v_regie.company_id
  ) then
    raise exception 'Customer is not an active authorized signer for this project';
  end if;

  v_token := encode(gen_random_bytes(32),'hex');

  update public.rf_public_approval_links
  set revoked_at=coalesce(revoked_at,now())
  where version_id=p_version_id
    and customer_contact_id=p_customer_contact_id
    and used_at is null
    and revoked_at is null;

  insert into public.rf_public_approval_links(
    company_id,version_id,customer_contact_id,token_hash,expires_at,created_by_user_id
  )
  values(
    v_regie.company_id,p_version_id,p_customer_contact_id,
    encode(digest(v_token,'sha256'),'hex'),
    now()+make_interval(hours=>p_valid_hours),
    auth.uid()
  );

  insert into public.rf_audit_log(company_id,project_id,regie_id,actor_user_id,event_type,metadata)
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
    'public_approval_link_created',
    jsonb_build_object('version_id',p_version_id,'version_no',v_version.version_no,'valid_hours',p_valid_hours,'customer_contact_id',p_customer_contact_id)
  );

  return v_token;
end
$$;

revoke all on function public.rf_create_public_approval_link(uuid,uuid,integer) from public,anon;
grant execute on function public.rf_create_public_approval_link(uuid,uuid,integer) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Secure links require active authorized signer',
'Secure approval-link creation now requires the target customer contact to still be active, belong to the same company and hold can_sign for the project. This prevents creating new approval links for deactivated contacts.');


-- 20261001151606 regieflow_unique_customer_account_per_company_v1

create unique index if not exists rf_customer_contacts_company_auth_unique
on public.rf_customer_contacts(company_id,auth_user_id)
where auth_user_id is not null;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','One customer identity per company account enforced',
'Added a partial unique index on (company_id, auth_user_id) for customer contacts. A single login can no longer be linked to multiple customer-contact identities inside the same contractor company, removing ambiguity in customer RLS helpers, uploads, comments and signing identity.');


-- 20261001151652 regieflow_signature_storage_internal_only_v1

drop policy if exists rf_private_select on storage.objects;
create policy rf_private_select
on storage.objects for select to authenticated
using (
  bucket_id='rf-private'
  and exists (
    select 1
    from public.rf_regies r
    where r.company_id=public.rf_storage_segment_uuid(objects.name,1)
      and r.id=public.rf_storage_segment_uuid(objects.name,2)
      and (
        (
          split_part(objects.name,'/',3)='signatures'
          and public.rf_has_permission(r.company_id,'documents.view')
        )
        or
        (
          split_part(objects.name,'/',3)='documents'
          and (
            public.rf_has_permission(r.company_id,'documents.view')
            or public.rf_customer_has_project(r.project_id)
          )
        )
        or
        (
          split_part(objects.name,'/',3) not in ('documents','signatures')
          and (
            public.rf_has_permission(r.company_id,'regies.view')
            or public.rf_customer_has_project(r.project_id)
          )
        )
      )
  )
);

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Raw signature images hidden from customers',
'Storage RLS now treats signatures separately from final PDFs. Customers assigned to a project can open their final PDFs and work photos, but raw signature image files are available only to internal users with documents.view. This aligns Storage with the earlier customer_signatures table restriction.');


-- 20261001151804 regieflow_drop_duplicate_customer_auth_index_v1

drop index if exists public.rf_customer_contacts_company_auth_unique;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Duplicate customer identity index removed',
'Performance advisor found the newly added customer account uniqueness index duplicated an existing partial unique index. Removed the duplicate and retained the pre-existing uniqueness protection.');


-- 20261001151844 regieflow_company_legal_fields_client_update_v1

grant update(legal_name,address) on public.rf_companies to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Contractor legal identity fields enabled in settings',
'Existing rf_companies legal_name and address fields are now writable through the same company.manage RLS boundary. These fields are available for branded/legal document identity without conflating the display/brand name.');


-- 20261001152255 regieflow_customer_invite_single_active_v1

create or replace function public.rf_create_customer_invite(
  p_customer_contact_id uuid,
  p_valid_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_contact public.rf_customer_contacts%rowtype;
  v_token text;
begin
  if p_valid_hours < 1 or p_valid_hours > 720 then
    raise exception 'Invite validity must be between 1 and 720 hours';
  end if;

  select * into v_contact
  from public.rf_customer_contacts
  where id=p_customer_contact_id and active;

  if not found then raise exception 'Customer contact not found'; end if;

  if not (
    public.rf_has_permission(v_contact.company_id,'projects.manage')
    or public.rf_has_permission(v_contact.company_id,'users.manage')
  ) then
    raise exception 'Not allowed';
  end if;

  if v_contact.auth_user_id is not null then
    raise exception 'Customer already has an account';
  end if;

  update public.rf_customer_invites
  set revoked_at=coalesce(revoked_at,now())
  where customer_contact_id=p_customer_contact_id
    and used_at is null
    and revoked_at is null;

  v_token := encode(gen_random_bytes(32),'hex');

  insert into public.rf_customer_invites(
    company_id,customer_contact_id,token_hash,expires_at,created_by_user_id
  )
  values(
    v_contact.company_id,p_customer_contact_id,
    encode(digest(v_token,'sha256'),'hex'),
    now()+make_interval(hours=>p_valid_hours),
    auth.uid()
  );

  insert into public.rf_audit_log(
    company_id,actor_user_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_contact.company_id,auth.uid(),p_customer_contact_id,
    'customer_invite_created',
    jsonb_build_object('valid_hours',p_valid_hours)
  );

  return v_token;
end
$$;

revoke all on function public.rf_create_customer_invite(uuid,integer) from public,anon;
grant execute on function public.rf_create_customer_invite(uuid,integer) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Customer invitations reduced to one active token',
'Creating a new customer-account invitation now revokes prior unused invitations for that contact and writes an audit event. This reduces stale invitation exposure while preserving one-time hashed-token onboarding.');


-- 20261001220257 regieflow_seat_billing_dispatch_v2

create table if not exists regieflow_private.billing_config (
  singleton boolean primary key default true check (singleton),
  hook_secret text not null,
  updated_at timestamptz not null default now()
);

revoke all on regieflow_private.billing_config from public,anon,authenticated;

insert into regieflow_private.billing_config(singleton,hook_secret)
values(true,encode(gen_random_bytes(32),'hex'))
on conflict (singleton) do nothing;

create or replace function public.rf_billing_get_config()
returns jsonb
language sql
security definer
set search_path=regieflow_private,public
as $$
  select jsonb_build_object('hook_secret',hook_secret)
  from regieflow_private.billing_config
  where singleton=true;
$$;

revoke all on function public.rf_billing_get_config() from public,anon,authenticated;
grant execute on function public.rf_billing_get_config() to service_role;

create or replace function regieflow_private.dispatch_seat_billing_sync()
returns trigger
language plpgsql
security definer
set search_path=public,regieflow_private,net
as $$
declare
  v_company uuid;
  v_plan text;
  v_secret text;
begin
  if tg_op='UPDATE' and old.active is not distinct from new.active then
    return new;
  end if;

  if tg_op='DELETE' then
    v_company := old.company_id;
  else
    v_company := new.company_id;
  end if;

  select plan into v_plan
  from public.rf_company_billing
  where company_id=v_company;

  if v_plan is null or v_plan='development' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  select hook_secret into v_secret
  from regieflow_private.billing_config
  where singleton=true;

  perform net.http_post(
    url := 'https://kiihabzzepoehsokglzq.supabase.co/functions/v1/rf-sync-seat-billing',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-regieflow-billing-hook',v_secret
    ),
    body := jsonb_build_object('companyId',v_company)
  );

  if tg_op='DELETE' then return old; else return new; end if;
end
$$;

revoke all on function regieflow_private.dispatch_seat_billing_sync() from public,anon,authenticated;

drop trigger if exists rf_memberships_seat_billing_sync on public.rf_memberships;
create trigger rf_memberships_seat_billing_sync
after insert or delete or update of active
on public.rf_memberships
for each row execute function regieflow_private.dispatch_seat_billing_sync();

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Automatic seat-billing dispatch prepared',
'Paid-plan membership insert/delete/activation changes now enqueue a private authenticated Edge call to synchronize extra internal-profile quantities with Stripe. Development-plan companies are skipped. The billing hook uses a dedicated private random secret separate from Push.');


-- 20261001152315 regieflow_revoke_approval_links_v1

create or replace function public.rf_revoke_public_approval_links(
  p_version_id uuid,
  p_customer_contact_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_count integer;
begin
  select r.* into v_regie
  from public.rf_regies r
  join public.rf_regie_versions v on v.regie_id=r.id
  where v.id=p_version_id;

  if not found then raise exception 'Version not found'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;

  update public.rf_public_approval_links
  set revoked_at=now()
  where version_id=p_version_id
    and used_at is null
    and revoked_at is null
    and (p_customer_contact_id is null or customer_contact_id=p_customer_contact_id);

  get diagnostics v_count = row_count;

  if v_count>0 then
    insert into public.rf_audit_log(
      company_id,project_id,regie_id,actor_user_id,event_type,metadata
    )
    values(
      v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
      'public_approval_links_revoked',
      jsonb_build_object('version_id',p_version_id,'customer_contact_id',p_customer_contact_id,'count',v_count)
    );
  end if;

  return v_count;
end
$$;

revoke all on function public.rf_revoke_public_approval_links(uuid,uuid) from public,anon;
grant execute on function public.rf_revoke_public_approval_links(uuid,uuid) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Manual secure-link revocation added',
'Added an audited RPC to revoke unused secure approval links for a Regie version, optionally for one signer. This provides an immediate recovery path if a link was sent to the wrong person or should no longer remain valid.');


-- 20261001154207 regieflow_stripe_billing_scaffold_v1

alter table public.rf_plan_catalog
  add column if not exists stripe_price_id text;

alter table public.rf_company_billing
  add column if not exists stripe_price_id text,
  add column if not exists billing_email text,
  add column if not exists current_period_end timestamptz,
  add column if not exists cancel_at_period_end boolean not null default false,
  add column if not exists last_provider_event_id text;

create unique index if not exists rf_company_billing_stripe_customer_uidx
  on public.rf_company_billing(stripe_customer_id)
  where stripe_customer_id is not null;

create unique index if not exists rf_company_billing_stripe_subscription_uidx
  on public.rf_company_billing(stripe_subscription_id)
  where stripe_subscription_id is not null;

create table if not exists regieflow_private.billing_events (
  provider_event_id text primary key,
  event_type text not null,
  company_id uuid null references public.rf_companies(id) on delete set null,
  received_at timestamptz not null default now(),
  applied_at timestamptz null,
  payload_sha256 text null
);

revoke all on regieflow_private.billing_events from public,anon,authenticated;

create or replace function public.rf_apply_subscription_state(
  p_company_id uuid,
  p_plan text,
  p_stripe_customer_id text,
  p_stripe_subscription_id text,
  p_stripe_price_id text,
  p_subscription_status text,
  p_current_period_end timestamptz,
  p_cancel_at_period_end boolean,
  p_provider_event_id text,
  p_billing_email text default null
)
returns boolean
language plpgsql
security definer
set search_path=public,regieflow_private
as $$
declare
  v_plan public.rf_plan_catalog%rowtype;
begin
  if p_plan not in ('starter','team','business') then
    raise exception 'Unknown plan';
  end if;

  select * into v_plan
  from public.rf_plan_catalog
  where plan=p_plan and active;

  if not found then raise exception 'Plan not active'; end if;

  if p_provider_event_id is null or btrim(p_provider_event_id)='' then
    raise exception 'Provider event id required';
  end if;

  if exists (
    select 1 from regieflow_private.billing_events
    where provider_event_id=p_provider_event_id and applied_at is not null
  ) then
    return true;
  end if;

  insert into regieflow_private.billing_events(provider_event_id,event_type,company_id)
  values(p_provider_event_id,coalesce(p_subscription_status,'unknown'),p_company_id)
  on conflict (provider_event_id) do nothing;

  insert into public.rf_company_billing(
    company_id,plan,included_internal_profiles,additional_profile_price_chf,
    stripe_customer_id,stripe_subscription_id,stripe_price_id,subscription_status,
    billing_email,current_period_end,cancel_at_period_end,last_provider_event_id
  )
  values(
    p_company_id,p_plan,v_plan.included_internal_profiles,v_plan.extra_profile_price_chf,
    p_stripe_customer_id,p_stripe_subscription_id,p_stripe_price_id,p_subscription_status,
    p_billing_email,p_current_period_end,coalesce(p_cancel_at_period_end,false),p_provider_event_id
  )
  on conflict (company_id) do update set
    plan=excluded.plan,
    included_internal_profiles=excluded.included_internal_profiles,
    additional_profile_price_chf=excluded.additional_profile_price_chf,
    stripe_customer_id=excluded.stripe_customer_id,
    stripe_subscription_id=excluded.stripe_subscription_id,
    stripe_price_id=excluded.stripe_price_id,
    subscription_status=excluded.subscription_status,
    billing_email=coalesce(excluded.billing_email,public.rf_company_billing.billing_email),
    current_period_end=excluded.current_period_end,
    cancel_at_period_end=excluded.cancel_at_period_end,
    last_provider_event_id=excluded.last_provider_event_id,
    updated_at=now();

  update regieflow_private.billing_events
  set applied_at=now(),company_id=p_company_id
  where provider_event_id=p_provider_event_id;

  insert into public.rf_audit_log(company_id,event_type,metadata)
  values(
    p_company_id,
    'billing_subscription_updated',
    jsonb_build_object(
      'plan',p_plan,
      'subscription_status',p_subscription_status,
      'provider_event_id',p_provider_event_id,
      'current_period_end',p_current_period_end,
      'cancel_at_period_end',coalesce(p_cancel_at_period_end,false)
    )
  );

  return true;
end
$$;

revoke all on function public.rf_apply_subscription_state(
  uuid,text,text,text,text,text,timestamptz,boolean,text,text
) from public,anon,authenticated;
grant execute on function public.rf_apply_subscription_state(
  uuid,text,text,text,text,text,timestamptz,boolean,text,text
) to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Stripe billing backend scaffold prepared',
'Prepared Stripe-ready billing schema without enabling payments yet: plan catalog can hold Stripe Price IDs; company billing stores Stripe customer/subscription/price IDs, billing email, period end and cancel-at-period-end. Added private idempotent billing event ledger plus service-only rf_apply_subscription_state to apply verified provider webhook events. No Stripe secret or live payment endpoint has been added yet.');


-- 20261001154224 regieflow_single_final_approval_evidence_v1

create unique index if not exists rf_customer_signature_approved_version_uidx
  on public.rf_customer_signatures(version_id)
  where decision='approved';

create unique index if not exists rf_signed_document_version_uidx
  on public.rf_documents(version_id)
  where document_type='signed_regie_pdf';

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Single final approval evidence enforced',
'Added database-level uniqueness guarantees so one Regie version can have at most one approved customer signature record and one signed Regie PDF. The workflow row lock already prevents normal double approval; these indexes add a final integrity barrier against concurrency or future code regressions.');


-- 20261001154258 regieflow_private_launch_checklist_v1

create table if not exists regieflow_private.launch_checklist (
  key text primary key,
  category text not null,
  title text not null,
  status text not null check (status in ('todo','in_progress','blocked','passed','not_required')),
  blocker text null,
  evidence text null,
  updated_at timestamptz not null default now()
);

revoke all on regieflow_private.launch_checklist from public,anon,authenticated;

insert into regieflow_private.launch_checklist(key,category,title,status,blocker,evidence) values
('core_internal_regie','core','Interne Regie: Entwurf bis Kundenfreigabe','passed',null,'Live E2E RF-2026-A06A7939 inkl. Revision, Pflichtbild, secure link, Signatur und PDF.'),
('core_closeout','core','Ausführung bis Rapportnummer und Archiv','passed',null,'RF-2026-A06A7939: work_started → work_completed → TEST-RAPPORT-001 → closed.'),
('customer_account','customer','Kostenloses Kundenkonto','passed',null,'Echte Einladung angenommen; Kunde erhielt nur customer context.'),
('customer_request','customer','Kunde erstellt Auftrag','passed',null,'RF-2026-5BC80278 erfolgreich vom Kunden angelegt und im Büro übernommen.'),
('customer_request_photo','customer','Übernommene Kundenanfrage mit Pflicht-Vorherbild absenden','blocked','Benötigt ein echtes Browser-/Datei-Upload-Ereignis für den positiven Upload-Test.','Negativtest ohne Vorherbild wurde korrekt blockiert.'),
('push_delivery','notifications','Browser Push echte Zustellung','blocked','Benötigt Browser-Push-Berechtigung und echte Subscription.','VAPID public endpoint und Hook-Autorisierung negativ getestet.'),
('roles_permissions','security','Rollen, Owner-Schutz und granulare Rechte','passed',null,'Controlled membership role/active RPCs, Owner-Schutz, permission-driven UI, audited changes.'),
('rls_privileges','security','RLS und minimale Browser-DB-Rechte','passed',null,'Anon ohne rf_* Grants; authenticated DML auf minimale UI-Spalten/Operationen reduziert; lifecycle state RPC-only.'),
('approval_evidence','security','Unterschrift/PDF/Audit Integrität','passed',null,'Version-bound approval, immutable docs, SHA-256 für Signatur/PDF, consent v1, raw signature intern.'),
('secure_links','security','Secure approval links','passed',null,'Hashed one-time links, expiry/revoke, current-version binding, active signer validation, manual revocation.'),
('csp_headers','security','Frontend Security Headers/CSP','passed',null,'app.js extern; CSP ohne script-src unsafe-inline; no-referrer; frame deny.'),
('billing_scaffold','billing','Stripe-ready Billing-Datenmodell','passed',null,'Stripe IDs/period state/idempotent private billing events + service-only apply function vorbereitet.'),
('stripe_live','billing','Stripe Checkout/Webhook/Portal live','blocked','Stripe-Zugang/Plugin bzw. Stripe API-Konfiguration erforderlich.','Noch keine Live-Zahlung aktiviert.'),
('public_onboarding','onboarding','Öffentliche Firmenregistrierung','todo',null,'Soll an verifizierte Stripe Checkout/Subscription gekoppelt werden; Development-Setup ist retired.'),
('legal_pages','legal','Datenschutz / AGB / Impressum','blocked','Benötigt Betreiber-Rechtsname, Geschäftsadresse und gewünschte Vertrags-/Datenschutzangaben.','Firmen-Legalname/Adresse Felder existieren bereits für Mandanten.'),
('password_breach','security','Leaked password protection','blocked','Supabase Auth-Projekteinstellung muss im Dashboard/API aktiviert werden.','Supabase Security Advisor meldet Schutz derzeit deaktiviert.'),
('backup_recovery','ops','Backup/Recovery Runbook','todo',null,'Code liegt versioniert auf GitHub; Daten-/Storage-Recovery muss noch als Produktionsverfahren definiert werden.')
on conflict (key) do update set
  category=excluded.category,title=excluded.title,status=excluded.status,
  blocker=excluded.blocker,evidence=excluded.evidence,updated_at=now();

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Persistent launch checklist created',
'Created regieflow_private.launch_checklist to track launch blockers and passed milestones independently of chat history. Initial checklist records core E2E, customer account/request, security, push, Stripe, public onboarding, legal and recovery status.');


-- 20261001154359 regieflow_paid_onboarding_scaffold_v1

create table if not exists regieflow_private.signup_intents (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  company_name text not null,
  owner_display_name text not null,
  plan text not null check (plan in ('starter','team','business')),
  auth_user_id uuid null references auth.users(id) on delete set null,
  stripe_checkout_session_id text null unique,
  status text not null default 'pending' check (status in ('pending','checkout_created','paid','provisioned','expired','cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '24 hours'),
  provisioned_company_id uuid null references public.rf_companies(id) on delete set null,
  updated_at timestamptz not null default now()
);

create unique index if not exists rf_signup_intents_open_email_uidx
  on regieflow_private.signup_intents(lower(email))
  where status in ('pending','checkout_created','paid');

revoke all on regieflow_private.signup_intents from public,anon,authenticated;

create or replace function public.rf_provision_paid_company(
  p_signup_intent_id uuid,
  p_provider_event_id text
)
returns uuid
language plpgsql
security definer
set search_path=public,regieflow_private
as $$
declare
  v_intent regieflow_private.signup_intents%rowtype;
  v_plan public.rf_plan_catalog%rowtype;
  v_company uuid;
begin
  select * into v_intent
  from regieflow_private.signup_intents
  where id=p_signup_intent_id
  for update;

  if not found then raise exception 'Signup intent not found'; end if;
  if v_intent.status='provisioned' and v_intent.provisioned_company_id is not null then
    return v_intent.provisioned_company_id;
  end if;
  if v_intent.status <> 'paid' then
    raise exception 'Signup intent is not paid';
  end if;
  if v_intent.auth_user_id is null then
    raise exception 'Signup intent has no auth user';
  end if;

  select * into v_plan
  from public.rf_plan_catalog
  where plan=v_intent.plan and active;

  if not found then raise exception 'Plan not active'; end if;

  insert into public.rf_companies(name,primary_owner_user_id)
  values(btrim(v_intent.company_name),v_intent.auth_user_id)
  returning id into v_company;

  insert into public.rf_memberships(
    company_id,user_id,display_name,active,must_change_password
  )
  values(
    v_company,v_intent.auth_user_id,btrim(v_intent.owner_display_name),true,false
  );

  insert into public.rf_company_billing(
    company_id,plan,included_internal_profiles,additional_profile_price_chf,
    subscription_status,last_provider_event_id
  )
  values(
    v_company,v_plan.plan,v_plan.included_internal_profiles,v_plan.extra_profile_price_chf,
    'active',p_provider_event_id
  );

  update regieflow_private.signup_intents
  set status='provisioned',provisioned_company_id=v_company,updated_at=now()
  where id=v_intent.id;

  insert into public.rf_audit_log(company_id,actor_user_id,event_type,metadata)
  values(
    v_company,v_intent.auth_user_id,'company_provisioned_after_payment',
    jsonb_build_object(
      'signup_intent_id',v_intent.id,
      'plan',v_intent.plan,
      'provider_event_id',p_provider_event_id
    )
  );

  return v_company;
end
$$;

revoke all on function public.rf_provision_paid_company(uuid,text)
  from public,anon,authenticated;
grant execute on function public.rf_provision_paid_company(uuid,text)
  to service_role;

update regieflow_private.launch_checklist
set status='in_progress',
    evidence='Private signup-intent ledger and service-only paid-company provisioning function are prepared. Public registration and Stripe Checkout/Webhook still need wiring.',
    updated_at=now()
where key='public_onboarding';

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Paid company onboarding backend scaffold prepared',
'Added private signup_intents with one-open-intent-per-email protection and a service-role-only rf_provision_paid_company function. Provisioning is idempotent and only succeeds after an intent is marked paid. This prepares the safe post-Stripe path without exposing unpaid company creation publicly.');


-- 20261001154453 regieflow_customer_contact_management_v1

create or replace function public.rf_update_customer_contact(
  p_customer_contact_id uuid,
  p_full_name text,
  p_organization_name text,
  p_email text,
  p_phone text,
  p_active boolean
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_contact public.rf_customer_contacts%rowtype;
begin
  select * into v_contact
  from public.rf_customer_contacts
  where id=p_customer_contact_id
  for update;

  if not found then raise exception 'Customer contact not found'; end if;
  if not public.rf_has_permission(v_contact.company_id,'projects.manage') then
    raise exception 'Not allowed';
  end if;
  if p_full_name is null or btrim(p_full_name)='' then
    raise exception 'Name required';
  end if;

  update public.rf_customer_contacts
  set
    full_name=btrim(p_full_name),
    organization_name=nullif(btrim(coalesce(p_organization_name,'')),''),
    email=nullif(lower(btrim(coalesce(p_email,''))),''),
    phone=nullif(btrim(coalesce(p_phone,'')),''),
    active=coalesce(p_active,true),
    updated_at=now()
  where id=p_customer_contact_id;

  if coalesce(p_active,true)=false then
    update public.rf_public_approval_links
    set revoked_at=coalesce(revoked_at,now())
    where customer_contact_id=p_customer_contact_id
      and used_at is null
      and revoked_at is null;

    update public.rf_customer_invites
    set revoked_at=coalesce(revoked_at,now())
    where customer_contact_id=p_customer_contact_id
      and used_at is null
      and revoked_at is null;
  end if;

  insert into public.rf_audit_log(
    company_id,actor_user_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_contact.company_id,auth.uid(),p_customer_contact_id,
    case when coalesce(p_active,true) then 'customer_contact_updated' else 'customer_contact_deactivated' end,
    jsonb_build_object(
      'full_name',btrim(p_full_name),
      'organization_name',nullif(btrim(coalesce(p_organization_name,'')),''),
      'active',coalesce(p_active,true)
    )
  );

  return true;
end
$$;

revoke all on function public.rf_update_customer_contact(uuid,text,text,text,text,boolean)
  from public,anon;
grant execute on function public.rf_update_customer_contact(uuid,text,text,text,text,boolean)
  to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Controlled customer contact management added',
'Added rf_update_customer_contact for editing/deactivating customer contacts under projects.manage. Deactivation automatically revokes outstanding secure approval links and unused customer-account invitations while preserving historical project access and audit evidence.');


-- 20261001215904 regieflow_paid_onboarding_state_v2

alter table regieflow_private.signup_intents
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text,
  add column if not exists stripe_price_id text,
  add column if not exists paid_at timestamptz,
  add column if not exists completion_token_hash text,
  add column if not exists completion_expires_at timestamptz;

create unique index if not exists rf_signup_intents_checkout_uidx
  on regieflow_private.signup_intents(stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

create or replace function public.rf_provision_paid_company(
  p_signup_intent_id uuid,
  p_provider_event_id text
)
returns uuid
language plpgsql
security definer
set search_path=public,regieflow_private
as $$
declare
  v_intent regieflow_private.signup_intents%rowtype;
  v_plan public.rf_plan_catalog%rowtype;
  v_company uuid;
begin
  select * into v_intent
  from regieflow_private.signup_intents
  where id=p_signup_intent_id
  for update;

  if not found then raise exception 'Signup intent not found'; end if;
  if v_intent.status='provisioned' and v_intent.provisioned_company_id is not null then
    return v_intent.provisioned_company_id;
  end if;
  if v_intent.status <> 'paid' then
    raise exception 'Signup intent is not paid';
  end if;
  if v_intent.auth_user_id is null then
    raise exception 'Signup intent has no auth user';
  end if;

  select * into v_plan
  from public.rf_plan_catalog
  where plan=v_intent.plan and active;

  if not found then raise exception 'Plan not active'; end if;

  insert into public.rf_companies(name,primary_owner_user_id)
  values(btrim(v_intent.company_name),v_intent.auth_user_id)
  returning id into v_company;

  insert into public.rf_memberships(
    company_id,user_id,display_name,active,must_change_password
  )
  values(
    v_company,v_intent.auth_user_id,btrim(v_intent.owner_display_name),true,false
  );

  insert into public.rf_company_billing(
    company_id,plan,included_internal_profiles,additional_profile_price_chf,
    stripe_customer_id,stripe_subscription_id,stripe_price_id,
    subscription_status,last_provider_event_id,current_period_end,cancel_at_period_end
  )
  values(
    v_company,v_plan.plan,v_plan.included_internal_profiles,v_plan.extra_profile_price_chf,
    v_intent.stripe_customer_id,v_intent.stripe_subscription_id,v_intent.stripe_price_id,
    'active',p_provider_event_id,null,false
  );

  update regieflow_private.signup_intents
  set status='provisioned',
      provisioned_company_id=v_company,
      completion_token_hash=null,
      completion_expires_at=null,
      updated_at=now()
  where id=v_intent.id;

  insert into public.rf_audit_log(company_id,actor_user_id,event_type,metadata)
  values(
    v_company,v_intent.auth_user_id,'company_provisioned_after_payment',
    jsonb_build_object(
      'signup_intent_id',v_intent.id,
      'plan',v_intent.plan,
      'provider_event_id',p_provider_event_id,
      'stripe_customer_id',v_intent.stripe_customer_id,
      'stripe_subscription_id',v_intent.stripe_subscription_id
    )
  );

  return v_company;
end
$$;

revoke all on function public.rf_provision_paid_company(uuid,text)
  from public,anon,authenticated;
grant execute on function public.rf_provision_paid_company(uuid,text)
  to service_role;


-- 20261001220345 regieflow_member_activation_billing_guard_v1

create or replace function public.rf_set_member_active(
  p_membership_id uuid,
  p_active boolean
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_member public.rf_memberships%rowtype;
  v_owner uuid;
  v_billing public.rf_company_billing%rowtype;
  v_plan public.rf_plan_catalog%rowtype;
  v_active_count integer;
begin
  select * into v_member
  from public.rf_memberships
  where id=p_membership_id
  for update;

  if not found then raise exception 'Membership not found'; end if;
  if not public.rf_has_permission(v_member.company_id,'users.manage') then
    raise exception 'Not allowed';
  end if;

  select primary_owner_user_id into v_owner
  from public.rf_companies
  where id=v_member.company_id;

  if v_member.user_id=v_owner and not p_active then
    raise exception 'Primary Owner cannot be deactivated';
  end if;

  if v_member.user_id=auth.uid() and not p_active then
    raise exception 'You cannot deactivate your own account';
  end if;

  if p_active and not v_member.active then
    select * into v_billing
    from public.rf_company_billing
    where company_id=v_member.company_id;

    if found and v_billing.plan <> 'development' then
      if coalesce(v_billing.subscription_status,'') not in ('active','trialing') then
        raise exception 'Subscription is not active';
      end if;

      select * into v_plan
      from public.rf_plan_catalog
      where plan=v_billing.plan and active;

      if not found then raise exception 'Plan not active'; end if;

      select count(*)::integer into v_active_count
      from public.rf_memberships
      where company_id=v_member.company_id and active;

      if v_active_count + 1 > v_plan.included_internal_profiles
         and v_plan.stripe_extra_price_id is null then
        raise exception 'Extra-seat billing is not configured';
      end if;
    end if;
  end if;

  update public.rf_memberships
  set active=p_active,updated_at=now()
  where id=p_membership_id;

  insert into public.rf_audit_log(company_id,actor_user_id,event_type,metadata)
  values(
    v_member.company_id,auth.uid(),
    case when p_active then 'membership_activated' else 'membership_deactivated' end,
    jsonb_build_object('membership_id',p_membership_id,'user_id',v_member.user_id)
  );

  return true;
end
$$;

revoke all on function public.rf_set_member_active(uuid,boolean) from public,anon;
grant execute on function public.rf_set_member_active(uuid,boolean) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Paid seat activation billing guard added',
'Activating an internal profile on a paid plan now requires an active/trialing subscription. If the activation exceeds the included profile allowance, the plan must have a Stripe extra-seat Price configured. Development plans remain unrestricted.');


-- 20261001220640 regieflow_legal_publication_gate_v1

create table if not exists regieflow_private.legal_config (
  singleton boolean primary key default true check (singleton),
  operator_legal_name text,
  operator_address text,
  operator_email text,
  imprint_text text,
  privacy_text text,
  terms_text text,
  published boolean not null default false,
  updated_at timestamptz not null default now()
);

revoke all on regieflow_private.legal_config from public,anon,authenticated;

insert into regieflow_private.legal_config(singleton,published)
values(true,false)
on conflict (singleton) do nothing;

create or replace function public.rf_public_legal()
returns jsonb
language sql
security definer
set search_path=regieflow_private,public
as $$
  select case when published then jsonb_build_object(
    'published',true,
    'operatorLegalName',operator_legal_name,
    'operatorAddress',operator_address,
    'operatorEmail',operator_email,
    'imprint',imprint_text,
    'privacy',privacy_text,
    'terms',terms_text,
    'updatedAt',updated_at
  ) else jsonb_build_object('published',false) end
  from regieflow_private.legal_config
  where singleton=true;
$$;

revoke all on function public.rf_public_legal() from public;
grant execute on function public.rf_public_legal() to anon,authenticated,service_role;

update regieflow_private.launch_checklist
set evidence='Legal content storage and public publication gate are built. Paid checkout will be blocked until legal content is published.',
    updated_at=now()
where key='legal_pages';

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Legal publication gate prepared',
'Created private legal configuration for operator identity, imprint, privacy and terms. Public clients can only read it after published=true. Paid onboarding can now be gated so no public purchase is accepted before legal pages are configured.');


-- 20261001220729 regieflow_signup_legal_consent_v1

alter table regieflow_private.signup_intents
  add column if not exists legal_accepted_at timestamptz,
  add column if not exists legal_version_hash text;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Paid signup legal-consent evidence fields added',
'Paid onboarding intents now have fields for legal acceptance timestamp and a hash of the published terms/privacy version, allowing the company-creation audit trail to preserve what legal version was accepted.');


-- 20261001220904 regieflow_subscription_read_only_gate_v1

create or replace function public.rf_company_write_enabled(p_company uuid)
returns boolean
language sql
security definer
stable
set search_path=public
as $$
  select case
    when b.company_id is null then true
    when b.plan='development' then true
    when b.subscription_status in ('active','trialing','past_due') then true
    else false
  end
  from (select p_company as company_id) x
  left join public.rf_company_billing b on b.company_id=x.company_id;
$$;

revoke all on function public.rf_company_write_enabled(uuid) from public,anon,authenticated;

create or replace function public.rf_has_permission(p_company uuid,p_permission text)
returns boolean
language plpgsql
security definer
stable
set search_path=public
as $$
declare
  v_override jsonb;
  v_permissions text[];
begin
  if p_permission not in (
    'projects.view',
    'regies.view',
    'documents.view',
    'documents.export',
    'company.manage',
    'billing.manage'
  ) and not public.rf_company_write_enabled(p_company) then
    return false;
  end if;

  if exists (
    select 1
    from public.rf_companies c
    where c.id=p_company and c.primary_owner_user_id=auth.uid()
  ) then
    return true;
  end if;

  select m.permission_overrides,coalesce(r.permissions,'{}'::text[])
  into v_override,v_permissions
  from public.rf_memberships m
  left join public.rf_roles r on r.id=m.role_id
  where m.company_id=p_company
    and m.user_id=auth.uid()
    and m.active
  limit 1;

  if not found then return false; end if;
  if v_override ? p_permission then
    return coalesce((v_override->>p_permission)::boolean,false);
  end if;
  return p_permission=any(v_permissions);
end
$$;

revoke all on function public.rf_has_permission(uuid,text) from public,anon;
grant execute on function public.rf_has_permission(uuid,text) to authenticated,service_role;

create or replace function public.rf_create_customer_request(
  p_project_id uuid,
  p_description text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid;
  v_contact uuid;
  v_company uuid;
  v_regie uuid;
begin
  v_uid:=auth.uid();
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_description is null or char_length(btrim(p_description))<1 then
    raise exception 'Description required';
  end if;

  select p.company_id,c.id
  into v_company,v_contact
  from public.rf_projects p
  join public.rf_project_customer_access a on a.project_id=p.id
  join public.rf_customer_contacts c on c.id=a.customer_contact_id
  where p.id=p_project_id
    and p.active
    and c.auth_user_id=v_uid
    and c.active
  limit 1;

  if v_company is null or v_contact is null then
    raise exception 'Project not available to this customer';
  end if;
  if not public.rf_company_write_enabled(v_company) then
    raise exception 'Company subscription is read-only';
  end if;

  insert into public.rf_regies(
    company_id,project_id,source,status,requested_by_customer_contact_id,
    request_description,request_created_at
  )
  values(
    v_company,p_project_id,'customer','customer_request',v_contact,
    btrim(p_description),now()
  )
  returning id into v_regie;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_company,p_project_id,v_regie,v_contact,'customer_request_created',
    jsonb_build_object('description',btrim(p_description))
  );

  return v_regie;
end
$$;

revoke all on function public.rf_create_customer_request(uuid,text) from public,anon;
grant execute on function public.rf_create_customer_request(uuid,text) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Inactive paid subscriptions become read-only',
'Paid companies with inactive/cancelled/unpaid subscription states now retain read/export/company/billing access but operational write permissions are denied. Development and active/trialing/past_due subscriptions remain writable. Customer-created requests are also blocked when the contractor is read-only, preserving archive access without allowing new unpaid work.');


-- 20261001220917 regieflow_comment_subscription_gate_v1

create or replace function public.rf_add_regie_comment(
  p_regie_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_contact uuid;
  v_id uuid;
  v_internal boolean:=false;
begin
  if p_body is null or char_length(btrim(p_body))<1 then
    raise exception 'Kommentar darf nicht leer sein';
  end if;
  if char_length(btrim(p_body))>4000 then
    raise exception 'Kommentar ist zu lang';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status in ('closed','rejected') then
    raise exception 'Archivierte Regien sind schreibgeschützt';
  end if;
  if not public.rf_company_write_enabled(v_regie.company_id) then
    raise exception 'Company subscription is read-only';
  end if;

  if public.rf_is_internal_member(v_regie.company_id)
     and public.rf_has_permission(v_regie.company_id,'regies.view') then
    v_internal:=true;
    insert into public.rf_regie_comments(regie_id,actor_user_id,body)
    values(p_regie_id,auth.uid(),btrim(p_body))
    returning id into v_id;
  else
    select c.id into v_contact
    from public.rf_project_customer_access a
    join public.rf_customer_contacts c on c.id=a.customer_contact_id
    where a.project_id=v_regie.project_id
      and c.auth_user_id=auth.uid()
      and c.active
    limit 1;

    if v_contact is null then raise exception 'Not allowed'; end if;

    insert into public.rf_regie_comments(regie_id,actor_customer_contact_id,body)
    values(p_regie_id,v_contact,btrim(p_body))
    returning id into v_id;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,actor_customer_contact_id,event_type,metadata
  )
  values(
    v_regie.company_id,
    v_regie.project_id,
    v_regie.id,
    case when v_internal then auth.uid() else null end,
    v_contact,
    'regie_comment_added',
    jsonb_build_object('comment_id',v_id)
  );

  if v_internal then
    insert into public.rf_notifications(
      company_id,recipient_customer_contact_id,regie_id,type,title,body
    )
    select
      v_regie.company_id,
      a.customer_contact_id,
      v_regie.id,
      'regie_comment',
      'Neue Notiz · '||coalesce(v_regie.regie_code,'Regie'),
      left(btrim(p_body),240)
    from public.rf_project_customer_access a
    where a.project_id=v_regie.project_id;
  else
    insert into public.rf_notifications(
      company_id,recipient_user_id,regie_id,type,title,body
    )
    select
      v_regie.company_id,
      x.user_id,
      v_regie.id,
      'regie_comment',
      'Neue Kundennotiz · '||coalesce(v_regie.regie_code,'Regie'),
      left(btrim(p_body),240)
    from (
      select c.primary_owner_user_id as user_id
      from public.rf_companies c
      where c.id=v_regie.company_id
      union
      select v_regie.assigned_monteur_user_id
    ) x
    where x.user_id is not null;
  end if;

  return v_id;
end
$$;

revoke all on function public.rf_add_regie_comment(uuid,text) from public,anon;
grant execute on function public.rf_add_regie_comment(uuid,text) to authenticated;


-- 20261001220932 regieflow_public_rate_limits_v1

create table if not exists regieflow_private.rate_limit_buckets (
  scope text not null,
  key_hash text not null,
  window_start timestamptz not null,
  count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key(scope,key_hash,window_start)
);

revoke all on regieflow_private.rate_limit_buckets from public,anon,authenticated;

create or replace function public.rf_take_rate_limit(
  p_scope text,
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
declare
  v_window timestamptz;
  v_count integer;
begin
  if p_scope is null or p_key_hash is null
     or p_limit<1 or p_window_seconds<1 then
    return false;
  end if;

  v_window:=to_timestamp(
    floor(extract(epoch from now())/p_window_seconds)*p_window_seconds
  );

  insert into regieflow_private.rate_limit_buckets(
    scope,key_hash,window_start,count,updated_at
  )
  values(p_scope,p_key_hash,v_window,1,now())
  on conflict(scope,key_hash,window_start)
  do update set
    count=regieflow_private.rate_limit_buckets.count+1,
    updated_at=now()
  returning count into v_count;

  delete from regieflow_private.rate_limit_buckets
  where window_start < now()-interval '2 days';

  return v_count<=p_limit;
end
$$;

revoke all on function public.rf_take_rate_limit(text,text,integer,integer)
  from public,anon,authenticated;
grant execute on function public.rf_take_rate_limit(text,text,integer,integer)
  to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Private fixed-window rate limiter prepared',
'Added a private service-only rate-limit bucket and atomic rf_take_rate_limit helper for anonymous/public Edge endpoints. No client role can read or mutate the limiter state.');


-- 20261001221111 regieflow_context_subscription_state_v1

create or replace function public.rf_my_context()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
with uid as (
  select auth.uid() as id
),
internal_access as (
  select
    c.id as company_id,
    c.name as company_name,
    m.display_name,
    (c.primary_owner_user_id=(select id from uid)) as is_primary_owner,
    r.name as role_name,
    coalesce(r.permissions,'{}'::text[]) as role_permissions,
    coalesce(m.permission_overrides,'{}'::jsonb) as permission_overrides,
    m.must_change_password,
    coalesce(b.plan,'development') as plan,
    coalesce(b.subscription_status,'development') as subscription_status,
    public.rf_company_write_enabled(c.id) as write_enabled
  from public.rf_companies c
  join public.rf_memberships m
    on m.company_id=c.id
   and m.user_id=(select id from uid)
   and m.active
  left join public.rf_roles r on r.id=m.role_id
  left join public.rf_company_billing b on b.company_id=c.id
),
customer_access as (
  select
    c.id as company_id,
    c.name as company_name,
    cc.id as customer_contact_id,
    cc.full_name,
    cc.organization_name,
    (
      select count(*)::integer
      from public.rf_project_customer_access a
      where a.customer_contact_id=cc.id
    ) as project_count,
    public.rf_company_write_enabled(c.id) as write_enabled
  from public.rf_customer_contacts cc
  join public.rf_companies c on c.id=cc.company_id
  where cc.auth_user_id=(select id from uid)
    and cc.active
)
select jsonb_build_object(
  'internal',coalesce((
    select jsonb_agg(jsonb_build_object(
      'companyId',company_id,
      'companyName',company_name,
      'displayName',display_name,
      'isPrimaryOwner',is_primary_owner,
      'roleName',role_name,
      'rolePermissions',role_permissions,
      'permissionOverrides',permission_overrides,
      'mustChangePassword',must_change_password,
      'plan',plan,
      'subscriptionStatus',subscription_status,
      'writeEnabled',write_enabled
    ) order by company_name)
    from internal_access
  ),'[]'::jsonb),
  'customer',coalesce((
    select jsonb_agg(jsonb_build_object(
      'companyId',company_id,
      'companyName',company_name,
      'customerContactId',customer_contact_id,
      'fullName',full_name,
      'organizationName',organization_name,
      'projectCount',project_count,
      'writeEnabled',write_enabled
    ) order by company_name)
    from customer_access
  ),'[]'::jsonb)
);
$$;

revoke all on function public.rf_my_context() from public,anon;
grant execute on function public.rf_my_context() to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Subscription write-state exposed to UI context',
'rf_my_context now includes plan, subscriptionStatus and writeEnabled for internal users and writeEnabled for customer accounts. This lets the frontend enter a clear read-only state instead of showing operational buttons that the backend will reject after a paid subscription becomes inactive.');


-- 20261001221315 regieflow_remove_non_enforceable_export_permission_v1

update public.rf_roles
set permissions=array_remove(permissions,'documents.export')
where 'documents.export'=any(coalesce(permissions,'{}'::text[]));

update public.rf_memberships
set permission_overrides=permission_overrides-'documents.export'
where permission_overrides ? 'documents.export';

delete from public.rf_permission_catalog
where key='documents.export';

insert into regieflow_private.dev_log(kind,title,content) values
('decision','Removed misleading separate document-export permission',
'Browser PDF viewing inherently allows saving/downloading, so a separate documents.export permission could not be honestly enforced independently from documents.view. Removed the unused permission from catalog, roles and overrides rather than exposing a control that did not provide real isolation.');


-- 20261001221501 regieflow_legal_rpc_service_only_v1

revoke all on function public.rf_public_legal() from public,anon,authenticated;
grant execute on function public.rf_public_legal() to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Public legal content moved behind Edge endpoint',
'Anonymous clients no longer execute the SECURITY DEFINER legal RPC directly. The public rf-public-legal Edge Function reads the private legal configuration with service role and exposes only the explicitly published payload.');


-- 20261001221656 regieflow_integrity_selfcheck_v1

create or replace function public.rf_system_integrity_check()
returns jsonb
language sql
security definer
stable
set search_path=public
as $$
with checks as (
  select 'owner_membership_missing' as key, count(*)::integer as n
  from public.rf_companies c
  where not exists (
    select 1 from public.rf_memberships m
    where m.company_id=c.id
      and m.user_id=c.primary_owner_user_id
      and m.active
  )
  union all
  select 'current_version_missing',count(*)::integer
  from public.rf_regies r
  where r.current_version_no>0
    and not exists (
      select 1 from public.rf_regie_versions v
      where v.regie_id=r.id and v.version_no=r.current_version_no
    )
  union all
  select 'approved_without_final_pdf',count(*)::integer
  from public.rf_regies r
  where r.status in ('approved','in_execution','awaiting_rapport','closed')
    and not exists (
      select 1
      from public.rf_regie_versions v
      join public.rf_documents d on d.version_id=v.id
      where v.regie_id=r.id
        and v.version_no=r.current_version_no
        and d.document_type='signed_regie_pdf'
    )
  union all
  select 'closed_without_rapport_number',count(*)::integer
  from public.rf_regies
  where status='closed'
    and (rapport_number is null or btrim(rapport_number)='')
  union all
  select 'approved_signature_hash_mismatch',count(*)::integer
  from public.rf_customer_signatures s
  join public.rf_documents d
    on d.version_id=s.version_id
   and d.document_type='signed_regie_pdf'
  where s.decision='approved'
    and s.document_sha256 is distinct from d.sha256
  union all
  select 'paid_billing_missing_provider_ids',count(*)::integer
  from public.rf_company_billing
  where plan<>'development'
    and subscription_status in ('active','trialing','past_due')
    and (stripe_customer_id is null or stripe_subscription_id is null or stripe_price_id is null)
)
select jsonb_build_object(
  'ok',bool_and(n=0),
  'checks',jsonb_object_agg(key,n)
)
from checks;
$$;

revoke all on function public.rf_system_integrity_check()
  from public,anon,authenticated;
grant execute on function public.rf_system_integrity_check()
  to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','System integrity self-check added',
'Added a service-only integrity check covering Primary Owner membership, current-version linkage, required final PDFs for approved/executed/closed Regien, Rapportnummer on closed Regien, signature/document hash consistency and paid billing provider IDs.');


-- 20261001221709 regieflow_stripe_identifier_uniqueness_v1

create unique index if not exists rf_plan_catalog_stripe_price_uidx
  on public.rf_plan_catalog(stripe_price_id)
  where stripe_price_id is not null;

create unique index if not exists rf_plan_catalog_stripe_extra_price_uidx
  on public.rf_plan_catalog(stripe_extra_price_id)
  where stripe_extra_price_id is not null;

create unique index if not exists rf_company_billing_extra_item_uidx
  on public.rf_company_billing(stripe_extra_subscription_item_id)
  where stripe_extra_subscription_item_id is not null;


-- 20261001221904 regieflow_push_account_centric_v1

create or replace function regieflow_private.dispatch_push_notification()
returns trigger
language plpgsql
security definer
set search_path=public,regieflow_private,net
as $$
declare
  v_secret text;
  v_has_subscription boolean;
  v_customer_user uuid;
begin
  if new.recipient_customer_contact_id is not null then
    select auth_user_id into v_customer_user
    from public.rf_customer_contacts
    where id=new.recipient_customer_contact_id;
  end if;

  select exists (
    select 1
    from public.rf_push_subscriptions s
    where (new.recipient_user_id is not null and s.user_id=new.recipient_user_id)
       or (new.recipient_customer_contact_id is not null and s.customer_contact_id=new.recipient_customer_contact_id)
       or (v_customer_user is not null and s.user_id=v_customer_user)
  ) into v_has_subscription;

  if not v_has_subscription then
    return new;
  end if;

  select hook_secret into v_secret
  from regieflow_private.push_config
  where singleton=true;

  perform net.http_post(
    url := 'https://kiihabzzepoehsokglzq.supabase.co/functions/v1/rf-push',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-regieflow-hook',v_secret
    ),
    body := jsonb_build_object('notificationId',new.id)
  );

  return new;
end
$$;

revoke all on function regieflow_private.dispatch_push_notification()
from public,anon,authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Push subscriptions made account-centric',
'Push dispatch now recognizes customer notifications through the customer contact auth_user_id, allowing one browser subscription to follow the signed-in account across internal/customer and multi-company contexts. Legacy contact-specific subscriptions remain compatible.');


-- 20261001222120 regieflow_revision_resets_execution_state_v1

create or replace function public.rf_create_regie_revision(
  p_regie_id uuid,
  p_description text,
  p_estimate_label text,
  p_estimate_minutes integer default null,
  p_copy_before_photos boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_next integer;
  v_prev_version uuid;
  v_new_version uuid;
begin
  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.status='closed' then raise exception 'Closed Regie cannot be revised'; end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.create') then raise exception 'Not allowed'; end if;
  if p_description is null or btrim(p_description)='' then raise exception 'Description required'; end if;
  if p_estimate_label is null or btrim(p_estimate_label)='' then raise exception 'Estimate required'; end if;

  select coalesce(max(version_no),0)+1 into v_next
  from public.rf_regie_versions
  where regie_id=p_regie_id;

  select id into v_prev_version
  from public.rf_regie_versions
  where regie_id=p_regie_id
  order by version_no desc
  limit 1;

  insert into public.rf_regie_versions(
    regie_id,version_no,description,estimate_label,estimate_minutes,created_by_user_id
  )
  values(
    p_regie_id,v_next,btrim(p_description),btrim(p_estimate_label),p_estimate_minutes,auth.uid()
  )
  returning id into v_new_version;

  update public.rf_regies
  set status='draft',
      current_version_no=v_next,
      work_completed_at=null,
      updated_at=now()
  where id=p_regie_id;

  if p_copy_before_photos and v_prev_version is not null then
    insert into public.rf_regie_files(
      regie_id,version_id,kind,storage_path,original_filename,mime_type,byte_size,sha256,sort_order,uploaded_by_user_id
    )
    select
      regie_id,v_new_version,'before',storage_path,original_filename,mime_type,byte_size,sha256,sort_order,auth.uid()
    from public.rf_regie_files
    where regie_id=p_regie_id
      and version_id=v_prev_version
      and kind='before';
  end if;

  update public.rf_public_approval_links pal
  set revoked_at=coalesce(revoked_at,now())
  where pal.version_id in (
    select id
    from public.rf_regie_versions
    where regie_id=p_regie_id and id<>v_new_version
  )
    and pal.used_at is null
    and pal.revoked_at is null;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,p_regie_id,auth.uid(),'regie_revision_created',
    jsonb_build_object(
      'new_version_id',v_new_version,
      'new_version_no',v_next,
      'copied_before_photos',p_copy_before_photos,
      'previous_status',v_regie.status
    )
  );

  return jsonb_build_object('regieId',p_regie_id,'versionId',v_new_version,'versionNo',v_next);
end
$$;

revoke all on function public.rf_create_regie_revision(uuid,text,text,integer,boolean) from public,anon;
grant execute on function public.rf_create_regie_revision(uuid,text,text,integer,boolean) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Revision resets stale execution completion state',
'Creating a new Regie version now clears work_completed_at and records the previous workflow status in audit metadata. This prevents a revised, newly re-approved scope from carrying a stale completion timestamp from an earlier version.');


-- 20261001222558 regieflow_private_signup_rpc_boundary_v1

create or replace function public.rf_signup_find_open(p_email text)
returns jsonb
language sql
security definer
set search_path=regieflow_private,public
as $$
  select to_jsonb(x)
  from (
    select id,status,stripe_checkout_url,expires_at,created_at
    from regieflow_private.signup_intents
    where lower(email)=lower(btrim(p_email))
      and status in ('pending','checkout_created','paid')
    order by created_at desc
    limit 1
  ) x;
$$;

create or replace function public.rf_signup_create_intent(
  p_email text,
  p_company_name text,
  p_owner_display_name text,
  p_plan text,
  p_legal_version_hash text
)
returns uuid
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
declare v_id uuid;
begin
  update regieflow_private.signup_intents
  set status='cancelled',updated_at=now()
  where lower(email)=lower(btrim(p_email))
    and status in ('pending','checkout_created');

  insert into regieflow_private.signup_intents(
    email,company_name,owner_display_name,plan,status,expires_at,
    legal_accepted_at,legal_version_hash
  ) values(
    lower(btrim(p_email)),btrim(p_company_name),btrim(p_owner_display_name),
    p_plan,'pending',now()+interval '24 hours',now(),p_legal_version_hash
  ) returning id into v_id;
  return v_id;
end
$$;

create or replace function public.rf_signup_set_checkout(
  p_intent_id uuid,
  p_checkout_session_id text,
  p_checkout_url text,
  p_stripe_price_id text
)
returns boolean
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
begin
  update regieflow_private.signup_intents
  set stripe_checkout_session_id=p_checkout_session_id,
      stripe_checkout_url=p_checkout_url,
      stripe_price_id=p_stripe_price_id,
      status='checkout_created',
      updated_at=now()
  where id=p_intent_id and status='pending';
  if not found then raise exception 'Signup intent is not pending'; end if;
  return true;
end
$$;

create or replace function public.rf_signup_cancel_intent(p_intent_id uuid)
returns boolean
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
begin
  update regieflow_private.signup_intents
  set status='cancelled',updated_at=now()
  where id=p_intent_id and status in ('pending','checkout_created');
  return true;
end
$$;

create or replace function public.rf_signup_get_by_checkout(p_checkout_session_id text)
returns jsonb
language sql
security definer
set search_path=regieflow_private,public
as $$
  select to_jsonb(x)
  from (
    select id,email,company_name,owner_display_name,plan,status,auth_user_id,
           stripe_checkout_session_id,stripe_checkout_url,stripe_customer_id,
           stripe_subscription_id,stripe_price_id,paid_at,
           completion_token_hash,completion_expires_at,
           provisioned_company_id,expires_at,created_at
    from regieflow_private.signup_intents
    where stripe_checkout_session_id=p_checkout_session_id
    limit 1
  ) x;
$$;

create or replace function public.rf_signup_mark_paid(
  p_intent_id uuid,
  p_checkout_session_id text,
  p_stripe_customer_id text,
  p_stripe_subscription_id text
)
returns jsonb
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
declare v_row regieflow_private.signup_intents%rowtype;
begin
  update regieflow_private.signup_intents
  set status=case when status='provisioned' then status else 'paid' end,
      paid_at=coalesce(paid_at,now()),
      stripe_customer_id=coalesce(p_stripe_customer_id,stripe_customer_id),
      stripe_subscription_id=coalesce(p_stripe_subscription_id,stripe_subscription_id),
      updated_at=now()
  where id=p_intent_id
    and stripe_checkout_session_id=p_checkout_session_id
  returning * into v_row;
  if not found then raise exception 'Signup intent not found'; end if;
  return to_jsonb(v_row);
end
$$;

create or replace function public.rf_signup_issue_completion(p_intent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=regieflow_private,public,extensions
as $$
declare
  v_row regieflow_private.signup_intents%rowtype;
  v_token text;
  v_exp timestamptz;
begin
  select * into v_row
  from regieflow_private.signup_intents
  where id=p_intent_id
  for update;
  if not found then raise exception 'Signup intent not found'; end if;
  if v_row.status='provisioned' then
    return jsonb_build_object(
      'status','provisioned',
      'email',v_row.email,
      'companyName',v_row.company_name,
      'plan',v_row.plan,
      'companyId',v_row.provisioned_company_id
    );
  end if;
  if v_row.status<>'paid' then raise exception 'Signup intent is not paid'; end if;

  v_token:=encode(gen_random_bytes(32),'hex');
  v_exp:=now()+interval '30 minutes';

  update regieflow_private.signup_intents
  set completion_token_hash=encode(digest(v_token,'sha256'),'hex'),
      completion_expires_at=v_exp,
      updated_at=now()
  where id=p_intent_id;

  return jsonb_build_object(
    'status','paid',
    'intentId',v_row.id,
    'completionToken',v_token,
    'completionExpiresAt',v_exp,
    'email',v_row.email,
    'companyName',v_row.company_name,
    'ownerDisplayName',v_row.owner_display_name,
    'plan',v_row.plan
  );
end
$$;

create or replace function public.rf_signup_verify_completion(
  p_intent_id uuid,
  p_completion_token_hash text
)
returns jsonb
language sql
security definer
set search_path=regieflow_private,public
as $$
  select to_jsonb(x)
  from (
    select id,email,company_name,owner_display_name,plan,status,auth_user_id,
           stripe_checkout_session_id,stripe_customer_id,stripe_subscription_id,
           stripe_price_id,provisioned_company_id
    from regieflow_private.signup_intents
    where id=p_intent_id
      and completion_token_hash=p_completion_token_hash
      and completion_expires_at>now()
    limit 1
  ) x;
$$;

create or replace function public.rf_signup_set_auth_user(
  p_intent_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
begin
  update regieflow_private.signup_intents
  set auth_user_id=p_user_id,updated_at=now()
  where id=p_intent_id and status='paid';
  if not found then raise exception 'Signup intent is not paid'; end if;
  return true;
end
$$;

create or replace function public.rf_signup_clear_auth_user(
  p_intent_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
begin
  update regieflow_private.signup_intents
  set auth_user_id=null,updated_at=now()
  where id=p_intent_id and auth_user_id=p_user_id and status='paid';
  return true;
end
$$;

create or replace function public.rf_billing_event_begin(
  p_provider_event_id text,
  p_event_type text,
  p_payload_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
declare v regieflow_private.billing_events%rowtype;
begin
  insert into regieflow_private.billing_events(provider_event_id,event_type,payload_sha256)
  values(p_provider_event_id,p_event_type,p_payload_sha256)
  on conflict(provider_event_id) do nothing;

  select * into v
  from regieflow_private.billing_events
  where provider_event_id=p_provider_event_id;

  return jsonb_build_object(
    'providerEventId',v.provider_event_id,
    'applied',v.applied_at is not null,
    'appliedAt',v.applied_at,
    'companyId',v.company_id
  );
end
$$;

create or replace function public.rf_billing_event_mark_applied(
  p_provider_event_id text,
  p_company_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path=regieflow_private,public
as $$
begin
  update regieflow_private.billing_events
  set applied_at=coalesce(applied_at,now()),
      company_id=coalesce(p_company_id,company_id)
  where provider_event_id=p_provider_event_id;
  if not found then raise exception 'Billing event not found'; end if;
  return true;
end
$$;

revoke all on function public.rf_signup_find_open(text) from public,anon,authenticated;
revoke all on function public.rf_signup_create_intent(text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.rf_signup_set_checkout(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.rf_signup_cancel_intent(uuid) from public,anon,authenticated;
revoke all on function public.rf_signup_get_by_checkout(text) from public,anon,authenticated;
revoke all on function public.rf_signup_mark_paid(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.rf_signup_issue_completion(uuid) from public,anon,authenticated;
revoke all on function public.rf_signup_verify_completion(uuid,text) from public,anon,authenticated;
revoke all on function public.rf_signup_set_auth_user(uuid,uuid) from public,anon,authenticated;
revoke all on function public.rf_signup_clear_auth_user(uuid,uuid) from public,anon,authenticated;
revoke all on function public.rf_billing_event_begin(text,text,text) from public,anon,authenticated;
revoke all on function public.rf_billing_event_mark_applied(text,uuid) from public,anon,authenticated;

grant execute on function public.rf_signup_find_open(text) to service_role;
grant execute on function public.rf_signup_create_intent(text,text,text,text,text) to service_role;
grant execute on function public.rf_signup_set_checkout(uuid,text,text,text) to service_role;
grant execute on function public.rf_signup_cancel_intent(uuid) to service_role;
grant execute on function public.rf_signup_get_by_checkout(text) to service_role;
grant execute on function public.rf_signup_mark_paid(uuid,text,text,text) to service_role;
grant execute on function public.rf_signup_issue_completion(uuid) to service_role;
grant execute on function public.rf_signup_verify_completion(uuid,text) to service_role;
grant execute on function public.rf_signup_set_auth_user(uuid,uuid) to service_role;
grant execute on function public.rf_signup_clear_auth_user(uuid,uuid) to service_role;
grant execute on function public.rf_billing_event_begin(text,text,text) to service_role;
grant execute on function public.rf_billing_event_mark_applied(text,uuid) to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Private signup/billing tables isolated behind service RPC boundary',
'Added service-role-only public RPC wrappers for paid signup intents and billing event idempotency. Edge Functions no longer need direct PostgREST exposure of regieflow_private, preserving the private schema boundary while keeping paid onboarding operational.');


-- 20261001222937 regieflow_billing_status_notifications_v1

create or replace function public.rf_apply_subscription_state(
  p_company_id uuid,
  p_plan text,
  p_stripe_customer_id text,
  p_stripe_subscription_id text,
  p_stripe_price_id text,
  p_subscription_status text,
  p_current_period_end timestamptz,
  p_cancel_at_period_end boolean,
  p_provider_event_id text,
  p_billing_email text default null
)
returns boolean
language plpgsql
security definer
set search_path=public,regieflow_private
as $$
declare
  v_plan public.rf_plan_catalog%rowtype;
  v_old_status text;
  v_owner uuid;
begin
  if p_plan not in ('starter','team','business') then
    raise exception 'Unknown plan';
  end if;

  select * into v_plan
  from public.rf_plan_catalog
  where plan=p_plan and active;
  if not found then raise exception 'Plan not active'; end if;

  if p_provider_event_id is null or btrim(p_provider_event_id)='' then
    raise exception 'Provider event id required';
  end if;

  if exists (
    select 1 from regieflow_private.billing_events
    where provider_event_id=p_provider_event_id and applied_at is not null
  ) then
    return true;
  end if;

  select subscription_status into v_old_status
  from public.rf_company_billing
  where company_id=p_company_id;

  select primary_owner_user_id into v_owner
  from public.rf_companies
  where id=p_company_id;

  insert into regieflow_private.billing_events(provider_event_id,event_type,company_id)
  values(p_provider_event_id,coalesce(p_subscription_status,'unknown'),p_company_id)
  on conflict (provider_event_id) do nothing;

  insert into public.rf_company_billing(
    company_id,plan,included_internal_profiles,additional_profile_price_chf,
    stripe_customer_id,stripe_subscription_id,stripe_price_id,subscription_status,
    billing_email,current_period_end,cancel_at_period_end,last_provider_event_id
  )
  values(
    p_company_id,p_plan,v_plan.included_internal_profiles,v_plan.extra_profile_price_chf,
    p_stripe_customer_id,p_stripe_subscription_id,p_stripe_price_id,p_subscription_status,
    p_billing_email,p_current_period_end,coalesce(p_cancel_at_period_end,false),p_provider_event_id
  )
  on conflict (company_id) do update set
    plan=excluded.plan,
    included_internal_profiles=excluded.included_internal_profiles,
    additional_profile_price_chf=excluded.additional_profile_price_chf,
    stripe_customer_id=excluded.stripe_customer_id,
    stripe_subscription_id=excluded.stripe_subscription_id,
    stripe_price_id=excluded.stripe_price_id,
    subscription_status=excluded.subscription_status,
    billing_email=coalesce(excluded.billing_email,public.rf_company_billing.billing_email),
    current_period_end=excluded.current_period_end,
    cancel_at_period_end=excluded.cancel_at_period_end,
    last_provider_event_id=excluded.last_provider_event_id,
    updated_at=now();

  update regieflow_private.billing_events
  set applied_at=now(),company_id=p_company_id
  where provider_event_id=p_provider_event_id;

  insert into public.rf_audit_log(company_id,event_type,metadata)
  values(
    p_company_id,'billing_subscription_updated',
    jsonb_build_object(
      'plan',p_plan,
      'previous_status',v_old_status,
      'subscription_status',p_subscription_status,
      'provider_event_id',p_provider_event_id,
      'current_period_end',p_current_period_end,
      'cancel_at_period_end',coalesce(p_cancel_at_period_end,false)
    )
  );

  if v_owner is not null and v_old_status is distinct from p_subscription_status then
    insert into public.rf_notifications(
      company_id,recipient_user_id,type,title,body
    )
    values(
      p_company_id,v_owner,'billing_status',
      case
        when p_subscription_status='past_due' then 'Zahlung prüfen'
        when p_subscription_status in ('canceled','unpaid','incomplete_expired','paused') then 'RegieFlow-Abo eingeschränkt'
        when p_subscription_status in ('active','trialing') then 'RegieFlow-Abo aktiv'
        else 'Abo-Status geändert'
      end,
      case
        when p_subscription_status='past_due' then 'Bei der letzten Zahlung gab es ein Problem. Bitte prüfe die Abrechnung in den Einstellungen.'
        when p_subscription_status in ('canceled','unpaid','incomplete_expired','paused') then 'Die Firma ist jetzt im Nur-Lesen-Modus. Bestehende Daten bleiben verfügbar.'
        when p_subscription_status in ('active','trialing') then 'Das Firmenabo ist aktiv und RegieFlow kann normal verwendet werden.'
        else 'Der Abostatus wurde aktualisiert.'
      end
    );
  end if;

  return true;
end
$$;

revoke all on function public.rf_apply_subscription_state(
  uuid,text,text,text,text,text,timestamptz,boolean,text,text
) from public,anon,authenticated;
grant execute on function public.rf_apply_subscription_state(
  uuid,text,text,text,text,text,timestamptz,boolean,text,text
) to service_role;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Billing state changes notify Primary Owner',
'Stripe subscription state transitions now create an in-app notification for the Primary Owner. Past-due asks the owner to review payment; inactive/cancelled states explain read-only mode; recovery to active/trialing is also surfaced.');


-- 20261001223054 regieflow_production_readiness_flags_v1

create table if not exists regieflow_private.production_config (
  singleton boolean primary key default true check (singleton),
  email_confirmation_ready boolean not null default false,
  leaked_password_protection_ready boolean not null default false,
  backup_recovery_ready boolean not null default false,
  updated_at timestamptz not null default now()
);

revoke all on regieflow_private.production_config from public,anon,authenticated;

insert into regieflow_private.production_config(singleton)
values(true)
on conflict (singleton) do nothing;

create or replace function public.rf_production_readiness()
returns jsonb
language sql
security definer
set search_path=regieflow_private,public
as $$
  select jsonb_build_object(
    'emailConfirmationReady',email_confirmation_ready,
    'leakedPasswordProtectionReady',leaked_password_protection_ready,
    'backupRecoveryReady',backup_recovery_ready
  )
  from regieflow_private.production_config
  where singleton=true;
$$;

revoke all on function public.rf_production_readiness() from public,anon,authenticated;
grant execute on function public.rf_production_readiness() to service_role;

insert into regieflow_private.launch_checklist(key,category,title,status,blocker,evidence)
values
('email_confirmation','security','E-Mail-Verifikation für öffentliche Firmenkonten','blocked','Supabase Auth E-Mail-Bestätigung und produktionsfähiger SMTP-Versand müssen aktiviert und getestet werden.','Paid onboarding code is being hardened to wait for a confirmed account before provisioning.'),
('production_gate','ops','Öffentliche Registrierung Sicherheits-Gate','in_progress',null,'Private production_config flags gate public registration on email confirmation, leaked-password protection and backup/recovery readiness.')
on conflict(key) do update set
  category=excluded.category,title=excluded.title,status=excluded.status,
  blocker=excluded.blocker,evidence=excluded.evidence,updated_at=now();

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Explicit production readiness flags added',
'Added private production_config flags for verified email-confirmation/SMTP setup, leaked-password protection and backup/recovery readiness. Public paid signup can now stay hard-disabled until those external production controls are actually confirmed instead of assuming they are configured.');


-- 20261001223355 regieflow_overview_current_version_evidence_v2

create or replace view public.rf_regie_overview
with (security_invoker=true)
as
select
  r.id,r.company_id,r.project_id,r.regie_code,r.source,r.status,
  r.created_by_user_id,r.requested_by_customer_contact_id,r.assigned_monteur_user_id,
  r.current_version_no,r.rapport_number,r.work_completed_at,r.closed_at,
  r.created_at,r.updated_at,
  p.project_number,p.external_project_reference,p.name as project_name,
  p.address as project_address,p.client_name,p.approval_workflow,
  coalesce(v.description,r.request_description) as description,
  v.estimate_label,v.estimate_disclaimer,v.id as current_version_id,
  v.locked_at as current_version_locked_at,
  exists(select 1 from public.rf_documents d where d.version_id=v.id) as has_final_pdf,
  (select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.version_id=v.id and f.kind='before') as before_photo_count,
  (select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.version_id=v.id and f.kind='after') as after_photo_count,
  (select count(*)::integer from public.rf_regie_files f
    where f.regie_id=r.id and f.kind='customer_request') as customer_request_photo_count
from public.rf_regies r
join public.rf_projects p on p.id=r.project_id
left join public.rf_regie_versions v
  on v.regie_id=r.id and v.version_no=r.current_version_no;

grant select on public.rf_regie_overview to authenticated;


-- 20261001223644 regieflow_assignee_permission_integrity_v1

create or replace function public.rf_user_has_permission(
  p_company uuid,
  p_user uuid,
  p_permission text
)
returns boolean
language plpgsql
security definer
stable
set search_path=public
as $$
declare
  v_override jsonb;
  v_permissions text[];
begin
  if p_company is null or p_user is null or p_permission is null then
    return false;
  end if;

  if exists(
    select 1 from public.rf_companies c
    where c.id=p_company and c.primary_owner_user_id=p_user
  ) then
    return true;
  end if;

  select m.permission_overrides,coalesce(r.permissions,'{}'::text[])
  into v_override,v_permissions
  from public.rf_memberships m
  left join public.rf_roles r on r.id=m.role_id
  where m.company_id=p_company
    and m.user_id=p_user
    and m.active
  limit 1;

  if not found then return false; end if;
  if v_override ? p_permission then
    return coalesce((v_override->>p_permission)::boolean,false);
  end if;
  return p_permission=any(v_permissions);
end
$$;

revoke all on function public.rf_user_has_permission(uuid,uuid,text)
from public,anon,authenticated;

create or replace function public.rf_decide_customer_request(
  p_regie_id uuid,
  p_decision text,
  p_assigned_monteur_user_id uuid default null
)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_regie public.rf_regies%rowtype;
  v_status text;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Invalid decision';
  end if;

  select * into v_regie
  from public.rf_regies
  where id=p_regie_id
  for update;

  if not found then raise exception 'Regie not found'; end if;
  if v_regie.source<>'customer' or v_regie.status<>'customer_request' then
    raise exception 'Regie is not an open customer request';
  end if;
  if not public.rf_has_permission(v_regie.company_id,'regies.review') then
    raise exception 'Not allowed';
  end if;

  if p_decision='approved' then
    if p_assigned_monteur_user_id is null then
      raise exception 'Assigned Monteur is required';
    end if;
    if not public.rf_user_has_permission(
      v_regie.company_id,p_assigned_monteur_user_id,'regies.create'
    ) then
      raise exception 'Assigned Monteur cannot create Regien';
    end if;

    v_status:='draft';
    update public.rf_regies
    set status='draft',
        assigned_monteur_user_id=p_assigned_monteur_user_id,
        updated_at=now()
    where id=p_regie_id;
  else
    v_status:='rejected';
    update public.rf_regies
    set status='rejected',updated_at=now()
    where id=p_regie_id;
  end if;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_regie.company_id,v_regie.project_id,v_regie.id,auth.uid(),
    'customer_request_'||p_decision,
    jsonb_build_object('assigned_monteur_user_id',p_assigned_monteur_user_id)
  );

  if v_regie.requested_by_customer_contact_id is not null then
    insert into public.rf_notifications(
      company_id,recipient_customer_contact_id,regie_id,type,title,body
    )
    values(
      v_regie.company_id,v_regie.requested_by_customer_contact_id,v_regie.id,
      'customer_request_'||p_decision,
      case when p_decision='approved' then 'Auftrag wurde übernommen' else 'Auftrag wurde abgelehnt' end,
      case when p_decision='approved'
        then 'Ihre Anfrage wurde vom Betrieb übernommen.'
        else 'Ihre Anfrage wurde vom Betrieb abgelehnt.'
      end
    );
  end if;

  if p_decision='approved' then
    insert into public.rf_notifications(
      company_id,recipient_user_id,regie_id,type,title,body
    )
    values(
      v_regie.company_id,p_assigned_monteur_user_id,v_regie.id,
      'customer_request_assigned',
      'Neuer Kundenauftrag',
      'Eine Kundenanfrage wurde Ihnen zugewiesen.'
    );
  end if;

  return v_status;
end
$$;

revoke all on function public.rf_decide_customer_request(uuid,text,uuid)
from public,anon;
grant execute on function public.rf_decide_customer_request(uuid,text,uuid)
to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Customer-request assignment requires a real Regie creator',
'Accepted customer requests must now be assigned to an active internal user who actually has regies.create (or is Primary Owner). This prevents assigning work to a read-only/office-only account that cannot prepare the resulting Regie.');


-- 20261001223738 regieflow_internal_regie_assignee_permission_v1

create or replace function public.rf_create_internal_regie(
  p_project_id uuid,
  p_description text,
  p_estimate_label text,
  p_estimate_minutes integer default null,
  p_assigned_monteur_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_project public.rf_projects%rowtype;
  v_regie_id uuid;
  v_version_id uuid;
  v_monteur uuid;
begin
  select * into v_project
  from public.rf_projects
  where id=p_project_id and active;

  if not found then raise exception 'Project not found or inactive'; end if;
  if not public.rf_has_permission(v_project.company_id,'regies.create') then
    raise exception 'Not allowed';
  end if;
  if p_description is null or btrim(p_description)='' then raise exception 'Description required'; end if;
  if p_estimate_label is null or btrim(p_estimate_label)='' then raise exception 'Estimate required'; end if;
  if p_estimate_minutes is not null and p_estimate_minutes<=0 then raise exception 'Estimate minutes must be positive'; end if;

  v_monteur:=coalesce(p_assigned_monteur_user_id,auth.uid());

  if not public.rf_user_has_permission(v_project.company_id,v_monteur,'regies.create') then
    raise exception 'Assigned Monteur cannot create Regien';
  end if;

  insert into public.rf_regies(
    company_id,project_id,source,status,created_by_user_id,assigned_monteur_user_id,current_version_no
  )
  values(
    v_project.company_id,p_project_id,'internal','draft',auth.uid(),v_monteur,1
  )
  returning id into v_regie_id;

  insert into public.rf_regie_versions(
    regie_id,version_no,description,estimate_label,estimate_minutes,created_by_user_id
  )
  values(
    v_regie_id,1,btrim(p_description),btrim(p_estimate_label),p_estimate_minutes,auth.uid()
  )
  returning id into v_version_id;

  insert into public.rf_audit_log(
    company_id,project_id,regie_id,actor_user_id,event_type,metadata
  )
  values(
    v_project.company_id,p_project_id,v_regie_id,auth.uid(),'regie_created',
    jsonb_build_object(
      'version_id',v_version_id,
      'version_no',1,
      'assigned_monteur_user_id',v_monteur
    )
  );

  return jsonb_build_object('regieId',v_regie_id,'versionId',v_version_id,'versionNo',1);
end
$$;

revoke all on function public.rf_create_internal_regie(uuid,text,text,integer,uuid)
from public,anon;
grant execute on function public.rf_create_internal_regie(uuid,text,text,integer,uuid)
to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','New Regie assignment permission enforced',
'New internal Regien can now be assigned only to an active user who can actually create Regien (or Primary Owner). The frontend also lets Büro choose an authorized responsible Monteur while defaulting to the creator.');

