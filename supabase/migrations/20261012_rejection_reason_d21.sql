-- Applied to Supabase project ndxirudvsauunxaxbkvc as migration admin_rejections_d21_notice_v3.
-- Preserves historical requests submitted under the old D+20 rule.
alter table public.event_requests add column if not exists rejection_reason text;
select set_config('app.vc_manager_verified','true',true);
update public.event_requests set rejection_reason='Motivo não registrado anteriormente.'
where request_status='Rejected' and nullif(trim(coalesce(rejection_reason,'')),'') is null;
alter table public.event_requests drop constraint if exists vc_rejection_reason_required;
alter table public.event_requests add constraint vc_rejection_reason_required
check (request_status <> 'Rejected' or nullif(trim(rejection_reason),'') is not null);
create or replace function public.vc_management_update(
  p_code text,p_event_id uuid,p_request_status text,
  p_operational_status text,p_notes text,p_rejection_reason text
) returns boolean language plpgsql security definer set search_path=''
as $$
declare updated_count integer;
begin
  if not private.vc_valid_code(p_code) then return false; end if;
  if p_request_status not in ('Requested','Under review','Tentatively scheduled','Confirmed','Rejected','Cancelled') then return false; end if;
  if p_operational_status not in ('Not started','Upcoming','In progress','Completed') then return false; end if;
  if p_request_status<>'Confirmed' and p_operational_status<>'Not started' then return false; end if;
  if p_request_status='Rejected' and length(trim(coalesce(p_rejection_reason,'')))=0 then return false; end if;
  perform set_config('app.vc_manager_verified','true',true);
  update public.event_requests
  set request_status=p_request_status,operational_status=p_operational_status,
      manager_notes=left(coalesce(p_notes,''),10000),
      rejection_reason=case when p_request_status='Rejected' then left(trim(p_rejection_reason),5000) else null end
  where id=p_event_id;
  get diagnostics updated_count=row_count;
  return updated_count=1;
end;
$$;
revoke all on function public.vc_management_update(text,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.vc_management_update(text,uuid,text,text,text,text) to anon,authenticated;
drop function if exists public.vc_management_update(text,uuid,text,text,text);
alter table public.event_requests drop constraint if exists date_notice;
-- NOT VALID preserves old requests while enforcing the new rule on future writes.
alter table public.event_requests add constraint date_notice
check (event_date >= ((created_at at time zone 'America/Sao_Paulo')::date + 21)) not valid;
