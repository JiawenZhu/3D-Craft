# Privacy data map — implementation review draft

This is an inventory to validate against production, not a completed App Privacy declaration.

| Data | Current/expected purpose | Recipient or handling to confirm |
|---|---|---|
| Uploaded photos / reference images | Concept generation and image-to-3D | App backend; selected image provider; selected fal/3D service |
| Text prompts / conversations | Clarification, prompt planning and generation | Backend; Gemini or optional connected ChatGPT planner |
| Concept images / 3D files | Store and retrieve user creations; export | Backend/storage; explicit system share destination |
| App user/session identifier | Ownership, jobs and credit balance | Current development UUID; replace with durable production identity |
| Optional connected ChatGPT account | Model catalog and account-powered functions | Optional bridge/OpenAI; validate token storage, revocation and commercial authorization |
| Purchase transactions / credit ledger | Fulfill credits and subscriptions | Apple and production verification service; implementation pending |
| Operational logs | Diagnose requests and failures | Audit production logs for prompts, image URLs, identifiers and retention |

Do not declare Data Not Collected solely because there is no tracking SDK. Review whether data is linked to a user, retained, collected by partners, and used for tracking. No final tracking or retention assertion has been made here. Inventory all SDKs in the release binary and verify required-reason API declarations.

Pending decisions: legal operator, support email, retention durations, backup deletion, account deletion recovery window, provider data terms, subprocessors, incident process. Publish a policy consistent with these decisions and the implemented runtime. Source: [Apple app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).
