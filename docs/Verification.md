# Verification

Verified October 14, 2026 on the iPhone 18 Pro simulator with iOS 27 and Xcode 27.

- Final automated suite: 35 passed, 0 failed, 0 skipped, about 0.6 seconds of test time (17 dinner-workflow, 8 connected-client, 10 dinner-history).
- Latest app build and launch: succeeded, no compiler warnings. Xcode's "AppIntents metadata extraction skipped" notice is expected because the app uses no App Intents.
- CodeRabbit: 0 findings on an earlier 34-file snapshot; see CodeRabbit-review.txt. The dinner history and rating changes were not reviewed there.
- Earlier, the database migration and workflow/security checks passed in an isolated local PostgreSQL database. They were not re-run for the dinner history update. No hosted service was provisioned or connected.

## Build repair (October 14, 2026)

The committed code did not compile before this update. `CloudKitchenController` created its default Supabase client in a default argument, which Swift treats as non-main-actor, and the client's initializer is main-actor. The default is now created inside the initializer. Separately, six views read `CloudKitchenController` from the SwiftUI environment but the app entry point never created or injected it, which would have crashed at launch. It is now created beside the store and injected, and it restores a saved session, records an invitation link's token, and follows scene-phase changes. Two limits: nothing presents the account sheet from an invitation link yet, and no Supabase URL or key is configured in the build, so none of the connected path ran in testing. Only the app's launch without a crash was confirmed. The README's older "17 tests passed" figure predates the connected-kitchen layer.

## Dinner history walkthrough

Seeded a saved kitchen in the simulator (four diners, a served dinner nobody had rated yet, and three past dinners, one of them for a recipe that no longer exists). Rated tonight's dinner: Alex 😍 and Jamie 🔄 showed as selected, and the dish moved to "Saved to House Menu" and showed a filled heart on House menu. Opened Past dinners: tonight's meal appeared with 😍 1 and 🔄 1 (recorded when first rated, since it was served before history existed), older meals showed their rating counts and dates, and the missing recipe showed a placeholder, "Not rated yet" and no Cook it again button. With tonight's dinner still served, Cook it again was disabled with a hint. After "Start a fresh dinner" it was enabled, and choosing the rigatoni confirmed "Creamy tomato rigatoni is on tonight's board."

Not verified: a physical device, ratings from more than one phone, history in a connected kitchen (by design it is not recorded), and Dynamic Type at large text sizes.

## Manual app walkthrough

Opened the explicit sample kitchen and entered Alex’s three reactions. The final submitted ballot confirmed bulgogi with 100% table happiness. Verified the receipt has four unique diners and Mia’s and Leo’s notes. Increased recipe portions from four to five and observed beef change from 600 g to 750 g and rice from 300 g to 375 g. Marked beef ready, selected garlic and scallions as missing, and verified the grocery share action has two items. No message was sent.

Started cooking and a fifteen-minute timer. Declined notifications in the simulator and verified the real in-app countdown still ran. Advanced through all five steps, observing completed progress, and rang the dinner bell. The served screen appeared and the active timer cleared.

Screenshots include views from this walkthrough; they show sample data. No physical device, online household sync, remote APNs, Live Activity, universal links, or iMessage extension was tested or claimed. The browser preview mirrors the installed native app.
