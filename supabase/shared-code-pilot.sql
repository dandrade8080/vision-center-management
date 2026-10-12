-- BYD Vision Center pilot shared-code management access.
-- Run in the project's Supabase SQL Editor as the project owner.
-- SECURITY: this is only appropriate for a limited pilot, not a production access policy.
-- Never store the access code in GitHub, frontend JavaScript or config.js.
-- After executing this whole script, use the separate private setup instruction
-- to choose your code in the SQL Editor.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.vc_pilot_access (
  name text primary key,
  code_hash text not null
);
revoke all on private.vc_pilot_access from public, anon, authenticated;
insert into private.vc_pilot_access(name,code_hash)
values ('manager', extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')))
on conflict(name) do nothing;

create or replace function private.vc_valid_code(p_code text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists(
    select 1 from private.vc_pilot_access a
    where a.name='manager'
      and length(coalesce(p_code,'')) between 12 and 128
      and extensions.crypt(p_code,a.code_hash)=a.code_hash
  );
$$;
revoke all on function private.vc_valid_code(text) from public,anon,authenticated;

create or replace function public.vc_management_check(p_code text)
returns boolean language sql stable security definer
set search_path = ''
as $$ select private.vc_valid_code(p_code); $$;
revoke all on function public.vc_management_check(text) from public,anon,authenticated;
grant execute on function public.vc_management_check(text) to anon,authenticated;

create or replace function public.vc_management_list(p_code text)
returns jsonb language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.vc_valid_code(p_code) then return null; end if;
  return coalesce(
    (select jsonb_agg(to_jsonb(e) order by e.event_date,e.start_time)
     from public.event_requests e),
    '[]'::jsonb
  );
end;
$$;
revoke all on function public.vc_management_list(text) from public,anon,authenticated;
grant execute on function public.vc_management_list(text) to anon,authenticated;

create or replace function public.vc_management_history(p_code text,p_event_id uuid)
returns jsonb language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.vc_valid_code(p_code) then return null; end if;
  return coalesce(
    (select jsonb_agg(to_jsonb(h) order by h.changed_at desc)
     from public.event_history h where h.event_id=p_event_id),
    '[]'::jsonb
  );
end;
$$;
revoke all on function public.vc_management_history(text,uuid) from public,anon,authenticated;
grant execute on function public.vc_management_history(text,uuid) to anon,authenticated;

-- Original trigger must continue forcing 'Requested' on all public INSERTs.
-- In this pilot, verified management updates set a transaction-local flag.
create or replace function public.guard_event_request()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op='INSERT' then
    new.created_at := now();
    new.request_status := 'Requested';
    new.operational_status := 'Not started';
    new.manager_notes := null;
    new.updated_by := null;
  elsif coalesce(current_setting('app.vc_manager_verified',true),'')<>'true'
        and not public.is_vision_center_manager() then
    raise exception 'Only managers can update event requests';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.vc_management_update(
  p_code text, p_event_id uuid, p_request_status text,
  p_operational_status text, p_notes text
) returns boolean language plpgsql security definer
set search_path = ''
as $$
declare updated_count integer;
begin
  if not private.vc_valid_code(p_code) then return false; end if;
  if p_request_status not in ('Requested','Under review','Tentatively scheduled',
     'Confirmed','Rejected','Cancelled') then return false; end if;
  if p_operational_status not in ('Not started','Upcoming','In progress','Completed')
     then return false; end if;
  if p_request_status<>'Confirmed' and p_operational_status<>'Not started'
     then return false; end if;
  perform set_config('app.vc_manager_verified','true',true);
  update public.event_requests
  set request_status=p_request_status,
      operational_status=p_operational_status,
      manager_notes=left(coalesce(p_notes,''),10000)
  where id=p_event_id;
  get diagnostics updated_count = row_count;
  return updated_count=1;
end;
$$;
revoke all on function public.vc_management_update(text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.vc_management_update(text,uuid,text,text,text) to anon,authenticated;

-- Rotate the code at any time using SQL Editor (do not publish your chosen code):
-- update private.vc_pilot_access
-- set code_hash=extensions.crypt('YOUR_NEW_PRIVATE_CODE',extensions.gen_salt('bf'))
-- where name='manager';

-- Before public rollout, replace shared code with distinct admin identities,
-- rate limits, auditing tied to user identities, and optional MFA.
