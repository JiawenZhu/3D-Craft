# Community games — local iOS review

The Games tab shows public browser games ranked by real player likes in four
independent categories: Most fun, Best animation, Best visuals, Most creative.
Guests can browse and play. Posting, voting and reporting require sign-in.
Each account can like a game once per category and undo that like; the SQLite
primary key makes repeated requests idempotent. Nothing creates synthetic votes.

Submission requires a title, public creator name, optional description, a checked
HTTPS game URL and the creator's confirmation that they have play-tested it.
The server repeats the link check on submission. It rejects private addresses,
credentials, custom ports, non-HTML files, known agent conversation/workspace
URLs, HTTP errors and detected login pages. Every redirect is checked and DNS
addresses are validated and pinned before connecting. Public Claude artifact
pages are allowed; ordinary Claude share pages are not game destinations.

Link checks prove public HTML reachability, not gameplay. Play opens the original
site in SFSafariViewController. Stale links are checked again after one hour;
failures hide the game from rankings. Owners can recheck or remove submissions.
Reports hide the game for the reporting account and are stored for later review.
An operational moderation/review workflow is still needed before public launch.

Data lives in the existing Mac backend's mobile.sqlite3 community tables. It is
not deployed to Firebase and does not sync votes between separate backends.
The connected iPhone review build must reach the existing Mac gateway.

## Reference games checked September 13, 2026

- Moss Robot / Sunseed Garden: public, entered gameplay.
- Emberwing / Dragon Flight: public, entered Sky Islands gameplay.
- Moonrun Claude artifact b996c58b-bb3c-491c-9fd7-cc5f50a8b168: public,
  entered gameplay despite the wrapper's optional Sign in button.
- Claude shared conversation b47d0193-8eba-4cc6-b1de-7cd2f0226fe1: contains
  artifact 5f0f172e-f032-4ae9-aefa-92d0dfa539b0, but that artifact currently
  displays Sign in to view this page. It is not seeded as a public playable game.

`venv/bin/python -m scripts.seed_community_examples` adds only the first three
to the local review directory, labeled 3D Craft examples, with zero initial votes.
It preserves existing data and refuses production mode.

## Validation

64 backend tests passed with CRAFT_ALLOW_LOCAL_REVIEW=1 across community,
showcase and mobile flows. Community coverage includes auth, vote idempotency,
category sorting, undo, duplicate URLs, owner-only actions, failed links,
report visibility, rate limits, DNS/redirect restrictions and Claude artifacts.
Four handoff unit tests passed on the iOS simulator. Signed-in phone UI testing
is delegated to the user because simulator Google sign-in was not completed.

The native multi-object handoff UI test passed and reached the activity sheet.
The Codex browser simulator rendered the community rankings and opened Moonrun
inside the in-app browser. The signed Debug build was installed and launched on
the connected iPhone, with its embedded private gateway verified. No release or
Firebase deployment was performed.

Known validation boundary: some JavaScript sites return the same HTTP 200 shell
for both public and sign-in-only content. Claude's artifact shell is one example;
its anonymous metadata requests are not reliable for a server-side checker.
Thus page reachability is not a guarantee of anonymous gameplay. The creator's
open-and-play confirmation and report/recheck flow remain necessary. The private
Claude example was excluded based on live browser inspection, not on an automated
claim that every login gate can be detected.


## September 14: Play during creation and responsive votes

The native client now reads community games directly from Firestore through
CommunityCloudService; the backend-only storage description above records the
original September 13 implementation.

Active model jobs offer a Play while we create card. Games show the job's real
reported progress, animated featured cards, and direct Play actions. A completed
model produces a dismissible card, including above the in-app game browser.
Tapping it dismisses the browser first and navigates to that exact model. Old
library items do not trigger completion cards, and completion no longer forces
navigation away from a game.

Likes update immediately with count animation and haptic feedback. Only that
vote button waits for saving; Play stays available. A failed save rolls back and
shows retry guidance. Firestore writes the account vote and aggregate count in
one conditional commit, retrying conflicts and treating repeated intent as
idempotent. This does not replace production authorization rules.

Validation: six native unit tests passed for completion tracking, exact model
navigation, multiple completions, vote idempotency, and like/undo counts. The
simulator rendered live community entries. The final signed build was installed
and launched on the connected iPhone (installation sequence 5232). End-to-end
phone acceptance of voting and completion while playing remains with the user;
no synthetic public likes or paid generation were created for this check.
