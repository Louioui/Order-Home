# Optional connected backend

The iOS app currently uses `OrderHomeStore` and a local JSON file. The SQL baseline in this repository is independent of that store. Applying the migration does not connect the app or enable account, invite, notification, or synchronization behavior.

## Data model

The migration preserves the architecture's household, member, recipe cache, dinner session, pitch, and vote entities and separates **diner_orders** into a seventh table. A diner order contains attendance and customization once per person per session. Dish reactions are separate rows. This prevents a person who reacts to five dishes from being counted five times for portions or notifications.

Composite foreign keys prevent members, pitches, orders, and winners from crossing household or session boundaries. A partial unique index permits at most one unfinished dinner per household. Public recipe cache rows must contain only licensed provider content. Private imports and household notes need a separate household-scoped resource when implemented.

All seven tables have row-level security. Authenticated clients can select only their own household's rows, except for the public provider recipe cache. Anonymous users have no table access. Supported mutations use narrowly scoped `SECURITY DEFINER` functions with a fixed empty search path, qualified object references, and caller checks. Authenticated clients have no direct table write grants. The internal ticket resolver is not executable by API clients.

## RPC contract

| Function | Caller and behavior |
| --- | --- |
| `create_kitchen(name, mode, display_name)` | Authenticated user; creates a household and its first member atomically. |
| `open_dinner(household_id, deadline, poll_mode)` | Existing member; becomes the chef for this session. |
| `add_pitch(session_id, recipe_id, note)` | Existing member during pitching; chef only for `chefs_menu`. Serializes nominations and caps at five. |
| `start_voting(session_id)` | Session chef; requires two to five pitches and a future deadline. Snapshots household members into one order per member. Table for Two requires exactly two members. |
| `submit_order(session_id, reactions, eating_home, tags, note)` | Existing member included when voting opened; submits attendance, notes, and all dish reactions in one transaction. May update before the poll locks. |
| `close_voting(session_id)` | Session chef; locks a valid family winner or an existing mutual couple match. |
| `advance_kitchen(session_id, status, step_index, missing_groceries)` | Session chef; validates the forward ticket → cooking → served sequence and recipe step bounds. Step indices are zero-based. |

A reaction payload has this form:

```json
[
  { "pitch_id": "<first-pitch-uuid>", "weight": 2 },
  { "pitch_id": "<second-pitch-uuid>", "weight": 1 }
]
```

An attending person must submit one unique reaction for every pitch. Weights are 0, 1, or 2 in Family Table; Table for Two accepts 0 or 2. A person skipping dinner does not contribute votes. Family ranking uses the sum of weights, then the fewest pass reactions, then pitch creation order and ID for a deterministic final tie. Couple matching requires two attending people to submit love reactions for the same pitch.

Submissions and winner resolution acquire a lock on the same dinner session row. Concurrent submissions and closes therefore serialize; a later action observes the already locked status instead of replacing the winner. A family poll automatically resolves after every snapshotted person has submitted, including a skip order. It can also be closed early by the chef. No votes or no attending diners yield no ticket. A couple poll without mutual love remains open.

The SQL contract submits a whole order atomically; the local SwiftUI prototype records reactions individually. The connected client must reconcile that difference deliberately rather than send local model snapshots directly to tables.

## Deployment and next implementation steps

Use a development Supabase project first. Apply the migration through the project's migration workflow. It expects the standard Supabase `auth.users`, `auth.uid()`, `anon`, and `authenticated` resources. It adds collaboration tables to the `supabase_realtime` publication if that publication exists. Realtime still requires a deployed project with logical replication and correctly authenticated subscriptions.

Next, implement and validate these connections:

1. Configure Sign in with Apple and Supabase Auth. Map the authenticated user to household membership. Replace local profile switching with the signed-in user's identity.
2. Add a secure invitation service. Invitation tokens must be random, expiring, household scoped, and redeemed transactionally by an authenticated user. Apply owner authorization and Table for Two capacity rules. The baseline intentionally exposes no join-by-household-ID RPC and no public invite codes; until this service exists, only a trusted administrator can provision additional real members.
3. Populate the provider recipe cache through a server worker that stores API keys server-side, validates provider responses and units, observes licensing/caching requirements, and hydrates the winning recipe before cooking. Keep social imports private until the user deliberately shares them.
4. Build a Supabase repository that maps Swift domain values to the RPC contract, subscribes with household filters, reloads authoritative state after reconnect, and handles rejected transitions and stale updates.
5. Add a trusted deadline worker. The current SQL rejects late submissions but does not schedule a job to close a poll. Couple no-match and zero-diner states need explicit product handling. A privileged worker must use the same transaction and membership-independent resolution rules; it must not create a fallback couple winner.
6. Implement remaining app data operations as guarded RPCs: member management, owner permissions, deadline extension/reopening, meal history ratings, household favorites, co-op step checks, and cancellation. They are not present in this baseline.
7. Add server device-token storage and an event/outbox processor for APNs, with appropriate token privacy, retries, idempotency, permission behavior, and per-person attendance filtering. Device tokens are deliberately absent from member rows so one family member cannot read everyone else's tokens.
8. Add HTTPS routing and associated domains, host share previews, then implement ActivityKit/Widget and Messages extensions. Validate behavior across two physical accounts and devices before describing the product as live or synchronized.

Run separate tests for concurrent closes, real JWT authentication, Realtime delivery/reconnection, member changes during an active poll, and Apple entitlements. The local PostgreSQL checks validate relational workflow and permissions; they do not validate any hosted Supabase or Apple service.

## Database smoke checks

`supabase/tests/security_and_workflow.sql` runs inside a transaction and rolls back. It creates three synthetic auth IDs and two test recipes. Run it only against an isolated disposable local database with the migration applied, using the migration owner so it can seed those fixtures. Never use this fixture script against production.

It verifies:

- One attendance record per diner, even with multiple dish reactions.
- A partial family poll stays open; completed votes lock the expected tie-break winner.
- Authenticated clients cannot write tables directly or call the internal resolver.
- A diner cannot advance the chef's cooking state.
- An outsider cannot select another household's private rows or submit an order.
- The chef can advance a hydrated ticket through cooking and served.
- Incompatible couple choices do not create a match; a revised mutual love does.

For a plain local PostgreSQL instance rather than Supabase, provide an isolated test stub for the `auth` schema and the `anon`/`authenticated` roles before applying the migration. The development verification used `auth.uid()` backed by the session's `request.jwt.claim.sub` setting. That stub simulates database identity only and must never be substituted for real Supabase authentication in a deployed app.
