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

## iMessage extension (October 14, 2026)

Added the `OrderHomeMessages` Messages extension and the shared `OrderHomePoll` code.

- **Automated:** 53 tests pass, 0 failed (35 earlier tests plus 18 in `ChatPollTests`). They cover the message URL round trip, malformed and newer-version URLs, damaged ballots, the URL size budget at five dishes and a full group, re-votes replacing old ballots, the three ways a poll ends, and that a chat poll ranks dishes exactly like the app's kitchen vote (the same ballots are run through the real `OrderHomeStore`).
- **Project structure:** the project lists three targets; the build embeds `OrderHomeMessages.appex` in `OrderHome.app/PlugIns`; the extension's `Info.plist` has the `com.apple.message-payload-provider` point and the same version as the app; the shared folder compiles once per target. The iMessage app icon set (generated from the app icon) builds without warnings.
- **On screen in the iOS 27 simulator:** iOS registered `com.orderhome.app.messages` as a Messages extension; Order Home appeared in the Messages app drawer with its icon; opening it showed the "What's for dinner? / Start a poll" card. At a very large accessibility text size (on an iPhone simulator) that card truncated its text, so the compact states now scroll and wrap. On an iPad Pro simulator at normal text size, with the final build, the card showed its full text and tapping **Start a poll** opened the compose screen listing all eight dishes with their emoji and times.
- **Not verified:** choosing dishes, inserting and sending a poll, voting from a second participant, the bubble updating in place, the bubble image, closing a poll, and "Open Order Home". On the iPad, three dish taps and a swipe showed no effect over about a minute of screenshots, but the host's load average was around 480 and the simulator took about a minute to draw the extension at all, so that result is inconclusive rather than a confirmed failure. No physical device, no second phone, and no real iMessage delivery were tested.
- **One anomaly, not reproduced on a quiet device:** on the shared iPhone simulator, tapping "Start a poll" ended with the main app in front twice. The system log showed the simulator host force-quitting Messages and then opening the app, with no crash of the extension, and no `orderhome://` URL was requested. Another session was using that simulator at the time, which most likely explains it, but the log cannot show who sent those commands. The same tap behaved correctly on the iPad, which nobody else was using.
- **Not checked:** how a poll bubble behaves for someone without Order Home installed or on a device that cannot run the extension. The `orderhome://` URL is a custom scheme, not a web link, so it should not be expected to work in a browser.
- **Known gaps:** nothing here has been through App Store validation, and the extension has no entitlements or signing team.
