# Pet Care Tracker

Native offline-first iPhone application. SwiftUI, SwiftData, UserNotifications, PhotosPicker, StoreKit 2 and native PDF rendering. No third-party application packages, accounts, advertisements, tracking or custom backend.

Open **PetCare Tracker.xcodeproj**, choose **PetCare Tracker** and an iPhone simulator. The project uses Xcode 27.2, Swift 5 language mode with the installed Swift 6.4.2 compiler, and a minimum of **iOS 17.6**. Keep the existing project format; do not regenerate the project.

## Implemented flows
Pet profiles/photos, health records and category filtering, veterinary appointments, weight history in kg/lb, local recurring reminders with overdue tracking and custom intervals, veterinarian contact per pet, history search, weight chart, dashboard, EN/RO, offline PDF export, additive JSON backup recovery, and lifetime premium through verified StoreKit transactions.

Create/edit/delete records from a pet's history. Add a reminder from a record's detail screen to associate its lifecycle with that record. Appointments are a record category with an exact date/time; they appear under Coming up. Weight entries have their own editable history.

## Verification
In Xcode select **Product > Test**. The shared scheme includes unit/integration and UI targets. Tests use in-memory/temporary stores; UI tests launch a separate DEBUG-only test store. They do not reset the normal app's database.

For an isolated simulator run, use **bash scripts/verify.sh**. It creates/removes its own simulator (preferring the verified compact iPhone 17 layout), runs unit/StoreKit tests, installs the built app, runs UI flows and builds/analyzes Release. An existing simulator can be selected with DEVICE_ID; that simulator is never deleted by the script. Test artifacts stay under the reported temporary path. CI uses the same script and needs an Xcode version that supports this project format plus an installed iPhone runtime. CI has not been run on GitHub from this workspace.

The script also loads two synthetic photo fixtures for the PhotosPicker UI test. When running that
test directly from Xcode, first drag the two PNGs in PetCareTrackerUITests/Fixtures into the selected
simulator's Photos library. The native Files test exports a real backup, saves it in On My iPhone,
then selects that saved file for recovery; it does not substitute the file picker or import service.

The UI test bundle identifier is injected by the script from the built app. For a renamed bundle in Xcode's test environment set PETCARE_APP_BUNDLE_ID to the app identifier. The default is ro.acl-smartsoftware.petcaretracker.

## StoreKit configuration
The app's **PremiumProductID** Info.plist entry is ro.acl-smartsoftware.petcaretracker.premium.lifetime. Create the **non-consumable** product with exactly this identifier in App Store Connect and set its regional pricing there (planned: EUR 6.99, one-time). The paywall always displays Product.displayPrice; no production price is hardcoded.

**PetCareTrackerTests/PetCareTesting.storekit** defines a distinct local test product only. SKTestSession loads its configuration from the test bundle by explicit URL and uses its official buyProduct API to automate a local purchase. Tests verify an Xcode-signed transaction, automatic restoration via a fresh provider and refund. The explicit Restore button flow is unit tested with a provider fake; real purchase-sheet and AppStore.sync authentication must be checked in App Store sandbox. This configuration is included only in the test bundle, never the production app. The main Run scheme does not enable simulated purchases. App Store sandbox/physical device validation is still required.

## Data and notification limitations
All pet data remains local. There is no app-managed cloud sync or cloud backup. iOS device backup behavior depends on the user's settings. Removing the app can remove its data. Export a full backup regularly.

JSON backups include images, records, reminders and weights; they are **not encrypted**. Share them only intentionally and store them securely. Import validates the whole archive, adds only missing pet UUIDs and skips entire existing pet profiles. It does not merge updates into existing pets or replace the database. Without premium, an import cannot leave more than one pet profile; restoring several pets requires the premium entitlement (restored automatically through the Apple Account, or with Restore purchases). Unreadable/missing photos cause export to fail instead of producing an incomplete backup.

Reminder definitions always persist separately from system notifications. The app schedules up to 64 nearest occurrences and refills the queue on activation and changes. Open it periodically, particularly after extended inactivity or timezone changes. It reports the scheduled horizon. Wall-clock dates follow the device timezone on reconciliation; monthly/yearly dates clamp without permanent drift. Denied notification permission leaves in-app reminders available. Device Focus/notification settings can delay or suppress delivery; this is not a medical alert system.

PDFs are owner-maintained summaries, not certified veterinary documents. Previously verified StoreKit entitlements remain available through StoreKit's local history while offline. Refunds/revocations refresh on app activation and transaction updates; existing pet data is never removed.

Full functional and technical reference: [application documentation](docs/APPLICATION.md).

See [architecture](docs/ARCHITECTURE.md), [release preparation](docs/DEPLOY.md) and [privacy notes](docs/PRIVACY.md).

Possible future product stages, including iCloud versus app accounts, are documented separately in
[product development options](docs/PRODUCT_ROADMAP.md). They are proposals, not implemented features.

Review fixes: moving an appointment date pauses its linked reminders in the same database save and asks the user to review them. Backup JSON is limited to 64 MB at both export and import. Bounded file reading/decoding and transactional import run off MainActor using a dedicated serial import queue with a job-confined SwiftData context; errors preserve existing data.
