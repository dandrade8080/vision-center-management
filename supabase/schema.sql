-- BYD Vision Center MVP — Supabase PostgreSQL schema
-- Execute in Supabase SQL Editor. Never expose service_role keys in the browser.
create extension if not exists pgcrypto;

create table if not exists public.manager_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.manager_users enable row level security;
revoke all on public.manager_users from anon, authenticated;
grant select on public.manager_users to authenticated;
create policy "Managers may read their own membership" on public.manager_users
for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.is_vision_center_manager()
returns boolean language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.manager_users m where m.user_id = (select auth.uid())); $$;
revoke all on function public.is_vision_center_manager() from public;
grant execute on function public.is_vision_center_manager() to authenticated;

create table if not exists public.event_requests (
  id uuid primary key default gen_random_uuid(),
  reference text unique not null default ('VC-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  requester_name text not null check (length(trim(requester_name)) between 2 and 200),
  requester_email text not null check (length(requester_email) between 5 and 254),
  requester_phone text,
  requester_origin text not null default 'Internal',
  company_unit text,
  event_name text not null check (length(trim(event_name)) between 2 and 240),
  event_type text,
  event_description text,
  estimated_attendees integer check (estimated_attendees is null or estimated_attendees > 0),
  audience text,
  event_date date not null,
  alternate_date date,
  start_time time not null,
  end_time time not null,
  space_ids text[] not null default '{}',
  needs text[] not null default '{}',
  av_brief jsonb not null default '{}'::jsonb,
  special_requirements text,
  agency text,
  request_status text not null default 'Requested' check (request_status in ('Requested','Under review','Tentatively scheduled','Confirmed','Rejected','Cancelled')),
  operational_status text not null default 'Not started' check (operational_status in ('Not started','Upcoming','In progress','Completed')),
  manager_notes text,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint date_notice check (event_date >= ((created_at at time zone 'America/Sao_Paulo')::date + 20)),
  constraint valid_time check (end_time > start_time),
  constraint operational_after_confirmation check (operational_status = 'Not started' or request_status = 'Confirmed')
);
create index if not exists event_requests_schedule_idx on public.event_requests(event_date, start_time);
create index if not exists event_requests_status_idx on public.event_requests(request_status);
alter table public.event_requests enable row level security;
revoke all on public.event_requests from anon, authenticated;
grant insert on public.event_requests to anon, authenticated;
grant select, update on public.event_requests to authenticated;

-- Public form can INSERT only. It cannot SELECT, UPDATE, or DELETE any event.
-- DB trigger below overrides any public attempt to set a privileged status.
create policy "Anyone may submit a request" on public.event_requests
for insert to anon, authenticated with check (true);
create policy "Only managers may view requests" on public.event_requests
for select to authenticated using (public.is_vision_center_manager());
create policy "Only managers may update requests" on public.event_requests
for update to authenticated using (public.is_vision_center_manager())
with check (public.is_vision_center_manager());

create or replace function public.guard_event_request()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.request_status := 'Requested';
    new.operational_status := 'Not started';
    new.manager_notes := null;
    new.updated_by := null;
  elsif not public.is_vision_center_manager() then
    raise exception 'Only managers can update event requests';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists event_request_guard on public.event_requests;
create trigger event_request_guard before insert or update on public.event_requests
for each row execute function public.guard_event_request();

create table if not exists public.event_history (
  id bigint generated always as identity primary key,
  event_id uuid not null references public.event_requests(id) on delete cascade,
  actor uuid references auth.users(id),
  previous_request_status text,
  new_request_status text,
  previous_operational_status text,
  new_operational_status text,
  changed_at timestamptz not null default now()
);
alter table public.event_history enable row level security;
revoke all on public.event_history from anon, authenticated;
grant select on public.event_history to authenticated;
create policy "Only managers read history" on public.event_history
for select to authenticated using (public.is_vision_center_manager());

create or replace function public.log_event_status_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.request_status is distinct from new.request_status
     or old.operational_status is distinct from new.operational_status then
    insert into public.event_history
    (event_id, actor, previous_request_status, new_request_status, previous_operational_status, new_operational_status)
    values (new.id, auth.uid(), old.request_status, new.request_status, old.operational_status, new.operational_status);
  end if;
  return new;
end $$;
drop trigger if exists event_history_trigger on public.event_requests;
create trigger event_history_trigger after update on public.event_requests
for each row execute function public.log_event_status_change();

-- IMPORTANT: Public INSERT can be abused by bots. Enable Supabase rate limiting,
-- CAPTCHA/Turnstile through a server-side endpoint before publicly sharing widely.
-- Create first admin in Supabase Auth dashboard, then run (with the actual auth.users UUID):
-- insert into public.manager_users(user_id) values ('YOUR-AUTH-USER-UUID');
