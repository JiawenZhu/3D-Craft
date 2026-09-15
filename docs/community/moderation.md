# Community moderation operations

3D Craft's operator is Jiawen Zhu. The published contact route is https://3d-craft.web.app/contact. This is a human review workflow; it does not automatically send notifications or promise that a report has already been assessed.

## Before launch

Assign and exercise a daily queue-review routine, including weekends and urgent reports. Confirm that support email is monitored. Target handling objectionable-content reports within 24 hours; this is an operational requirement to establish before release, not an automated response already provided by the software.

New submissions remain `pending` and invisible to other users until approval. A valid HTTPS response proves reachability only. Do not approve a link based on its title, thumbnail or HTTP status. Open the actual game and inspect gameplay, menus, linked destinations and public metadata. Reject objectionable content, infringement, misleading links, account-gated builder pages, unexpected payment flows or content unsuitable for the app's declared audience. Verify the creator's affirmative rights and play-test confirmations. Consider applicable App Review requirements for linked browser games and age restrictions before final submission.

Existing records without a review decision remain unpublished. Do not silently backfill rights confirmations or approve historical examples to populate the feed. Three historical example links currently need explicit rights/review reconciliation.

## Operator commands

Use an IAM-authorized gcloud identity from the repository root. No service key is embedded in the app or checked into Git. The operator tool records decisions and their reasons in Firebase.

```sh
python scripts/moderate_community.py queue
python scripts/moderate_community.py decide GAME_ID approved --reason 'Describe what was reviewed and why it is appropriate.'
python scripts/moderate_community.py decide GAME_ID rejected --reason 'Explain the correction the creator needs to make.'
python scripts/moderate_community.py posting FIREBASE_UID block --reason 'Explain the abuse and decision.'
python scripts/moderate_community.py resolve REPORT_ID --reason 'Record the action actually taken.'
```

Queue output includes private report text. Keep it within the operator workflow. Creator-visible review notes must not identify a reporter. A posting restriction prevents new submissions; separately reject each existing offending game to remove it. Unblocking posting does not approve or republish rejected content. Resolve a report only after checking it and recording the actual outcome. Use `posting ... allow` after a successful appeal.

Approved external pages can change after review. Revisit reported links and periodically review the published catalog. Reject pages that change into unsuitable content. A failed reachability recheck hides the game from rankings; a changed redirect target returns it to pending review.

## Data and user controls

- Cloud API derives the acting account from verified Firebase authentication. Client writes to community games, vote aggregates, reports and moderation documents are denied by Firestore rules.
- Votes are transactionally stored per account and category. Repeated requests carry the intended liked/unliked state and cannot multiply a like.
- Reports atomically save an operator-only report and hide the game for the reporter. A failed save returns an error; the UI does not claim success.
- Blocking stores a private account preference. It hides all games by that creator in personalized rankings and prevents opening those games through the app. Unblocking is available in the app. This does not prevent someone from independently visiting a publicly known external URL.
- Submissions persist the creator's explicit rights and play-test statements, terms version and timestamp. Only approved, unremoved, reachable entries are public through the API. Pending or rejected entries are visible to their owner in My submissions.
- Account deletion erases that account's reports, moderation records about its own submissions, private safety preferences, submissions and votes. Other users' blocking preferences can remain as private abuse-prevention records; the privacy policy discloses this limited retention.

Reference: https://developer.apple.com/app-store/review/guidelines/#user-generated-content
