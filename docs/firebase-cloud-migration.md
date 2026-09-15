# Shared Firebase studio — September 14, 2026

Canonical app API origin: https://3d-craft.web.app. Debug, simulator, TestFlight
and App Store builds use the same origin. Old LAN preferences no longer select
the backend. Firebase Auth, Firestore and Storage use Google's service endpoints
for that same Firebase project, forma-studio-2026 (display name: 3D Craft).

## Data

- `users/{uid}/mobileCreations`: shared web/iOS gallery metadata and immutable
  Storage object references. Legacy inline preview documents remain readable.
- `studioProjects`, `studioConcepts`, `studioJobs`, `studioConversations` below
  `users/{uid}`: owner-scoped original creation records. Clients can read their
  own records; only the cloud service can write them.
- Firebase Storage `users/{uid}/files`, `models`, `previews`: original reference
  images, generated concept images, and 3D models. Content hashes deduplicate
  retries; uploads cannot overwrite an existing object. No public download
  token is created. Temporary device caches are disposable copies.
- Wallets and verified payment events must be migrated separately into server-
  managed Firestore transactions. Local and sandbox balances are not real money
  and were intentionally excluded from creation migration.

Migration: `python -m scripts.migrate_firebase_creations` inventories records;
`--apply --gcloud-account=...` performs a one-time authenticated upload. Original
files are retained. Existing cloud record edits are preserved. A failed file
upload prevents publication of metadata referencing that file.

## Current release gate

`server.firebase_api` is a cloud-only reading API. It never opens SQLite or calls
a laptop. Its health response deliberately reports `generationReady: false`.
Cloud job execution, account-connected AI sessions, payment delivery and wallet
settlement must pass acceptance before this flag can change. Do not submit the
app to Apple or install over the current phone build on the strength of a
successful read-only API health check. The phone installer enforces this gate.

The local production-readiness blocks in `server/mobile.py` and `server/app.py`
are retained. Merely putting the old review server in Cloud Run is not a valid
migration: ephemeral SQLite would lose jobs and balances, and global file paths
would violate account isolation.

## Verified deployment

Cloud Run service `craft-api`, revision `craft-api-00001-nqw`, is behind the
Firebase Hosting `/api/**` rewrite. The website and the Firestore/Storage rules
were deployed. Migration verified 30 projects, 68 concepts, 57 jobs, 13 conversation
records, and 77 gallery entries (including 28 models) across three Firebase
accounts. All 204 referenced Storage objects exist. Source files were retained.

The authorized test account authenticated against Firebase and received HTTP 200
for its cloud projects, assets, jobs and wallet endpoints. Anonymous API requests
receive HTTP 401. The cloud wallet starts empty; local test credit history was
not treated as a verified production balance.

Validation: 34 storage/showcase tests, 8 cloud API/storage tests, and 10 selected
iOS unit tests passed. The website built and deployed. Unsigned iPhone Release
compilation passed; this is not an App Store archive or phone-install proof.
