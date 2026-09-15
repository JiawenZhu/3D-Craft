# Own ChatGPT account in the local iOS studio

The Gemini renderer remains independent of ChatGPT login. A user can also connect
**their own ChatGPT account** for the account's available prompt-planning models
and Codex's built-in **GPT Image 2** renderer. This integration is for the existing
loopback-only development API, not a production multi-tenant authentication service.

## Official protocol and model naming

The implementation uses the installed Codex CLI's `app-server` JSON-RPC interface,
not CueFlow tokens or undocumented `chatgpt.com/backend-api` HTTP calls.
Verified locally with Codex CLI **0.147.0**, including its generated JSON schemas.

- [App-server protocol](https://learn.chatgpt.com/docs/app-server)
- [Built-in image generation](https://learn.chatgpt.com/docs/image-generation)

The image guide identifies the built-in renderer as `gpt-image-2`. Its usage counts
toward the user's Codex limits. The image tool's RPC result does not expose a
Sunburst model or a maximum-quality/resolution selector, so the UI must not label
this path as GPT Image 2.5, guaranteed 2K, or guaranteed maximum quality.
The selectable catalog ID `codex-gpt-image-2` maps to actual provenance
`model: gpt-image-2, provider: chatgpt`.

## API contract

All routes require the existing mobile session bearer token and loopback access.
No OAuth access/refresh token is returned to iOS.

- `GET /api/mobile/ai/account`: `available`, `connected`, optional `email`,
  `models: [{id,name,reasoningEfforts}]`, optional `pendingLoginId` and
  `loginStatus`, `imageGenerationSupported`, `imageGenerationReason`.
- `POST /api/mobile/ai/login`: official `chatgptDeviceCode` response with
  `loginId`, `verificationUrl`, and `userCode`. The user opens the verification
  URL and approves their own account. No automatic sign-in is performed.
- `POST /api/mobile/ai/login/cancel`: `{loginId}`; the ID must belong to this owner.
- `POST /api/mobile/ai/logout`: removes this isolated account's managed login.

Poll account status while a device code is pending. The protocol does not expose
an expiry timestamp or a polling interval. Unfinished local login attempts are
cancelled after ten minutes on the next status read. Catalog results are returned
only after this isolated account is connected. Available prompt-model IDs and
reasoning efforts come from `model/list`, not a hardcoded list of public models.

## Isolation and execution

Each mobile owner gets a SHA-256-named directory under
`~/Library/Application Support/3D Craft/Codex Accounts/`. Override only with a
private outside-project path using `CRAFT_CODEX_ACCOUNTS_DIR`. Set
`CRAFT_CODEX_BINARY` if Codex is not on PATH or at `~/.local/bin/codex`.

Directories are mode 0700. Configuration/auth files are mode 0600 and child
process umask is 0077. `cli_auth_credentials_store = "file"` and a per-child
`CODEX_HOME` prevent reuse of ambient `~/.codex` or Keychain authentication.
API keys and ambient Codex configuration environment variables are not inherited.
Auth storage is outside every asset-serving route. The private account directory
retains the Codex-managed login until the user disconnects; never copy it into
public assets, logs, support reports, or repository backups.

Warm processes are bounded to eight owners, reclaimed after fifteen minutes idle
when another request arrives, and terminated on clean API process exit. Calls
are multiplexed, allowing account-status polling during a generation. Each owner
has one generation/planning operation at a time; logout refuses while it runs.
Concurrent anchored image views queue on this owner lock for at most fifteen
minutes; each image turn deadline starts only after it acquires the lock.

Planning threads are ephemeral, read-only, without environment access or selected
capability roots. Shell, exec, browser, computer use, plugins, apps, memories,
subagents and image generation are disabled. Image threads enable only the
built-in image tool. Image threads retain the default tool environment and code-mode host required by the native image extension; planning still supplies an empty environment list. Incoming client-tool/approval requests are rejected. Image
references are explicitly supplied as data URLs. There is no arbitrary URL fetch.
Provider model fallback is disabled. Planner results must satisfy the supplied
JSON Schema. Image output must be a valid PNG, JPEG or WebP, supplied as inline
bytes or a file under that owner's isolated account directory.

Prompt turns have a 45-second deadline; image turns have a 300-second deadline.
Timeouts interrupt the turn; ambiguous turn-start failures close the isolated
process. There is no automatic retry, model substitution, or rendering fallback.

## Verification

`venv/bin/python -m unittest discover -s tests -p 'test_codex_bridge.py'`

Nine offline tests cover account isolation and permissions, ambient credential
exclusion, logged-out catalog behavior, cross-owner login cancellation, exact
model/schema planning, timeout interruption, concurrent side-view serialization, verified image artifacts and route
authentication. An isolated live app-server smoke verified initialization,
account/read (disconnected), image capability discovery and read-only ephemeral
thread creation with network access disabled. It did not start device-code login,
a paid planning turn, or image generation. End-to-end account generation needs the
user to connect their own account and initiate a generation.

## iPhone sign-in recovery — 2026-09-12

OpenAI device-code login requires the account owner to enable device-code authorization in ChatGPT Settings → Security (or the workspace administrator to enable it). The app now links to that setting before sign-in and keeps the code visible until the user opens the official verification page. Get a new code cancels any previous pending attempt, including one left on the server after restarting the app. The app does not change or bypass the account setting.

Official source: https://learn.chatgpt.com/docs/auth#preferred-device-code-authentication-beta

The signed Debug build was rebuilt and installed on the paired physical iPhone. The focused simulator recovery test passed: request a code, replace the pending attempt, and cancel. This check did not authorize a ChatGPT account. A private, device-provisioned IPA is available in the ignored `ios/.build-device/exports/3DCraft-Development.ipa`; its review service requires the same Mac and LAN gateway.


## Connected-account generation repair — 2026-09-12

The account endpoint now returns image availability with account status in one snapshot. iOS publishes that snapshot before clearing the login task ID, preventing SwiftUI task cancellation from leaving the image picker disconnected. A revision guard discards stale catalog fetches; API requests bypass URL response caching.

The image bridge no longer disables `code_mode_host` or removes the default environment from image threads. These are needed by the native image extension. Planning retains its empty environment list, and other tool restrictions remain.

Verified with the connected account: GPT-5.6-Sol returned a valid conversation plan in 7.3 seconds; GPT Image 2 generated an image in 30.5 seconds; the final production configuration generated a reference-based edit in 32.3 seconds. Artifacts are in `docs/design/chat-creation/chatgpt-connection-test.png` and `chatgpt-reference-test.png`. All 72 focused backend tests and native account/image selection tests passed. The account catalog (including hidden models) did not include GPT-6; a native test confirms GPT-6 is selectable when a future account catalog returns it.

The fixed signed build was installed and launched on the paired physical iPhone. The backend was restarted while no work was active; the private LAN gateway responded successfully. Full interaction testing on the physical phone is left to the user. Export: `ios/.build-device/exports/3DCraft-ChatGPT-Fix-2026-09-12.ipa`. Keep the Mac and gateway running on the same network for testing.
