# Mobile concept image models

Gemini is the default and needs no ChatGPT account. The studio configures its Gemini service; users do not enter a Gemini or OpenAI API key.

`GET /api/mobile/image-models` returns two authenticated, explicit choices:

| Display name | Request identifier | Image setting |
| --- | --- | --- |
| Gemini 3 Pro Image | `gemini-3-pro-image` | Native 2K |
| GPT Image 2 · ChatGPT account | `codex-gpt-image-2` | Native account output |

The independent GPT Image 2.5 API route has been removed. Existing saved concepts retain their original provenance. The native app migrates the old image preference to Gemini; a previously bound pending request is not silently rewritten.

ChatGPT is optional. Profile → ChatGPT connection starts the official Codex device-code flow for the user's own account. The local studio bridge isolates each mobile owner's Codex home and uses the account's built-in image tool; it does not send account tokens to the public Images API. Its current actual image model is GPT Image 2, not a selectable 2.5 variant. Account availability is checked, but entitlement and generation success still require a real signed-in generation test.

Prompt planning is a separate choice: Gemini 3.8 Flash by default, or a model returned by the connected account's live catalog. The same chosen planner writes the prompt and evaluates alternate-view consistency. The native picker prefers supported low reasoning on explicit account-model selection. Account planning is bounded to 45 seconds; image turns have a longer generation timeout. No silent cross-provider fallback or automatic generation retry occurs.

Both image routes retain canonical image → anchored camera views and conservative consistency review. New unavailable selections fail before credit reservation. Requests bind model and planner choices into idempotency; retries of an existing job resolve the same job without reserving credit again. Native dimensions and actual model/provider provenance are stored. Smaller account-native images are not upscaled and mislabeled 2K.

Offline coverage includes default Gemini without a ChatGPT account, removed API rejection, account capability gates, selected renderer/reference routing, planning selection, idempotency, credit accounting, isolated account endpoints, and image extraction. Native tests cover preference migration, request identity, and account/model screens without signing in or generating. The Codex bridge is a local studio integration; this does not establish a standalone public iOS subscription-auth service.

Reference: [official Codex app-server protocol](https://learn.chatgpt.com/docs/app-server), [Codex image generation](https://learn.chatgpt.com/docs/image-generation).
