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


## Temporary management access: shared code (pilot only)

The management frontend now asks for an access code instead of email/password. The code is **never embedded in the public repository**. The Supabase SQL Editor must be used to apply `supabase/shared-code-pilot.sql`, then privately set the code with:

```sql
update private.vc_pilot_access
set code_hash = extensions.crypt('REPLACE_WITH_YOUR_CODE', extensions.gen_salt('bf'))
where name = 'manager';
```

Replace the placeholder directly in your private SQL Editor; **never commit the code to GitHub or place it in config.js**. Until these database functions exist, the page cannot validate a code. There is no client-side security bypass. Code is held only in page memory (not localStorage); sign out or refresh to require reentry.

**Important limitations:** Anyone holding the code can see personal contact and event information and change all event statuses. There is currently no per-person audit or server-side abuse throttling for guesses. Pilot use only: rotate the code regularly, do not broadly distribute it, and migrate to per-user authentication before public operational use. The previous individual-manager Supabase configuration remains in the database but is not used by the pilot login form.

## Data access and security

- Public users do not sign in, can submit requests only (INSERT), and cannot SELECT/UPDATE/DELETE events.
- Pilot management uses a shared access code verified by restricted server-side PostgreSQL RPC functions. Individual Supabase Auth remains configured for future use.
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


## Requester flow refinements (October 2026)

- Public calendar defaults to the month containing the first eligible D+20 date and has a smaller, two-column layout with explanatory copy. Non-eligible days display faded red diagonal stripes.
- Requester can request separate setup and dismantling dates; both are pending review, not reservations.
- The space choices now include both `Plenária + Studio` and independent `Studio`.
- Basic needs no longer present speakers, external guests, live streaming, transportation, or accessibility support as standalone options. AV outcome questions remain available conditionally.
- Agency question is now "Você já tem uma agência de eventos?"; selecting No shows guidance about potential partner referrals.
- The Supabase migration `request_setup_dates_and_notification_outbox` has been applied: new setup/dismantling fields and private email outbox plus separate manager-notification recipients.
- **Emails are not being sent yet.** Requests create pending outbox records only. Add named manager email recipients, a verified Resend sending domain and a protected sender/worker (with retries) before claiming email delivery. Do not put API keys or email recipient lists in browser code.

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
