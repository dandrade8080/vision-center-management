-- Internal prebookings: separate from anonymous event requests.
-- Admin creates a hold independently from the public D+21 intake rules.
create table if not exists public.vc_internal_bookings (
  id uuid primary key default gen_random_uuid(),
  event_name text not null check (length(trim(event_name)) between 2 and 240),
  event_date date not null,
  start_time time not null,
  end_time time not null,
  setup_date date,
  teardown_date date,
  space_ids text[] not null,
  responsible_name text not null check (length(trim(responsible_name)) between 2 and 200),
  responsible_email text,
  responsible_phone text,
  company_unit text,
  notes text,
  status text not null default 'Tentative'
    check(status in ('Tentative','Confirmed','Cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vc_internal_booking_time check (start_time<end_time),
  constraint vc_internal_booking_spaces check (cardinality(space_ids)>0),
  constraint vc_internal_booking_dates check (
    (setup_date is null or setup_date<=event_date) and
    (teardown_date is null or teardown_date>=event_date)
  )
);
create index if not exists vc_internal_bookings_date_idx on public.vc_internal_bookings(event_date);
alter table public.vc_internal_bookings enable row level security;
revoke all on public.vc_internal_bookings from public, anon, authenticated;
-- No direct public table access; only RPCs below can access booking contacts.
create or replace function public.vc_internal_bookings_list(p_code text)
returns jsonb language plpgsql security definer set search_path=''
as $$
begin
  if not private.vc_valid_code(p_code) then return null; end if;
  return coalesce(
    (select jsonb_agg(to_jsonb(b) order by b.event_date,b.start_time)
     from public.vc_internal_bookings b),
    '[]'::jsonb);
end;
$$;
revoke all on function public.vc_internal_bookings_list(text) from public,anon,authenticated;
grant execute on function public.vc_internal_bookings_list(text) to anon,authenticated;

create or replace function public.vc_internal_booking_save(
  p_code text, p_event_name text, p_date date, p_start time, p_end time,
  p_spaces text[], p_responsible text, p_email text, p_phone text,
  p_company text, p_notes text, p_status text, p_setup date, p_teardown date,
  p_booking_id uuid default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare ret uuid;
begin
  if not private.vc_valid_code(p_code) then raise exception 'Invalid manager access'; end if;
  if p_status not in ('Tentative','Confirmed','Cancelled')
     or p_date is null or p_start is null or p_end is null or p_start>=p_end
     or cardinality(p_spaces)<1 or p_spaces is null
     or nullif(trim(coalesce(p_event_name,'')),'') is null
     or nullif(trim(coalesce(p_responsible,'')),'') is null
     or (p_setup is not null and p_setup>p_date)
     or (p_teardown is not null and p_teardown<p_date)
    then raise exception 'Incomplete or invalid booking information'; end if;
  if p_booking_id is null then
    insert into public.vc_internal_bookings
      (event_name,event_date,start_time,end_time,space_ids,responsible_name,
       responsible_email,responsible_phone,company_unit,notes,status,setup_date,teardown_date)
    values
      (left(trim(p_event_name),240),p_date,p_start,p_end,p_spaces,left(trim(p_responsible),200),
       nullif(left(trim(p_email),254),''),nullif(left(trim(p_phone),80),''),
       nullif(left(trim(p_company),200),''),left(coalesce(p_notes,''),10000),
       p_status,p_setup,p_teardown)
    returning id into ret;
  else
    update public.vc_internal_bookings
    set event_name=left(trim(p_event_name),240),event_date=p_date,start_time=p_start,
        end_time=p_end,space_ids=p_spaces,responsible_name=left(trim(p_responsible),200),
        responsible_email=nullif(left(trim(p_email),254),''),
        responsible_phone=nullif(left(trim(p_phone),80),''),
        company_unit=nullif(left(trim(p_company),200),''),
        notes=left(coalesce(p_notes,''),10000),status=p_status,
        setup_date=p_setup,teardown_date=p_teardown,updated_at=now()
    where id=p_booking_id returning id into ret;
    if ret is null then raise exception 'Booking not found'; end if;
  end if;
  return ret;
end;
$$;
revoke all on function public.vc_internal_booking_save(
 text,text,date,time,time,text[],text,text,text,text,text,text,date,date,uuid
) from public,anon,authenticated;
grant execute on function public.vc_internal_booking_save(
 text,text,date,time,time,text[],text,text,text,text,text,text,date,date,uuid
) to anon,authenticated;
