# Cloud creative conversations

The conversation service runs at `https://3d-craft.web.app`. Cloud Run revision `craft-api-00013-mx7` receives 100% of traffic, using image `us-central1-docker.pkg.dev/forma-studio-2026/craft-cloud/api:0eeb731f-52cc-4bde-a31c-0c463c2231ed`. Google Cloud Build completed successfully. This adds chat to the existing prompt-improvement service; concept-image generation was unfinished at this checkpoint and has since passed the bounded cloud acceptance in [Cloud concepts](../cloud-concepts/acceptance.md).

## Behavior and storage

Authenticated clients obtain a chat quote and submit a message to `/api/mobile/projects/{id}/chat`. Gemini 3.8 Flash receives a bounded recent conversation, the durable creative brief, the selected style and an optional owned image preview. It returns a reply, updated brief, readiness flag and short suggested answers. Generation requires a separate explicit action.

Cloud Tasks handles work independently of the phone or Mac. Private request state, provider usage and spending consent are under the user's private planning jobs; owner-visible conversation records and the latest successful project brief are in Firestore. The new conversation index is deployed and real Firestore queries passed. The brief survives even when more than 20 failed messages push earlier successful replies outside the recent-history query.

One transaction reserves funds and creates the working message. Only one message can be active per project. Stable request IDs prevent duplicate reservations and charges. Another transaction publishes the completed reply and settles the wallet. A saved provider answer can recover after a worker crash. An uncertain paid call is never automatically repeated; its reservation is released. Account deletion prevents further work. Selected references must belong to the same account and project.

## Tokens and native UI

The current quote reserves up to 4 app Tokens per reply, covering 32,000 input and 2,048 output tokens. Actual usage determines the final charge using the existing 15% service fee and $0.01 Token usage value. Unused reserved Tokens return to their appropriate wallet bucket, respecting subscription expiry. Published provider price changes and quote expiry follow the same policy as prompt improvement.

Native source shows the maximum before sending and the actual charge beneath a completed reply. Pending submissions retain their request ID and account-scoped payload across interrupted responses. Default Gemini uses low reasoning effort; own-account models are not silently substituted with a paid provider. Those account integrations remain unavailable in this cloud route until separately completed.

## Verified acceptance

- 70 backend checks passed, covering strict request and response validation, pricing, ownership, authentication, existing cloud billing, model jobs, moderation and deletion.
- Disposable real Firestore tests passed: four concurrent retries produced one reservation; changed input, wrong-owner requests and wrong-project images were rejected; follow-up history and the durable brief were preserved; worker recovery did not duplicate a charge or provider call; deletion barred new work.
- Canonical API acceptance used a disposable Firebase login, Cloud Tasks and the deployed runtime identity. Text chat, a follow-up preserving the red swing frame while adding a green canopy and wooden seat, and reference-image understanding all completed. Each reply settled 1 Token. Replay did not charge again; provider state was denied to direct client Firestore reads; no automatic generation job was created. Test records, files, authentication and wallet were removed.
- Final local iOS Release build succeeded, including the per-reply actual-cost label. Its only warning was optional App Intents metadata extraction being skipped because the app has no App Intents dependency.

Evidence: `/tmp/craft-chat-complete-tests.log`, `/tmp/craft-chat-recovery-final.log`, `/tmp/craft-chat-canonical-final.log`, `/tmp/craft-chat-ios-complete.log`, `/tmp/craft-chat-final-build.log`, `/tmp/craft-chat-final-deploy.log`.

## Remaining acceptance

No physical-phone UI acceptance or App Store submission is claimed. The image test demonstrates reference understanding, not faithful 3D facial reconstruction. Concept-image generation/refinement, cloud account-connected AI, full physical-device generation/payment acceptance and final App Review disclosures remain open. `generationReady` remains false intentionally; do not replace the working phone build solely on the basis of these service tests.
