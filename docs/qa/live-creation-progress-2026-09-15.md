# Live completion and 3D submission follow-up

The reported two-image cloud job is complete (100%, two saved concepts).
The recent job records inspected contained no new 3D job for the reported
submission interval. These were read-only checks; no generation was replayed.

Native changes:

- Publish each accepted job response immediately, including its captured source
  concept, instead of waiting for a full library/catalog refresh.
- Poll job state first, independently of library and price retrieval. Reading a
  known pending job no longer takes the foreground busy lock. Completion clears
  the persisted pending request before ancillary requests, and late active
  snapshots cannot regress terminal state.
- Return the foreground submission state immediately after the server accepts
  image/refinement/model work. Show a starting message while 3D submission is in
  flight. Refresh the private library after observed completion.
- Allow selection of concepts already present in job results even when the
  project snapshot has not caught up. Restrict this fallback to the same project.
- Obtain fal.ai permission on the still-present 3D confirmation sheet. Only
  dismiss after consent succeeds. Declining keeps the sheet retryable and shows
  the reason; it does not leave a hidden permission continuation holding busy.
- Add pull-to-refresh to the conversation.

Focused native tests cover immediate publication, source identity, terminal
regression prevention, pending-request release, selection before project refresh,
and provider/account consent boundaries. The physical-phone end-to-end consent
and generation flow still needs user acceptance; no paid 3D request was made for
this verification. The existing App Store review build is unchanged.
