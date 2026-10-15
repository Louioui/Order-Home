# Shared kitchens: implementation and deployment

The connected milestone adds an authenticated member identity, invitations and a
single authoritative dinner ticket. The database migration and iPhone client must
both be configured against the same Supabase **development** project before two
physical phones can share data. Local PostgreSQL verification does not establish
a hosted Supabase connection or configure Apple services.

## Apply the database

Apply these migrations in filename order using the project's migration workflow:

1. `supabase/migrations/202610150001_initial_order_home.sql` — baseline tables,
   household isolation and the atomic dinner workflow.
2. `supabase/migrations/202610150002_shared_kitchens.sql` — invitations, snapshots,
   guarded member operations, concurrency protection and deadline resolution.
3. `supabase/migrations/20261015032424_bundled_recipes.sql` — all eight original
   recipes included in the iPhone app, with matching IDs, ingredients and steps.

The migrations assume standard Supabase `auth.users`, `auth.uid()`, `anon` and
`authenticated` resources. They grant the trusted deadline worker to
`service_role` when that role exists. Never put the service role key or any secret
key in the application bundle.

The recipe migration contains only the app's original cooking content. Images
remain bundled in iOS. Social links and arbitrary client recipe imports are not
uploaded into the shared global cache; a nominated recipe must already exist in
the curated database catalog and have complete cooking instructions.

## Configure the iPhone client and authentication

The app reads these values from its bundled Info.plist:

| Key | Value |
| --- | --- |
| `SUPABASE_URL` | The project's HTTPS base URL. |
| `SUPABASE_PUBLISHABLE_KEY` | Its public `sb_publishable_…` key. A legacy anon key is supported; secret/service role keys are rejected. |
| `ORDER_HOME_INVITE_BASE_URL` | Optional HTTPS invitation landing page URL, once a domain is configured. |
| `ORDER_HOME_APPLE_SIGNIN_ENABLED` | Boolean; enable only after the Apple provider, app identifier and Sign in with Apple entitlement are configured. |

Email authentication uses a numeric one-time code. In Supabase Auth's email
templates, ensure the sign-in/Magic Link email displays `{{ .Token }}` so the
person can enter the code in the app. A template containing only
`{{ .ConfirmationURL }}` does not support the app's code-entry flow. Verify email
delivery and production SMTP separately before a family beta.

Native Apple sign-in exchanges Apple's identity token and a cryptographic nonce
with Supabase Auth. It requires Apple provider setup and native signing
entitlements. Numeric email sign-in does not require an Apple developer team or
an authentication redirect URL. Invitation routing is separate from
authentication; iOS must receive the invite URL in the configured app scheme.

## Invitations and household identity

Only the kitchen owner can issue or revoke invitations. `create_kitchen_invite`
returns a random 64-hex token, household name and seven-day expiry exactly once.
The database stores the token's SHA-256 hash inside the unexposed
`order_home_private` schema. Authenticated and anonymous clients have neither
schema nor table privileges there; RLS is also enabled as defense in depth.

Redemption requires an authenticated identity and a display name. The token is
single use. Retrying a successful redemption from the same account returns the
same kitchen ID, allowing recovery if the first network response was lost. An
expired, revoked, unknown or already redeemed token cannot reveal household
details to a new caller. Possession of an invitation is authority to join; send
it only to the intended person. The app presents the share sheet; it does not
message people automatically.

Joins, mode changes, opening a dinner and opening voting share a household row
lock. Two people cannot claim the last seat in Table for Two. Joining is allowed
during nominations and between dinners. It is rejected once voting, a confirmed
ticket or cooking is in progress, keeping the voter/portion roster stable.
The owner may change Family Table to Table for Two only with at most two members
and before voting begins. A couple poll requires exactly two members.

## Read contract

`my_kitchens()` returns an array of `{id,name,mode,owner_user_id}` objects for the
authenticated account's memberships.

`kitchen_snapshot(p_household_id)` returns one JSON object:

```json
{
  "household": {"id":"uuid","name":"Our kitchen","mode":"family","owner_user_id":"uuid"},
  "members": [{"id":"uuid","user_id":"uuid","display_name":"Alex","avatar_emoji":"🍽️","default_role":"head_chef","dietary_tags":[]}],
  "session": null,
  "pitches": [],
  "votes": [],
  "orders": []
}
```

With a dinner, `session` contains a raw `dinner_sessions` row; pitches, votes and
orders contain the matching raw table rows. The latest active dinner takes
precedence over served dinners. With no active dinner, the latest served dinner
is returned. Without dinner history, `session` is JSON null and the arrays are
empty. Members include user IDs so the client can select the authenticated
person without allowing impersonation.

One SQL statement constructs the entire response under one database snapshot.
A caller must belong to the kitchen. Any client refresh, reconnect or change
notification should reload this snapshot; never determine the winner from local
votes. UUIDs are strings and dates are PostgreSQL ISO 8601 timestamps, potentially
with fractional seconds.

## Write contract

All parameters use the exact names below for PostgREST RPC calls. Existing
baseline RPCs remain available; clients have no direct write grants on tables.

| RPC | Arguments | Returns / authorization |
| --- | --- | --- |
| `create_kitchen` | `p_name`, `p_mode`, `p_display_name` | Kitchen UUID; authenticated caller becomes owner and first member. |
| `create_kitchen_invite` | `p_household_id` | `{token,expires_at,household_name}`; owner only. |
| `join_kitchen` | `p_token`, `p_display_name` | Kitchen UUID; authenticated token holder. |
| `revoke_kitchen_invite` | `p_household_id`, `p_token` | Void; owner only, idempotent. |
| `update_own_profile` | `p_household_id`, `p_display_name`, `p_avatar_emoji`, `p_dietary_tags` | Void; changes only the caller's member row, never authority or identity. |
| `set_kitchen_mode` | `p_household_id`, `p_mode` | Void; owner only, roster/stage checks. |
| `open_dinner` | `p_household_id`, `p_deadline`, `p_poll_mode` (default `open_cravings`) | Session UUID; caller is a member and becomes this dinner's chef. Deadline must be future and within seven days. |
| `add_pitch` | `p_session_id`, `p_recipe_id`, `p_note` (default empty) | Pitch UUID; member during nominations, chef only in `chefs_menu`. |
| `remove_pitch` | `p_session_id`, `p_recipe_id` | Void; the nominator or dinner chef, during nominations. |
| `save_diner_preferences` | `p_session_id`, `p_eating_home`, `p_tags`, `p_note` | Void; own attendance and notes while nominations/voting remain open. |
| `start_voting` | `p_session_id` | Void; dinner chef; snapshots all members while preserving their saved preferences. |
| `submit_order` | `p_session_id`, `p_reactions`, `p_eating_home` (default true), `p_tags` (default empty array), `p_note` (default empty) | Winning pitch UUID or null; authenticated member's atomic whole ballot. |
| `close_voting` | `p_session_id` | Winning pitch UUID; chef only; cannot invent a couple match. |
| `expire_voting` | `p_session_id` | Winning pitch UUID or null; member only, resolves only after the deadline. |
| `extend_voting` | `p_session_id`, `p_deadline` | Void; chef only; strictly later than current deadline, future and within seven days. |
| `cancel_dinner` | `p_session_id` | Void; chef only; removes an unconfirmed nominations/voting poll and its associated draft orders/votes. A confirmed/cooking/served dinner cannot be cancelled. |
| `advance_kitchen` | `p_session_id`, `p_status`, `p_step_index` (default 0), `p_missing_groceries` (default empty array) | Void; dinner chef; forward transitions and recipe step bounds enforced. |
| `close_due_dinners` | None | Count of newly resolved sessions; trusted service role / migration owner only. |

`p_reactions` is an array of `{"pitch_id":"uuid","weight":2}` objects, exactly
one per nominated dish for an attending diner. Family weights are 0, 1 or 2;
couples use 0 or 2. A skipping diner submits `p_eating_home=false` and contributes
no votes. Saving preferences changes the order back to a draft: it clears that
person's submitted timestamp and previous ballot until a full order is submitted
again. Local selection changes should be collected as drafts until the user
submits. They must not masquerade as persisted votes.

Session row locks serialize full submissions and winner selection. Every
snapshotted member submitting resolves a family dinner automatically. A chef can
close a family poll early, and a deadline can resolve submitted votes even when
some members did not vote. Family ranking uses total score, then fewer pass
reactions, then nomination time and UUID. A couple requires mutual love from two
attending, submitted orders; no deadline or chef action creates a fallback match.
Empty or no-match polls stay open for a chef to extend or cancel.

## Deadlines while phones are closed

If `pg_cron` is already enabled, the migration installs the named job
`order-home-close-due-dinners`, which calls `select public.close_due_dinners()`
every minute. If Cron is unavailable, the migration emits a notice and leaves
the worker function installed. Enable Supabase Cron in the development project,
then run as the database owner:

```sql
select cron.schedule(
  'order-home-close-due-dinners',
  '* * * * *',
  'select public.close_due_dinners()'
);
```

Confirm the job appears in `cron.job` and inspect `cron.job_run_details` after a
due poll. Polling clients may call `expire_voting` as a recovery path, but that
does not replace a deployed scheduler when every phone is closed. The worker
locks due sessions with `SKIP LOCKED`, uses the same internal winner resolver,
and is safe to call repeatedly.

## Verification

Run `python3 supabase/tests/run_local_tests.py` with local PostgreSQL tools
(`initdb`, `pg_ctl`, `psql`) on PATH. The runner creates a fresh temporary cluster,
binds only to loopback, applies every migration, runs both regression scripts,
then stops and removes the cluster. It never connects to a hosted database.

The checks cover family scoring and tie-breaking, couple matching/no-match,
authenticated household isolation, denied anonymous/direct/internal writes,
invitation expiry/revocation/single use/idempotent retry, self-only profile
updates, attendance preservation, exact member snapshots, identical winning
tickets for two accounts, stale-ballot rejection, recipe step bounds,
deadline/member/worker resolution, extension and safe cancellation.

Four checks use separate concurrent database processes: two invitations racing
for the last couple seat, two identities redeeming one token, two simultaneous
full ballots producing one ticket, and joining while voting is opened. The final
voter roster must exactly equal the household membership regardless of which
request acquires the lock first.

Supabase CLI database advisors also passed against an isolated test database
without reported issues. Before a beta, repeat advisors against the real
development project and verify real email/Apple authentication, invitations on
two physical phones, realtime/reconnect behavior, offline error handling and the
Cron job. Local auth fixtures exercise database authorization, not JWT issuance.
No APNs device registration, remote push delivery or Apple distribution service
is provided by these migrations.

Current source references: [Supabase database functions](https://supabase.com/docs/guides/database/functions),
[row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Cron quickstart](https://supabase.com/docs/guides/cron/quickstart), and
[the September 2026 PostgreSQL upgrade notice](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes).
