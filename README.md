<p align="center">
  <img src="docs/app-store/2026-09-12/branding/AppIcon-1024.png" width="112" height="112" alt="3D Craft app icon" />
</p>

<h1 align="center">3D Craft</h1>

<p align="center">Turn an idea or reference image into concept art, a 3D object, and a playable creation.</p>

<p align="center">
  <a href="https://3d-craft.web.app">Web studio</a> ·
  <a href="https://toolbox.marketingtools.apple.com/en-us/app-store/us/app/6811466883">App Store listing</a> ·
  <a href="https://3d-craft.web.app/docs/design/image-to-3d-comparison/index.html">Image-to-3D comparison</a> ·
  <a href="https://3d-craft.web.app/docs/design/video-provider-comparison/index.html">Video comparison</a>
</p>

<p align="center">
  <img src="docs/app-store/2026-09-12/promotional/02-blue-dragon-lavender.png" width="45%" alt="Blue dragon in the lavender 3D Craft theme" />
  <img src="docs/app-store/2026-09-12/promotional/01-lantern-cat-emerald.png" width="45%" alt="Lantern explorer in the emerald 3D Craft theme" />
</p>

3D Craft has a native SwiftUI iPhone app, a React web studio, and a Firebase-backed creation API. The checked-in iOS project targets iOS 17+ and declares app version **2.5** (build **2026092504**). That is the source version; the App Store listing is the place to check the currently released version.

## Create in the app

1. Describe an idea or add a reference image. The app generates one or more concept images.
2. Select the concept you want. The selected image is carried into a separate 3D confirmation step, where you can inspect the source, choose an engine, and see its Token quote before generating.
3. Open the resulting GLB in the interactive 3D studio. You can also create a character animation, export an asset, or use the game handoff.

Creation and animation are separate actions: selecting a concept does not silently spend Tokens on a 3D model. Work runs as a background job and its status can be revisited from the app.

### 3D object creation: from idea to finished model

These captures show one path through the current iOS source build. Token amounts shown in the screens are examples from that session; the app requests a fresh quote for each model and setting.

| Start with an idea | Refine it together |
| --- | --- |
| <img src="docs/screenshots/2026-10-01-ios-creation-flow/01-character-gallery.png" width="260" alt="Character gallery with example creations and a prompt field" /><br>Browse example characters or start from a written idea. | <img src="docs/screenshots/2026-10-01-ios-creation-flow/02-refine-idea.png" width="260" alt="Conversation refining the baby dragon idea before creation" /><br>Shape the character in the creation conversation. |
| **Review the concept request** | **Choose a concept** |
| <img src="docs/screenshots/2026-10-01-ios-creation-flow/03-concept-quote.png" width="260" alt="Concept generation sheet showing image count, editable prompt, and Token quote" /><br>Set the image count and prompt, then review the Token quote. | <img src="docs/screenshots/2026-10-01-ios-creation-flow/04-selected-concept.png" width="260" alt="Selected lava dragon concept with separate 3D and animation actions" /><br>Keep the concept you want before choosing a 3D or animation action. |
| **Confirm the 3D job** | **Follow its progress** |
| <img src="docs/screenshots/2026-10-01-ios-creation-flow/05-confirm-3d.png" width="260" alt="3D confirmation screen with the selected dragon image, engine, and Token quote" /><br>Inspect the source image, engine, and quote before generating. | <img src="docs/screenshots/2026-10-01-ios-creation-flow/06-3d-progress.png" width="260" alt="Background 3D reconstruction progress with stages and selected concept" /><br>Return to the job as the model is reconstructed. |
| **Inspect the result** | |
| <img src="docs/screenshots/2026-10-01-ios-creation-flow/07-finished-3d-studio.png" width="260" alt="Finished lava dragon in the interactive 3D studio with lighting and material controls" /><br>Rotate, zoom, change lighting, and inspect material or wire views. | |

| Area | Current implementation |
| --- | --- |
| iOS studio | SwiftUI with an interactive SceneKit/GLTFKit2 model viewer, lighting controls, and material/solid/wire views. |
| Concepts | Text or image references, generated concepts, and explicit image selection before 3D generation. |
| Image to 3D | Atlas options including Tripo H3.1, Seed3D, Hunyuan, HI3D, and Meshy; fal options including Rodin, TRELLIS.2, Hunyuan3D, and hybrid. The iOS picker currently suggests Tripo H3.1. |
| Animation | Atlas MiniMax H3, Seedance 2.0 Mini, Seedance 2.0, Seedance 2.5, and Wan 3.0 Prime; fal MiniMax H3 and Seedance 2.5. The iOS picker currently suggests Atlas MiniMax H3. |
| Preview 3D model samples before generating | The 3D confirmation view lets creators inspect interactive sample meshes for supported engines before starting their own generation. Animation choices include Dragon sample videos, with the sample's provider identified clearly. |
| Themes | Lavender and emerald are independent appearance choices. The lavender gallery uses the blue dragon; the emerald gallery uses the lantern explorer. |
| Games | Built-in browser games, game-building handoff, and community-submitted game links with review, voting, and reporting controls. |
| Accounts and billing | Firebase accounts and cloud library; weekly/monthly Creator subscriptions and separate one-time Token packs through Apple purchases and RevenueCat. |

The public [image-to-3D comparison](https://3d-craft.web.app/docs/design/image-to-3d-comparison/index.html) and [video comparison](https://3d-craft.web.app/docs/design/video-provider-comparison/index.html) contain interactive sample outputs and observations. They document particular test runs, not guaranteed results for every prompt or provider. The [3D methodology](docs/design/image-to-3d-comparison/README.md) and [video methodology](docs/design/video-provider-comparison/README.md) remain in this repository.

## Prices and Tokens

The app requests a current quote for the selected model and settings before generation. The confirmation screen shows the required Tokens; Apple provides localized purchase prices for Creator plans and one-time packs. Token costs can differ by model, resolution, duration, and current provider pricing, so this README intentionally does not publish a fixed price table. The weekly and monthly plans renew; Token packs are one-time purchases.

## Architecture

~~~mermaid
flowchart LR
    A["SwiftUI iOS app"] --> C["Firebase Hosting / API"]
    B["React web studio"] --> C
    D["Custom HTTP client with user API key"] --> C
    C --> E["Cloud Run FastAPI"]
    E --> F["Firebase Auth, Firestore, Storage"]
    E --> G["Concept, 3D, and video providers"]
~~~

Firebase Hosting serves the web build and rewrites <code>/api/**</code> to the <code>craft-api</code> Cloud Run service in <code>us-central1</code>. The iOS and web clients point to <code>https://3d-craft.web.app</code>. The cloud API lives in [server/firebase_api.py](server/firebase_api.py); [server/app.py](server/app.py) is the separate local/legacy server.

### Personal API keys

Signed-in users can create scoped, expiring <code>craft_live_</code> keys in the app, view the full key once, and revoke it later. The server stores a hash of the key. API calls use the account's production Token balance; Apple Sandbox Test Tokens cannot be spent through API keys. Keep keys out of repositories and client-side environment variables.

The API works with scripts or clients that support custom HTTP requests, a Bearer key, and the [OpenAPI specification](https://3d-craft.web.app/api/v1/openapi.json). Creators can generate and retrieve 3D objects, create revised versions from new prompts or selected concepts, rename or delete owned assets, and generate animations from prompts, concepts, or existing assets.

| Endpoint | Purpose |
| --- | --- |
| <code>GET /api/v1/creations/quote?engine=rodin&amp;effort=high</code> | Get the maximum Token charge for one concept image plus one 3D model. |
| <code>POST /api/v1/creations</code> | Start a prompt-to-concept-to-3D job with an idempotency key and spending cap. |
| <code>GET /api/v1/creations/{id}</code> | Check the creation's stage, progress, and result. |
| <code>GET /api/v1/animations/quote</code> | Get a quote for a chosen animation model and settings. |
| <code>POST /api/v1/animations</code> | Create a video from a prompt, concept, or existing asset using a selected Atlas or fal model. |
| <code>GET /api/v1/pricing</code> | Compare supported 3D and video model IDs and provider rates. |
| <code>GET /api/v1/models</code> | List selectable models, available providers, supported video resolutions, and quote links. |
| <code>GET /api/v1/assets</code>, <code>PATCH /api/v1/assets/{id}</code>, <code>DELETE /api/v1/assets/{id}</code> | List, rename, or delete owned 3D objects, videos, and concept images. Deletion requires a key with <code>assets:delete</code>. |
| <code>GET /api/keys</code>, <code>POST /api/keys</code> | List or create account-owned API keys. |

For a one-step creation, first request a quote for the same engine and effort. Pass its <code>maxTokens</code> in the POST body; the server rejects a cap below the current quote. For example, after obtaining a quote, a client can send:

~~~json
{
  "idempotencyKey": "my-unique-request-001",
  "prompt": "A friendly blue dragon character",
  "engine": "rodin",
  "effort": "high",
  "maxTokens": 100
}
~~~

The value <code>100</code> above is only an example spending cap, **not** a current quote. Use the returned value from the quote endpoint in a real request. The iOS flow retains its explicit concept-selection and 3D-confirmation steps; this API endpoint is an optional one-step automation workflow.

The API accepts the Atlas image-to-3D engines and Atlas Seedance, MiniMax H3, and Wan video models alongside the existing fal models. Pass the model ID explicitly and quote the exact settings before starting work. See the [API key guide](docs/API_KEYS.md) for model IDs, supported video resolutions, asset management, and examples.

## Run locally

### Web

~~~bash
npm ci
npm run dev
npm run build
~~~

The web app uses the configured Firebase project and cloud API. Provider secrets must stay on the server; a <code>VITE_</code> variable is bundled into browser JavaScript and is not suitable for private keys.

### iOS

Open [ios/CraftStudio.xcodeproj](ios/CraftStudio.xcodeproj) in Xcode, choose an iPhone simulator or your signed physical device, and build the <code>CraftStudio</code> scheme. Open the checked-in project directly: [ios/project.yml](ios/project.yml) is older than the current Xcode project and should not be regenerated over it without first updating its version/build settings.

### Backend

The deployed API uses [server/firebase_api.py](server/firebase_api.py), [server/requirements.txt](server/requirements.txt), and [deploy/cloud-api/Dockerfile](deploy/cloud-api/Dockerfile). Deployment needs the project's Firebase and Google Cloud credentials plus provider secrets; cloning the repository alone does not grant access to generation services. Local web builds do not deploy or charge for a generation.

## Repository guide

- [ios/CraftStudio/Sources](ios/CraftStudio/Sources): native app, model viewer, model/animation selection, themes, games, billing, and API-key screens.
- [src](src): React web studio and account/API access pages.
- [server](server): FastAPI routes, creation orchestration, pricing, keys, and provider integrations.
- [docs/design/image-to-3d-comparison](docs/design/image-to-3d-comparison): tested 3D model examples and comparison notes.
- [docs/design/video-provider-comparison](docs/design/video-provider-comparison): tested video provider examples and comparison notes.
- [firebase.json](firebase.json), [firestore.rules](firestore.rules), [storage.rules](storage.rules): Hosting/API routing and Firebase rules.

Generated images, models, and videos are user content. Review the displayed quote and source image before submitting a paid generation.
