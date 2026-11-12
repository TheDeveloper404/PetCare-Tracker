# Architecture / ADR 001

Native SwiftUI features use value drafts, small observable view models and injected services. CareStore owns SwiftData mutations and explicit save/rollback. Retain the existing Xcode project and iOS 17.6. No generic repository, external packages, backend, accounts, tracking or cloud synchronization.

Schema V1: Pet has cascading CareRecord, Reminder and WeightEntry relationships. CareRecord owns cascading associated reminders. Stable unique UUIDs identify entities. Weight history is separate rather than duplicated in care records. Gregorian ISO days represent date-only information; appointments use exact Date timestamps. Reminder times follow the device timezone. Monthly dates clamp without changing the original anchor; yearly February 29 returns in leap years. Missing DST times move forward, repeated times select the first occurrence. Future schema changes require a new VersionedSchema and tested migration.

Photos are downsampled and re-encoded without original EXIF under generated UUID filenames. Images declaring more than 100 megapixels are rejected before decoding. Autosave is disabled. Startup failure never silently replaces the store.

## ADR 002 — additive backup recovery
Versioned JSON contains all pets, records, reminders, weights and photos. Validate the entire archive before writing. Import only missing pet UUIDs; skip existing pet subtrees intact. Amended 2026-11-10: without premium an import may not leave more than one pet profile (existing + imported); the check runs before any write and fails with premiumRequired. The earlier rule (recovery ungated) let a free user add profiles by editing an exported file. Paying users regain premium on a new device through their Apple Account before importing. Write images under new local names before a single save in a separate context. Roll back and remove only new images on failure. A crash may leave unused images, not deleted data. Exports are unencrypted. This is additive recovery, not replacement or synchronization.

## ADR 003 — reminders
Persist definitions independently. Reconcile on edits, deletion, activation and significant time changes. A rolling queue contains up to 64 closest dated requests. Users must periodically reopen the app to refill this finite queue. The UI reports permission and scheduled horizon. Delivery depends on iOS settings and is not a medical guarantee.

Re-enabling a completed one-off reminder clears its completion marker so its unchanged future date
can be scheduled again. Pausing/resuming a recurring reminder preserves its completion history.
These are mutation-policy corrections within schema V1; no schema migration is required.

## ADR 004 — premium
Only verified matching StoreKit 2 non-consumable transactions grant premium. Product ID is configurable. Refresh currentEntitlements on activation and observe Transaction.updates. StoreKit locally available verified history supports offline access; no UserDefaults entitlement boolean. Revocation never deletes data. Display StoreKit prices only; explicit restore uses AppStore.sync.

## Threat surface
Validate untrusted backup/photo input and all relationships before persistence. Never use imported filenames as paths. iOS data protection, minimal PhotosPicker access and contextual notification permission. No user content in logs. StoreKit communicates with Apple only for purchases. Exports require user sharing.

Review fixes: moving an appointment date pauses its linked reminders in the same database save and asks the user to review them. Backup JSON is limited to 64 MB at both export and import. Bounded file reading/decoding and transactional import run off MainActor using a dedicated serial import queue with a job-confined SwiftData context; errors preserve existing data.

## ADR 005 — explicit background import executor
Runtime checks under installed Xcode 27.2 showed the ModelActor factory running off-main but its import body executing on the main thread. Bulk import therefore uses a private serial DispatchQueue, a Sendable ModelContainer, and a fresh ModelContext confined to each synchronous queue job. No model/context escapes or crosses an await. The async caller receives only a value result after save/rollback and photo cleanup. The worker is shared per CareStore to serialize overlapping imports. UI CRUD remains on mainContext. Architect design check approved this narrow executor adjustment; regression tests assert actual off-main saving and overlapping-import integrity.

## ADR 006 — pre-release additions to schema V1
Reminder.interval (1–12 multiplier of the repeat rule) and Pet.vetName/vetPhone/vetAddress were added to PetCareSchemaV1 in place, with defaults, on 2026-11-10. V1 had never been shipped, so a V2 schema would have duplicated every model and kept a permanent migration for a store no user has. Development installs made before this date must be deleted once. From the first public release the ADR 001 rule applies without exception: new VersionedSchema plus a tested migration. Backup fields for these values are optional, so archives written earlier remain valid (version stays 1). Premium gating for both features lives in the editors; stored values keep working if premium is lost.

StoreKit test boundary: the automated integration test uses SKTestSession.buyProduct, verifies environment .xcode, refreshes a new PremiumStore from signed local history and issues a refund. Interactive Product.purchase(confirmIn:) and explicit AppStore.sync remain native Apple flows requiring sandbox/physical-device validation. An unconfigured product ID does not start a transaction observer.
