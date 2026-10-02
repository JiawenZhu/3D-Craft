# 3D Craft API keys

3D Craft's API lets a creator use their own account from a script or compatible HTTP client. It can create concept images, generate and retrieve 3D objects, make revised versions, generate animations, and manage owned assets. Work created through the API appears in the same account library as work created in the app.

- **API base:** `https://3d-craft.web.app`
- **Full route and request reference:** [OpenAPI specification](https://3d-craft.web.app/api/v1/openapi.json)

## Before you start

1. Sign in to 3D Craft and create a personal API key in the app. Choose only the permissions your workflow needs, and set an expiration when appropriate.
2. Copy the key when it is shown. Store it in a secret manager or a private environment variable; the full key is not shown again.
3. Check the current model choices and request a Token quote for the exact settings you intend to use.
4. Send generation requests with a unique idempotency key and a spending cap based on that quote. Poll the returned job ID for progress and results.
5. Revoke the key in the app when you no longer need it, or immediately if it may have been exposed.

API jobs use the signed-in account's production Token balance. Prices and supported models can change, so use the API's current quote rather than copying a Token amount from an example or screenshot.

## What you can do

| Goal | Common route | Permission |
| --- | --- | --- |
| Discover available 3D and animation models | `GET /api/v1/models` | `assets:read` |
| Review model pricing | `GET /api/v1/pricing` | `assets:read` |
| Quote a concept-to-3D creation | `GET /api/v1/creations/quote` | `assets:read` |
| Create a concept image and 3D model | `POST /api/v1/creations` | `models:write` |
| Follow a creation | `GET /api/v1/creations/{id}` | `assets:read` |
| Quote an animation | `GET /api/v1/animations/quote` | `assets:read` |
| Create an animation | `POST /api/v1/animations` | `animations:write` |
| List or download owned assets | `GET /api/v1/assets`, `GET /api/v1/assets/{id}/download` | `assets:read` |
| Rename an owned asset | `PATCH /api/v1/assets/{id}` | `models:write` |
| Delete an owned asset | `DELETE /api/v1/assets/{id}` | `assets:delete` |

Use the [OpenAPI specification](https://3d-craft.web.app/api/v1/openapi.json) for the complete route list, required fields, supported model IDs, and response shapes. Asset management affects only assets owned by the account associated with the key. Deletion needs its own permission; choose it only when the client needs to remove assets.

To make another version of a 3D object, start a new generation with a revised prompt or a different model using an existing project or concept. Renaming an asset changes its library label; it does not edit the geometry of an existing GLB.

## Read-only example

Set `CRAFT_API_KEY` privately in your environment or secret manager before running these commands. The example reads model choices and your asset list; it does not start a paid generation.

```bash
API=https://3d-craft.web.app
: "${CRAFT_API_KEY:?Set CRAFT_API_KEY privately before running this example}"

curl --fail-with-body "$API/api/v1/models" \
  -H "Authorization: Bearer $CRAFT_API_KEY"

curl --fail-with-body "$API/api/v1/assets" \
  -H "Authorization: Bearer $CRAFT_API_KEY"
```

For a paid creation, first request a quote for the same engine and settings. Pass the returned maximum Token amount as `maxTokens` in the creation request, along with a unique `idempotencyKey`. Check `GET /api/v1/creations/{id}` until the job finishes. Animation follows the same quote-then-create pattern through the animation routes. The [README](../README.md#personal-api-keys) has a short creation example.

## Key management and safe use

Personal keys are created, listed, and revoked from a signed-in account in the app. A personal API key cannot create more keys.

- Keep keys out of repositories, screenshots, issue reports, browser code, and public chat messages.
- Send keys only to the 3D Craft API over HTTPS, in an `Authorization: Bearer` header. Do not put a key in a URL.
- Use the narrowest permissions needed. A read-only client does not need generation or deletion access.
- If a key is disclosed, revoke it and create a replacement. Do not rely on deleting the message or commit that exposed it.

Use the [OpenAPI specification](https://3d-craft.web.app/api/v1/openapi.json) as the reference for client integration.
