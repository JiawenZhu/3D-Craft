# Version 2.0 — What's New (App Store text)

Paste the block below into App Store Connect → 3D Craft → version 2.0 → "What's New in This Version".
It is 1,325 characters (limit 4,000).

---

3D Craft 2.0 opens your studio to the tools you already use.

• API Access for Your Own Tools: Create personal API keys in Profile and connect coding agents, scripts and automations. Describe an idea and get a finished 3D model back in a single request — the concept image and 3D result appear in your app like anything you make here. Read your projects, download 3D models and concept images, rename or reprompt creations, and (only with a key you allow to) delete them. Keys spend your own Tokens, show a spending cap before each creation, and can be revoked at any time.
• Live Library Sync: Work made or removed outside the app — through an API key or on another device — shows up in your studio within seconds, with no pull-to-refresh.
• Themed Mascot Waiting Animations: Enjoy smooth, expressive animations featuring our panda chef and cloud dragon while your concepts and 3D models generate.
• Enhanced 3D Lighting & Shading: Preview your models with more accurate material reflections, improved environment fill, and refined studio presets.
• Seamless Creation Journey: Real-time progress updates ensure your multi-image generation jobs and 3D conversions stay in sync without interruption.
• Studio & Stability Refinements: UI polish, smoother account switching, and performance optimizations across iPhone and iPad.

---

## Accuracy notes (keep the text true)

- "Keys spend your own Tokens": API keys bill the production wallet. TestFlight/sandbox Tokens are not spendable through the API
  (except internal tester accounts listed in `CRAFT_API_SANDBOX_UIDS` on the server). Remove that allowlist before release.
- "Only with a key you allow to": deleting requires the `assets:delete` permission, which full access never includes.
- "Spending cap": `GET /api/v1/creations/quote` + `maxTokens` on `POST /api/v1/creations`.
- "Within seconds": the app refreshes every 20 s while open and whenever it returns to the foreground.
- Developer reference: `docs/API_KEYS.md`, live OpenAPI at `https://3d-craft.web.app/api/v1/openapi.json`.
