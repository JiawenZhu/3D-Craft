# Account purchases, welcome screens, and cloud games

Updated September 15, 2026.

Purchases require a signed-in Firebase account, regardless of whether it uses
Apple, Google, or email authentication. There is no `test@test.com` purchase
allowlist. Apple sandbox payment credentials are separate from the app account.
Previously credited purchases remain owned by their original Firebase account.

## Purchase reconciliation

A new pack claim previously reconciled unrelated subscription history before
selecting its credited wallet. A receipt owned by a previous app account could
abort that reconciliation, leaving the app looking at an empty production
wallet despite a verified sandbox grant. Pack claims now reconcile only their
matching purchase. General reconciliation skips history owned by other accounts;
an explicit attempt to claim another account's receipt still fails.

Retained, verified pack receipts report their original amount for the app's
receipt-deduplicated success animation, with zero additional credit. No client
balance adjustment or duplicate grant was added. Pending transactions remain
stored for retry. The sync notice is scoped to Wallet and cleared when no pending
purchase remains for the current account; it no longer covers other screens.

Cloud Run revision `craft-api-00017-kml` serves the fix through
`https://3d-craft.web.app/api/`.

## Games and sign-in

The existing first-party Emberfront, Coastline Rush, The Last Signal, Emerald
Skies, and Lanternfall games are published in Firestore's community catalog.
They start at `/play?game=<id>` on production Hosting. The game bundle loads only
on that route. The native catalog fetches those records and their cover images;
it does not seed a local-only list. Existing community test examples remain
unapproved. No fake votes were inserted. `scripts/publish_first_party_games.py`
records the reviewed export hash and preserves votes on subsequent runs.

The welcome and sign-in screens use the existing appearance palette, compact
character artwork, labeled fields, password reveal, Apple/Google/email options,
and bilingual copy. Authentication endpoints and credentials are unchanged.

## Verification

- 59 Firebase unit tests passed, including purchase ownership, retry, expiry,
  and reconciliation regressions.
- 65 native unit tests executed: one existing skip, zero failures.
- Web production build passed; existing large-chunk warnings remain.
- All five shipped Godot pack scene smoke checks passed without script errors.
- Production browser player started Lanternfall and Coastline Rush and emitted
  real gameplay state. Full iPhone gameplay performance remains user acceptance.
- Live production catalog returned five games with covers; cloud health returned
  `200` / `ok`.
- Native welcome/sign-in/live-catalog UI acceptance checks exercise password
  reveal/hide and navigation without buying anything or creating an account.

Source `1de40b8` was installed and launched on the connected iPhone. App Store
version 1.0 build 15 contains these changes and is now Waiting for Review.
See [submission receipt](submission-2026-09-15.md). Apple approval is pending.
