# misbehave

iPhone app for couples. Two people link their iPhones and give each other points: +1 when something was nice, −1 when not. The partner gets a push right then ("You received +1 goodgirl point") and sees the score in a widget. The moment is the product: a point that arrives late or silently has missed its purpose, so **push and widget freshness matter more than anything else in the app**.

- Each person picks a role, `goodgirl` or `goodboy` (shown untranslated). It names the points they collect.
- A person can have several connections; each has its own score, strictly separate.
- Free, no accounts, no own server, no ads, no tracking, no third-party code.
- Not in scope for v1: rewards, streaks, a history UI, iPad/Mac, more than two people per connection.

Bundle ID `com.mp17.mpapps.misbehave`, iPhone only, iOS 18+, English and German. Original plan (German, working title "Goodgirl/Goodboy"): https://claude.ai/code/artifact/c22d5ca8-3c7b-40b4-be29-318d8353497c (a Claude Doc; read it with the docs connector).

## Working mode

Marco writes in German; answer in German. Code, comments, commit messages and this file are English.

- **Finish the work.** Do everything that can be done without him, including commit and push to `origin main`. Don't ask before committing or pushing.
- **No Claude attribution** in commits or PRs (no `Co-Authored-By`, no "Generated with").
- **At the end of a task, ask whether to upload a build** to App Store Connect so it is in TestFlight. Don't upload unasked.
- **Check visual work in the simulator first** (or on the test device) instead of cutting a build per iteration. Look at the result yourself with a screenshot before reporting.
- **Keep this file current.** When the concept, the release process or a hard-won fact changes, update it in the same commit. Keep it lean: only what a new session needs, no changelog, no narration.
- Marco signs in to Apple sites himself; never enter credentials. Deploying a CloudKit schema to Production is his click (it is blocked for Claude).

## Architecture

Everything is Swift and Apple frameworks, Swift 6 language mode.

| Part | Path | Role |
| --- | --- | --- |
| App | `misbehave/` | SwiftUI UI, `AppModel` (single source of truth), `SyncCoordinator` (CloudKit) |
| Widget | `MisbehaveWidget/` | Score of one connection, chosen per widget via App Intent |
| Notification extension | `MisbehaveNotificationService/` | Rewrites the neutral push into the real text |
| Shared package | `MisbehaveKit/` | Models, local store, CloudKit schema, push wording, tests |
| Config | `Config/` | Info.plists, entitlements, `ExportOptions.plist` |

The Xcode project uses file-system-synchronized folders: a file added to a target's folder is in the target. Don't put Info.plists or entitlements in those folders.

### Local state

JSON files in the App Group container (`group.com.mp17.mpapps.misbehave`), each with **exactly one writer** so no cross-process lock is needed:

- `store.json`: written only by the app.
- `inbox.json`: written only by the notification extension (what it fetched, plus its last run for diagnostics).
- `diagnostics.json`: written only by the app.

Readers (widget, extension) use `LocalStore.snapshot()`, which merges store and inbox. Local first: a tap is written to the device immediately and synced afterwards.

### CloudKit

Container `iCloud.com.mp17.mpapps.misbehave`. **A connection is a record zone** (`conn-<UUID>`) in the inviting person's private database, shared with exactly one partner through a zone-wide `CKShare`.

| Record type | Record name | Fields |
| --- | --- | --- |
| `Profile` | `owner` or `participant` | `role`, `displayName` |
| `PointFromOwner` | event id | `delta` (+1/−1), `createdAt` |
| `PointFromParticipant` | event id | `delta` (+1/−1), `createdAt` |

- Points are immutable events; a score is the sum of the other side's deltas. No counters, so no sync conflicts.
- Which side a device is follows from the database the zone is in: private = owner, shared = participant. No local person id.
- Connections are always identified by zone id, never by name.
- Sync runs through two `CKSyncEngine` instances (private and shared). Invitations, accepting, subscriptions and "delete all" talk to CloudKit directly because they need the network right now.
- Invitation = closed share (`publicPermission = .none`) with one `oneTimeURLParticipant()`. The owner disconnects by deleting the zone, the participant by deleting the share record.

### Push and widget

1. Two `CKDatabaseSubscription`s filtered by record type: private database on `PointFromParticipant`, shared on `PointFromOwner`. So only the partner's points trigger a push. They are re-saved on every launch.
2. The push carries a neutral localized text (`push.neutral.body`), `mutable-content` and `content-available`.
3. The notification extension fetches the new points with its own change tokens, writes them to the inbox, sets the real text and reloads the widget.
4. `content-available` also wakes the app, which syncs and reloads the widget.
5. Fallback: if points arrive through a background sync and no remote notification was delivered, the app posts a local one.
6. While the app is in the foreground, real pushes show no banner (the score changes on screen); only the demo connection's does.

Nothing visible happens without notification permission, and the extension does not run either. The app therefore shows a full-screen prompt on every launch until iOS has been asked.

**Settings → Diagnose** in the app shows permission, push registration, both subscriptions with error text, and when the last sync, wake-up, extension run and fallback happened. Ask for a screenshot of it from both phones before guessing at a push problem.

## Build and test

```bash
# Package tests
cd MisbehaveKit && swift test

# Simulator build
xcodebuild -project misbehave.xcodeproj -scheme misbehave \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

- The simulator has no iCloud account: only onboarding, the demo connection, settings and the widget can be checked there. Anything involving a second person needs two iPhones with two iCloud accounts.
- A debug build on Marco's iPhone talks to the CloudKit **Development** environment and replaces the TestFlight install (same bundle ID, Production data on the device). Avoid it while he is testing with TestFlight; use the simulator for UI and TestFlight for CloudKit flows.
- Strings: every user-facing string needs a German entry in the target's `Localizable.xcstrings` (keys are the English text). After a build, compare against the compiler's `*.stringsdata` in DerivedData to find missing keys. `push.neutral.body` is used only by CloudKit and looks unused.

## Release to TestFlight

App Store Connect app ID `6821730863`, team `PP2LXGF5L3`. Uploads work from the command line through the Apple ID signed in to Xcode; no API key.

1. Raise `CURRENT_PROJECT_VERSION` in `project.pbxproj` (two places, project level). Currently **3**.
2. Archive and upload (use a temp directory for the outputs):

```bash
xcodebuild -project misbehave.xcodeproj -scheme misbehave -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$TMP/misbehave.xcarchive" \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive -archivePath "$TMP/misbehave.xcarchive" \
  -exportOptionsPlist Config/ExportOptions.plist -exportPath "$TMP/export" \
  -allowProvisioningUpdates
```

"Upload succeeded" means the build is processing; it shows up in TestFlight a few minutes later.

### CloudKit schema

- TestFlight and App Store builds use the **Production** environment, which never creates record types or fields on its own. A new type or field must exist in Development first, then be deployed in the CloudKit Console ("Deploy Schema Changes…").
- Development creates schema just in time when a debug build saves a record. To seed without a second person, save one record of each new type from a debug build into a throwaway zone and delete the zone.
- Production schema can only grow. Never rename or repurpose a record type or field; add new ones.
- Console: https://icloud.developer.apple.com/dashboard/database/teams/PP2LXGF5L3/containers/iCloud.com.mp17.mpapps.misbehave/environments/DEVELOPMENT/types

## Hard-won facts

- One-time links need the entitlement `com.apple.developer.icloud-extended-share-access` = `[InProcessOneTimeLinks]`. Without it CloudKit traps in `CKShare.addParticipant` instead of throwing.
- The Swift name `oneTimeURL(for:)` is marked iOS 26 in the SDK; the code calls `__oneTimeURL(forParticipantID:)`, available since iOS 18.
- When CloudKit crashes or misbehaves without an error, run the steps one by one from a debug build on the connected iPhone and print each result (`xcrun devicectl device process launch --console …`); crash logs can be pulled with `devicectl device copy from --domain-type systemCrashLogs`.
- The demo connection is local only and mirrors every tap; it exists so the app and its notification can be tried alone (also for App Review).

## Open

- Not yet confirmed on two real iPhones: that the visible push arrives and the widget follows once notifications are allowed (build 3).
- Never exercised on real devices: the owner detecting that the partner left (read from the share's participant list), "delete all data" against iCloud, account switch.
- Before the App Store: privacy policy and support URLs, store page, review notes with a pairing video, age rating, final icon (the current one is a placeholder).
