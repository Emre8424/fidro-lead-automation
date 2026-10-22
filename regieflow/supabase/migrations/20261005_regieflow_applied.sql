-- 20261005152600 regieflow_performance_cleanup_v2

create index if not exists rf_private_billing_events_company_idx
  on regieflow_private.billing_events(company_id);

create index if not exists rf_private_signup_auth_user_idx
  on regieflow_private.signup_intents(auth_user_id);

create index if not exists rf_private_signup_company_idx
  on regieflow_private.signup_intents(provisioned_company_id);

drop index if exists public.rf_customer_signature_approved_version_uidx;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Performance advisor cleanup v2',
'Added covering indexes for RegieFlow private billing/signup foreign keys and removed the duplicate approved-signature unique index while retaining the equivalent existing uniqueness protection. No DriveLoop indexes were changed.');


-- 20261005153728 regieflow_customer_approval_subscription_gate_v1

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

  if not public.rf_company_write_enabled(v_regie.company_id) then
    raise exception 'Company subscription is read-only';
  end if;

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
('completed','Customer approval respects paid read-only state',
'The service-only approval finalizer now checks rf_company_write_enabled. If a paid company becomes inactive/cancelled/unpaid, pending secure-link or account approvals cannot mutate workflow state while archive/document reads remain available.');


-- 20261005192852 regieflow_project_customer_mutations_rpc_v1

create or replace function public.rf_create_project(
  p_company_id uuid,
  p_project_number text,
  p_name text,
  p_address text default null,
  p_client_name text default null,
  p_approval_workflow text default 'office_then_customer'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
begin
  if not public.rf_has_permission(p_company_id,'projects.manage') then
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

  insert into public.rf_projects(
    company_id,project_number,name,address,client_name,approval_workflow,active,created_by
  )
  values(
    p_company_id,btrim(p_project_number),btrim(p_name),
    nullif(btrim(coalesce(p_address,'')),''),
    nullif(btrim(coalesce(p_client_name,'')),''),
    p_approval_workflow,true,auth.uid()
  )
  returning id into v_id;

  return v_id;
end
$$;

create or replace function public.rf_create_customer_contact(
  p_company_id uuid,
  p_full_name text,
  p_organization_name text default null,
  p_email text default null,
  p_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_email text;
begin
  if not public.rf_has_permission(p_company_id,'projects.manage') then
    raise exception 'Not allowed';
  end if;
  if p_full_name is null or btrim(p_full_name)='' then
    raise exception 'Name required';
  end if;

  v_email:=nullif(lower(btrim(coalesce(p_email,''))),'');
  if v_email is not null and position('@' in v_email)=0 then
    raise exception 'Valid email required';
  end if;

  insert into public.rf_customer_contacts(
    company_id,full_name,organization_name,email,phone,active
  )
  values(
    p_company_id,btrim(p_full_name),
    nullif(btrim(coalesce(p_organization_name,'')),''),
    v_email,
    nullif(btrim(coalesce(p_phone,'')),''),
    true
  )
  returning id into v_id;

  return v_id;
end
$$;

create or replace function public.rf_set_project_customer_access(
  p_project_id uuid,
  p_customer_contact_id uuid,
  p_enabled boolean,
  p_can_sign boolean default false,
  p_label text default null
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid;
  v_contact_company uuid;
  v_active boolean;
begin
  select company_id into v_company
  from public.rf_projects
  where id=p_project_id;

  if v_company is null then raise exception 'Project not found'; end if;
  if not public.rf_has_permission(v_company,'projects.manage') then
    raise exception 'Not allowed';
  end if;

  select company_id,active into v_contact_company,v_active
  from public.rf_customer_contacts
  where id=p_customer_contact_id;

  if v_contact_company is null then raise exception 'Customer contact not found'; end if;
  if v_contact_company<>v_company then
    raise exception 'Customer contact must belong to the same company';
  end if;

  if not coalesce(p_enabled,false) then
    delete from public.rf_project_customer_access
    where project_id=p_project_id and customer_contact_id=p_customer_contact_id;
    return true;
  end if;

  if not v_active then
    raise exception 'Customer contact is inactive';
  end if;

  insert into public.rf_project_customer_access(
    project_id,customer_contact_id,can_sign,label
  )
  values(
    p_project_id,p_customer_contact_id,coalesce(p_can_sign,false),
    nullif(btrim(coalesce(p_label,'')),'')
  )
  on conflict (project_id,customer_contact_id)
  do update set
    can_sign=excluded.can_sign,
    label=excluded.label;

  return true;
end
$$;

revoke all on function public.rf_create_project(uuid,text,text,text,text,text) from public,anon;
revoke all on function public.rf_create_customer_contact(uuid,text,text,text,text) from public,anon;
revoke all on function public.rf_set_project_customer_access(uuid,uuid,boolean,boolean,text) from public,anon;

grant execute on function public.rf_create_project(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.rf_create_customer_contact(uuid,text,text,text,text) to authenticated;
grant execute on function public.rf_set_project_customer_access(uuid,uuid,boolean,boolean,text) to authenticated;

revoke insert,update on public.rf_projects from authenticated;
revoke insert,update on public.rf_customer_contacts from authenticated;
revoke insert,update,delete on public.rf_project_customer_access from authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Project/customer mutations moved behind controlled RPCs',
'Project creation, customer-contact creation and project/customer access changes now run through permission-checked SECURITY DEFINER RPCs that validate tenant ownership, active contacts and allowed workflow values. Direct authenticated INSERT/UPDATE/DELETE privileges were removed from rf_projects, rf_customer_contacts and rf_project_customer_access, closing spoofable IDs/timestamps/auth_user_id and other direct mutation surfaces.');


-- 20261005193212 regieflow_customer_invite_email_binding_v1

create or replace function public.rf_create_customer_invite(
  p_customer_contact_id uuid,
  p_valid_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path=public,extensions
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

  if v_contact.email is null or btrim(v_contact.email)='' then
    raise exception 'Customer email required for account invitation';
  end if;

  if exists (
    select 1
    from public.rf_customer_contacts c
    where c.company_id=v_contact.company_id
      and c.id<>v_contact.id
      and c.active
      and c.email is not null
      and lower(btrim(c.email))=lower(btrim(v_contact.email))
  ) then
    raise exception 'Customer email is used by another active contact';
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
    jsonb_build_object('valid_hours',p_valid_hours,'email',lower(btrim(v_contact.email)))
  );

  return v_token;
end
$$;

revoke all on function public.rf_create_customer_invite(uuid,integer) from public,anon;
grant execute on function public.rf_create_customer_invite(uuid,integer) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Customer account invitations bound to a unique contact email',
'Customer account invitations now require the contact to have an email address and refuse invitation when another active contact in the same company uses the same email. Since signup/claim already enforce the stored contact email, forwarded invitation links can no longer be claimed under an arbitrary new email.');


-- 20261005193335 regieflow_revoke_stale_contact_links_v1

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
  v_new_email text;
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

  v_new_email:=nullif(lower(btrim(coalesce(p_email,''))),'');

  update public.rf_customer_contacts
  set
    full_name=btrim(p_full_name),
    organization_name=nullif(btrim(coalesce(p_organization_name,'')),''),
    email=v_new_email,
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
  end if;

  if coalesce(p_active,true)=false
     or lower(coalesce(btrim(v_contact.email),'')) is distinct from lower(coalesce(v_new_email,'')) then
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
      'email_changed',lower(coalesce(btrim(v_contact.email),'')) is distinct from lower(coalesce(v_new_email,'')),
      'active',coalesce(p_active,true)
    )
  );

  return true;
end
$$;

create or replace function public.rf_set_project_customer_access(
  p_project_id uuid,
  p_customer_contact_id uuid,
  p_enabled boolean,
  p_can_sign boolean default false,
  p_label text default null
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid;
  v_contact_company uuid;
  v_active boolean;
begin
  select company_id into v_company
  from public.rf_projects
  where id=p_project_id;

  if v_company is null then raise exception 'Project not found'; end if;
  if not public.rf_has_permission(v_company,'projects.manage') then
    raise exception 'Not allowed';
  end if;

  select company_id,active into v_contact_company,v_active
  from public.rf_customer_contacts
  where id=p_customer_contact_id;

  if v_contact_company is null then raise exception 'Customer contact not found'; end if;
  if v_contact_company<>v_company then
    raise exception 'Customer contact must belong to the same company';
  end if;

  if not coalesce(p_enabled,false) then
    delete from public.rf_project_customer_access
    where project_id=p_project_id and customer_contact_id=p_customer_contact_id;

    update public.rf_public_approval_links pal
    set revoked_at=coalesce(pal.revoked_at,now())
    where pal.customer_contact_id=p_customer_contact_id
      and pal.used_at is null
      and pal.revoked_at is null
      and exists(
        select 1
        from public.rf_regie_versions v
        join public.rf_regies r on r.id=v.regie_id
        where v.id=pal.version_id and r.project_id=p_project_id
      );
    return true;
  end if;

  if not v_active then
    raise exception 'Customer contact is inactive';
  end if;

  insert into public.rf_project_customer_access(
    project_id,customer_contact_id,can_sign,label
  )
  values(
    p_project_id,p_customer_contact_id,coalesce(p_can_sign,false),
    nullif(btrim(coalesce(p_label,'')),'')
  )
  on conflict (project_id,customer_contact_id)
  do update set
    can_sign=excluded.can_sign,
    label=excluded.label;

  if not coalesce(p_can_sign,false) then
    update public.rf_public_approval_links pal
    set revoked_at=coalesce(pal.revoked_at,now())
    where pal.customer_contact_id=p_customer_contact_id
      and pal.used_at is null
      and pal.revoked_at is null
      and exists(
        select 1
        from public.rf_regie_versions v
        join public.rf_regies r on r.id=v.regie_id
        where v.id=pal.version_id and r.project_id=p_project_id
      );
  end if;

  return true;
end
$$;

revoke all on function public.rf_update_customer_contact(uuid,text,text,text,text,boolean) from public,anon;
revoke all on function public.rf_set_project_customer_access(uuid,uuid,boolean,boolean,text) from public,anon;
grant execute on function public.rf_update_customer_contact(uuid,text,text,text,text,boolean) to authenticated;
grant execute on function public.rf_set_project_customer_access(uuid,uuid,boolean,boolean,text) to authenticated;

insert into regieflow_private.dev_log(kind,title,content) values
('completed','Stale customer invitation and approval links are revoked automatically',
'Changing a customer contact email now revokes unused account invitations; deactivation still revokes all unused invites and approval links. Removing project access or turning off can_sign now proactively revokes unused secure approval links for that contact/project instead of merely relying on later authorization checks.');

