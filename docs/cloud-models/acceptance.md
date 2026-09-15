# Cloud image-to-3D generation acceptance

This is evidence for the image-to-3D service, not overall App Review readiness.
The cloud concept-image/chat/planning flow, account-connected AI handoff, community
moderation, and final device acceptance still need completion.

## Durable execution and accounting

- `server/firebase_model_jobs.py` publishes owner-scoped progress in
  `users/{uid}/studioJobs`, with provider arguments, request IDs, callback tokens,
  reservation allocations and leases under the server-only `private` subtree.
- The authenticated request schedules Cloud Tasks before the Firestore transaction
  creates the job and reserves its authoritative server quote. Reusing a request
  key returns the same job; changed content is rejected.
- References come from the same user's private Firebase Storage. Multi-view input
  additionally requires one validated sibling set and distinct camera directions.
- A transaction authorizes the paid provider POST once. Lost responses wait for a
  signed fal callback; retries never resubmit that paid POST. Queue observations
  continue through Cloud Tasks, independently of the app or server process.
- Completed GLB files are checked for format, size and external file references,
  then written to the private model directory. Publishing the shared web/mobile
  library entry and settling the Token reservation happen in one transaction.
- Failure releases the original reservation. A prior subscription allowance is
  only restored while that same paid period remains active and unrefunded.
  Failure cannot convert expiring allowance into permanent Token-pack credit.
- Cleanup is scheduled before model upload. Unpublished outputs, including late
  uploads that race account erasure, are removed by an authenticated worker.
- A job has a one-hour completion deadline. An ambiguous submission that cannot
  be recovered by then fails and releases its reservation; it is not sent again.

## Verification

- 51 focused tests passed across model accounting/provider boundaries, project
  uploads, purchases/subscriptions, cloud API and account deletion.
- Real Firestore/Storage fixture checks passed: simultaneous identical requests,
  conflicting retries, worker lease exclusion, ambiguous paid submission,
  callback recovery, crash after upload, exactly-once success/failure settlement,
  account-deletion barriers and unpublished-output cleanup. The fixture was removed.
- Repeat the transaction/crash check with an authorized gcloud account:
  `CRAFT_RUN_FIRESTORE_INTEGRATION=1 python scripts/verify_cloud_model_jobs.py`.
  This uses isolated cloud records and mocked fal calls, so it does not buy a model.
- The native Release build passed using the installed Xcode. The optional App
  Intents metadata notice remains; this is not distribution validation.

## Deployment

Cloud Run revision `craft-api-00008-dlb`, image build
`addd7387-3d74-4452-9771-c6c3f9369789`, serves the canonical
`https://3d-craft.web.app` API. The model key is in Secret Manager with access
restricted to the runtime identity. `craft-model-jobs` performs durable polling;
`craft-upload-cleanup` handles unpublished outputs. Worker access requires the
configured service identity and audience.

`modelGenerationReady` is independent of `generationReady`. The latter remains
false until the complete advertised creation flow passes acceptance.

## Live provider acceptance

All four single-image requests completed through the canonical public API using
one disposable Firebase account and the bundled Lantern Explorer reference:

| Engine | Settled Tokens | GLB bytes | Mesh vertices | Unauthenticated download |
|---|---:|---:|---:|---|
| Rodin | 46 | 10,532,684 | 53,560 | 403 |
| TRELLIS.2 | 35 | 2,115,696 | 27,946 | 403 |
| Hunyuan 2 textured | 56 | 4,509,304 | 25,042 | 403 |
| Hunyuan 2 white mesh | 19 | 8,403,696 | 175,080 | 403 |

- Every output is a parseable standalone GLB with mesh geometry. Authenticated
  owner downloads succeeded; anonymous downloads and even the owner's direct
  Firestore read of private provider-control records returned 403.
- Starting with 500 disposable sandbox Tokens, the wallet ended at 344, with zero
  reserved. Repeated requests before and after completion produced no additional
  charge or library model. The shared library contained exactly four models.
- Actual signed fal notifications reached the deployed callback and returned 200.
  TRELLIS.2 took longer and was confirmed InProgress at fal before completion;
  it was not cancelled or resubmitted.
- No Apple purchase was made. The test incurred the configured fal generation
  fees; its 500-Token balance was an isolated fixture, not a customer grant.
- The disposable Auth account, Firebase records/files and remaining fixture tasks
  were removed. Local evidence remains in `/tmp/craft-cloud-model-acceptance/`
  and `/tmp/craft-model-live-result.log` on this development Mac.
- Multi-view admission/provider argument checks pass, but fresh live multi-view
  output quality and phone rendering/export are still required. This single-image
  run does not certify those separate paths or the unfinished concept generator.

The iPhone UI now labels reservation/completion/return activity explicitly and
only offers the legacy Hybrid choice when the cloud bootstrap lists support.
The stale claim that cloud wallets use local test rates was removed.
