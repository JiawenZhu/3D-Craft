# Creator-provided browser games

The creator explicitly supplied these games and requested publication on
September 15, 2026. All three public pages were opened without sign-in and their
start controls entered gameplay. This is a start/control smoke check, not a
complete playthrough or physical-iPhone performance certification.

- Moonrun · Fox of the Hollow Road — https://claude.ai/artifact/PvCrAGzNSy4xSVVTTwPspj
- Moss Robot · Sunseed Garden — https://moss-robot-sunseed-garden.evan001007.chatgpt.site/
- Emberwing · Dragon Flight — https://emberwing-dragon-flight.evan001007.chatgpt.site/

`scripts/publish_creator_examples.py --publish` updates their existing example
records in Firebase, with creator attribution, publication authorization, and
moderation audit records. Votes and creation dates are preserved; removed
records cannot be silently republished. The public catalog now contains eight
games. These curated entries are attributed to Jiawen Zhu and managed by the
3D Craft catalog operator, not assigned to a guessed personal login.

## Future creator submissions

The existing build 15 flow is Games → + → Share a game. Signed-in users enter
title, creator, description and a public HTTPS link, use Check link and Open and
play-test, confirm their rights, and submit. My submissions displays pending
review status. Games are saved in Firebase under the submitting account, and
only approved entries enter the public feed. No provider account connection or
source-code upload is necessary; creators publish their game with Claude,
Codex or another tool before sharing the playable URL.

The shared link checker now accepts Claude's current `/artifact/` URL alongside
its older published artifact paths. It still checks public DNS, each redirect,
HTML reachability and sign-in/access-check pages. Claude returns HTTP 403 to
the cloud checker for some public artifacts that work in a browser. Such links
are admitted only as `browser_review_required`, with `reachable=false`, to the
private pending queue. An operator must open and play the public game and use
`moderate_community.py decide ID approved --browser-verified --reason ...`
before publication. That review is audited; no client can supply the override.
Chat conversation and private network URLs remain rejected. Future submissions
are not automatically approved.

## TestFlight notes

The build 15 English (U.S.) What to Test field was saved and reloaded successfully.
The exact text is in `../app-store/2026-09-14/testflight-build-15.txt`. It covers
account isolation, sandbox purchases, token animations, Gemini/3D creation,
AI permission, playing/sharing games and visual feedback. No tester invitations
were sent; the page still shows zero groups and zero individual testers.

## Deployment and acceptance

- Cloud Build `18644d7e-25d7-428d-a39e-c7e08e7dbe04` succeeded.
- Cloud Run `craft-api-00019-pkr` serves 100% of traffic through the canonical
  Firebase Hosting API.
- 22 focused community/link-check tests passed, including private-address and
  conversation-link rejection, Claude browser-review admission, and mandatory
  operator verification before approval. Client-supplied approval overrides
  are rejected by the submission schema.
- A newly created disposable non-test-email account used the deployed API to
  check all three links, submit the Claude artifact, retry idempotently, view
  My submissions, verify that the pending game could not be publicly played,
  and remove it. The temporary identity and records were deleted afterwards.
  Evidence: `/tmp/craft-public-submission-live.log`.
- The live public catalog returns the three supplied games plus the five
  existing games. This is a cloud update; it needs no new iOS build and does
  not replace the app version already waiting for Apple review.
