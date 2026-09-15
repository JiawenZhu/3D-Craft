# Cloud prompt improvement

14 September 2026 (local time). This completes the image-conditioned **Improve with AI** request, not the separate conversational chat or concept-image generation services.

## Implementation and deployment

- Canonical service: `https://3d-craft.web.app`; Cloud Run `craft-api-00011-2n5` receives 100% of traffic. Container `us-central1-docker.pkg.dev/forma-studio-2026/craft-cloud/api:2fd346fa-b661-4561-b75b-2369f2fa8464` was built successfully from the minimal deployment context.
- Gemini 3.8 Flash uses Vertex AI's global endpoint and the runtime service identity. Project ancestry, enabled billing, Vertex API and runtime `roles/aiplatform.user` were verified. No provider API key is put in an app or copied to source.
- Authenticated routes: GET `/api/mobile/planning/quote`, POST `/api/mobile/concepts/{id}/model-prompt`, GET `/api/mobile/planning/{jobId}`. A verified Cloud Tasks identity alone invokes `/internal/planning/{uid}/{jobId}`.
- Firestore holds private suggestions, request signatures, provider usage and job state under `users/{uid}/private/planningJobs/items/{jobId}`. A queued task is created before the reservation transaction. Early task delivery retries; abandoned pre-transaction deliveries expire.
- A single atomic state transition authorizes the paid provider call. Task redelivery cannot resubmit after an uncertain response. A response saved before a worker crash can settle later; otherwise the reservation is released and a user must explicitly request new work. Failed or incomplete suggestions are not charged to the user.
- Server-owned images from both current `images/` and migrated `files/` or `previews/` paths are accepted. Preview size is bounded; original files remain unchanged. No caller-supplied remote URL is fetched.
- The original description remains intact until the user applies the suggestion. Instructions are shared with the local review implementation, retain user language/intent, distinguish a swing from swimming, and do not promise facial scanning or game physics.

## Cost and native behavior

The server quote currently reserves at most **2 app Tokens** for up to 16,000 input tokens and 1,024 output tokens. Settlement uses actual input, cached-input and output usage including thinking, the existing 15% service fee and $0.01 Token usage value. The charge never exceeds the accepted quote. Unused reservation is returned, respecting subscription expiry and refund state.

Provider prices follow [Google Cloud's published pricing](https://cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing): $0.75 per million input and $3.75 per million output through 31 December 2026. The quote expires at that boundary; the published regular rates apply from 1 January 2027. The captured pricing and commercial policy are retained with each job.

Native source shows the maximum before the action. An interrupted request retains its ID and account-scoped draft, so retrying the same description resumes the same request. Account changes cancel result presentation; account deletion clears the local draft and request IDs. Wallet activity distinguishes planning reservations, completion and refunds. Own-account models are explicitly unavailable for this cloud action until the independent account integration is complete; they are never silently replaced by paid Gemini.

## Verification

- 68 backend checks passed, including ownership/authentication, strict spending consent, price-boundary behavior, response validation, no automatic provider retry, and existing billing/model/community/deletion checks.
- Disposable real Firestore tests passed: four simultaneous identical submissions created one reservation; replay charged once; changed input and insufficient authorization were rejected; another account could not read the job; a crash after call authorization refunded without another provider call; a saved answer recovered after a crash; deletion prevented new work. Fixture metadata and images were removed.
- A small real Vertex call with image and text returned a valid suggestion and settled one app Token.
- The canonical API acceptance used an actual disposable Firebase login, Cloud Tasks, the deployed runtime identity and Vertex. Two identical POSTs resolved to one job, one Token was charged, one was returned, a later POST did not charge again, and direct client Firestore access to provider state was denied. Fixtures were removed.
- A second canonical acceptance on the final revision passed using a migrated `files/` reference; the same ownership, single-charge and private-result checks passed (`/tmp/craft-planning-migrated-acceptance.log`).
- Local iOS Release build passed; its only reported build notice was skipped optional App Intents metadata extraction because the app has no App Intents dependency.

Local evidence: `/tmp/craft-planning-final-tests.log`, `/tmp/craft-planning-live.log`, `/tmp/craft-planning-canonical.log`, `/tmp/craft-planning-ios-acceptance.log`.

## Remaining acceptance

No new physical-phone installation or native animation/interaction acceptance is claimed for this change. The tiny synthetic reference tested transport and accounting, not facial likeness or image quality. Human review with actual character and swing images remains necessary. Conversational chat was subsequently deployed; see `chat-acceptance.md`. Concept-image generation, account-connected AI and complete phone/App Review acceptance remain open; `generationReady` deliberately remains false.
