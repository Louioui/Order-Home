# Order Home

A native SwiftUI dinner companion for iPhone and iPad. Build a household table, nominate dinner, find a family favorite or a couple match, and carry the winning order into the kitchen.

This project implements a complete **local, single-device dinner workflow** from the supplied architecture. It runs without account setup, API keys, paid services, or an internet connection. People at the same table take turns choosing their profile to vote. A clearly labeled sample kitchen is available for exploring the app.

## Open and run

1. Open `OrderHome.xcodeproj` in Xcode 16 or later. The project was created and verified using Xcode 27.
2. Select the **OrderHome** scheme and an iPhone or iPad simulator running iOS 17 or later.
3. Press **Run**. Create your kitchen or choose the sample table.

For a physical device, select your Apple development team in the OrderHome target's **Signing & Capabilities**, choose a unique bundle identifier if required, and run on your connected device. Signing credentials are not included.

To run the automated checks, choose **Product → Test** with the same scheme and simulator. From Terminal, a corresponding command is:

```sh
xcodebuild test \
  -project OrderHome.xcodeproj \
  -scheme OrderHome \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Choose an available simulator name on your Mac. No third-party Swift packages are required.

Verified on October 14, 2026 with Xcode 27 and an iPhone 18 Pro simulator running iOS 27: **17 tests passed, 0 failed, 0 skipped** in 31.017 seconds. The automated suite covers voting and attendance rules, couple matching, deadlines, cooking progress and timer persistence, ingredient scaling, corrupt saves, saved-link validation and persistence, and leaving the sample kitchen without affecting a personal kitchen or losing saved creator links. The optional database migration and its security/workflow smoke checks also passed against an isolated local PostgreSQL database. Hosted Supabase, physical-device signing, remote notifications, and multi-device behavior are outside those checks.

A CodeRabbit review of a 34-file source snapshot returned **0 findings**. A manual review then identified and fixed a voting-sheet transition when opening a poll was rejected. Final UI refinements and the guarded sample-kitchen exit were compiled in the passing 17-test run; that run is separate from the earlier review snapshot.

## What works

- **Household setup:** a personal kitchen, Family Table or Table for Two, local profiles, attendance, roles, and order notes.
- **Dinner board:** nominate up to five dishes from the included recipe collection, remove nominations, and open voting with at least two choices.
- **Family reactions:** Craving this = 2, I'm down = 1, Pass tonight = 0. Scores include attending diners only. Ties prefer fewer passes, then earlier nomination order. The app locks the winner when every attending diner has reacted to every dish. The chef can also confirm from submitted reactions. Deadline checks run while the app is open and when it returns to the foreground.
- **Couple matching:** two attending people must both explicitly love the same recipe. Incompatible choices leave the poll open so partners can change their reactions. A deadline does not fabricate a couple match.
- **Kitchen ticket:** the winning dish, true diner count, per-person notes, scaled ingredient quantities, and missing groceries that can be shared through the system share sheet.
- **Chef Studio:** ingredients, recipe steps, progress, a screen-awake cooking experience, and a countdown timer whose absolute end date survives closing the app. The dinner bell marks the meal served on this device.
- **House Menu:** browse included recipes, inspect instructions, keep favorite dishes, and save secure YouTube, TikTok, or Instagram recipe links. Saved links can be nominated; their ingredients and method remain in the original source.
- **Local persistence:** the kitchen, votes, attendance, notes, favorite recipes, ingredient checklists, and cooking progress are saved atomically in the app's Application Support directory.

To save a social recipe, open **House menu**, tap **Save a recipe link**, enter a recipe name, paste a secure YouTube, TikTok, or Instagram URL, and choose **Save to my house menu**. The saved card can be nominated for tonight alongside the included dishes.

The photo-backed recipe collection ships inside the app. Saved social links do not scrape or invent ingredient quantities, instructions, prep times, or thumbnails. Recipe quantities and steps are editable in `OrderHome/Models/RecipeCatalog.swift`. Dietary preferences and member notes are displayed for the chef; they do not automatically validate recipe ingredients or substitutions.

## Connected features and scope

The architecture also describes a distributed product. The following require a connected implementation and deployment; the current app does not pretend to provide them:

| Feature | Current implementation | Remaining connection |
| --- | --- | --- |
| Family accounts and invitations | Local household profiles | Sign in with Apple/Supabase Auth, secure invitation redemption, real users |
| Shared voting and co-op cooking | Complete workflow on one device | Supabase client, authenticated RPC calls, Realtime subscriptions, conflict handling |
| Recipe search and social import | Included recipes and locally saved social links | Licensed provider proxy, search/hydration/cache workers, supported social metadata import |
| Poll and grocery sharing | System share sheet | HTTPS Universal Links, hosted previews, shared poll resolution |
| Recipe video | Recipe source handoff | Verified video selection and supported embedded player |
| Live Activities/Dynamic Island | Cooking progress inside the app | ActivityKit attributes, Widget extension, entitlements, server update tokens |
| Dinner bell | Local served state, foreground chime, and haptic feedback | Device registration, APNs delivery, notification permission, remote sound assets |
| iMessage voting | Shareable text | Dedicated Messages extension and connected poll state |
| Watch companion and purchases | Not included | Separate targets and product requirements |

Custom `orderhome://` routing is registered for local navigation. It is not an HTTPS Universal Link, cannot install the app, and does not grant access to another household. Sharing local app state does not synchronize it to another phone.

Cooking timers retain their absolute end date after relaunch and can schedule a local notification when notification permission is granted. If alerts are unavailable, the in-app countdown still works. The app cannot execute deadline processing while it is terminated. No advertising, analytics, tracking, or external recipe credentials are included.

## Project layout

```text
OrderHome/
  OrderHomeApp.swift             App entry and navigation
  Models/                       Codable domain models and included recipes
  Services/OrderHomeStore.swift  Dinner rules and atomic local persistence
  Views/                        SwiftUI screens and visual system
  Assets.xcassets/               Bundled recipe photos and app assets
OrderHomeTests/                 Workflow, scoring, persistence, and scaling tests
supabase/migrations/           Optional connected-backend database baseline
supabase/tests/                Disposable-database security/workflow smoke test
docs/                          Architecture and connection notes
```

The Xcode project uses synchronized folder groups. New source or asset files added inside `OrderHome/` are automatically included in the app target; test files inside `OrderHomeTests/` belong to the test target.

## Optional backend baseline

`supabase/migrations/202610150001_initial_order_home.sql` translates the architecture into a guarded PostgreSQL/Supabase foundation. It is included as a future integration starting point and is not required to run the iOS app. See `docs/Backend.md` for its behavior, limitations, and validation procedure.

This repository contains no deployed backend, associated domain, Apple developer configuration, external API keys, or push credentials. Do not place provider API keys or a Supabase service-role key in an iOS bundle.
