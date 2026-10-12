# BYD Vision Center — Event Request MVP

## Current status

This repository hosts a responsive multilingual **public event-request form** (Português default, English, 简体中文) and an **authenticated management portal**. Its static frontend runs on Vercel, backed by Supabase Auth + PostgreSQL / Row Level Security (RLS).

**The site is NOT yet ready to accept actual requests until Supabase has been provisioned and configured.** Until configured, the submit button explicitly prevents submission rather than presenting a fake success.

## URLs

- Public requester: `https://vision-center-management.vercel.app/`
- Manager login: `https://vision-center-management.vercel.app/admin` (rewrite configured in `vercel.json`)

These paths can be linked from a future BYD landing page.

## First-time setup

1. Create a Supabase project in the BYD-approved account/region. Confirm BYD security, legal, data-processing, retention and LGPD requirements before storing identifiable requester data.
2. Open Supabase **SQL Editor** and execute `supabase/schema.sql`. Verify the tables `manager_users`, `event_requests` and `event_history` and their RLS policies.
3. In **Supabase Auth**, create the initial manager user by invite or via the dashboard. Disable open email signups if managers are to be provisioned by admins only. Set your production **Site URL** and **redirect URLs** to the Vercel domain, if using email invitation/recovery.
4. In Supabase **SQL Editor**, find the manager's auth user UUID and run:
   ```sql
   insert into public.manager_users (user_id) values ('REPLACE-WITH-AUTH-USER-UUID');
   ```
   Never assign this record from browser code. Additional managers must be provisioned by an authorized administrator.
5. Copy the project's **Project URL** and **publishable/anon public key** (NOT service_role, secret or database password) into `config.js`. Because this is a static app, these two values are publicly visible; security depends on RLS, not on hiding the public key.
6. Commit the updated `config.js` to GitHub. Vercel automatically deploys changes from `main`.
7. Verify anonymously that a requester can **INSERT** one event but cannot read any events or manager data. Verify the manager can sign in and change the request status from Requested → Tentatively scheduled → Confirmed, and view changes in Events and Calendar.
8. Add CAPTCHA/Turnstile and rate limiting via a server-side submission endpoint **before distributing the link broadly**. The current anonymous insert API is intentionally an MVP bootstrap and has no bot protection yet.

## Data access and security

- Public users do not sign in, can submit requests only (INSERT), and cannot SELECT/UPDATE/DELETE events.
- Management users use Supabase Auth with email/password, then must exist in `manager_users`.
- Managers can SELECT and UPDATE events; Postgres logs status transitions in `event_history`.
- Database trigger forces `Requested` and `Not started` on insert, preventing a public client from asserting approval.
- Public calendar shows date eligibility (D+20) and **does not reveal event data**. A selectable date is not an automatic reservation.
- A demo switch between user/manager with publicly readable localStorage records has been removed. An individual browser is no longer the event database.

## Supported operations

- Five-stage request: Contact → Event → Date and spaces → Needs (conditional AV briefing) → Review.
- Five independent event spaces (labels preserved as supplied in the brief), no invented capacity information.
- Multilingual prompts and answer choices (Portuguese, English, Simplified Chinese).
- Admin dashboard, event list, calendar, space/time schedule, event details, internal notes and status changes.
- Independent request status and operational status. Financial/budget features are intentionally out of scope.

## Known limitations / next work

- Supabase project and initial manager authentication must be set up by authorized account owner.
- This frontend imports Supabase JS from an external ESM CDN; for a hardened release, pin/bundle dependencies under a build process and add CSP.
- The public request form still requires CAPTCHA/server-side rate limits before sending widely.
- Calendar is read-only for requester; no public availability/conflict data is exposed.
- No real email notifications, file uploads, secondary-date handling in the management calendar, conflict resolution, automated status transitions, or corporate SSO yet.
- Basic localization is provided for requester questions and common answers; some manager backend status labels remain in English by design and some option terminology needs business review.
- Production access, role provisioning, database backup/monitoring and LGPD policies require IT ownership.

## Future landing-page handoff

CTA **Solicite seu evento** → `/`, no required query parameters. The same domain `/admin` is only for managers. An anonymous submission inserts a record into `public.event_requests` and displays its client-generated unique `VC-XXXXXXXXXX` reference. No public API to retrieve another person's request is exposed. Avoid embedding the admin portal as an unauthenticated iframe. For enterprise SSO and branded landing-page embedding, design appropriate session/security boundaries later.

**The requester describes WHAT they need; the Vision Center team decides HOW to deliver it.**
