# Forma CLI and MCP — local preview

The bridge is implemented and uses the same generation jobs, concept pipeline and exports as Studio. It is installed from this checkout; no public package or hosted MCP service has been published. The existing UI is retained. Open **OmniCraft → Connect your agent** for setup instructions.

## Install and connect

Run from the repository root with the Studio API running on `127.0.0.1:8000`:

```sh
venv/bin/python -m pip install -e ./integrations
venv/bin/forma health
venv/bin/forma --workspace "/absolute/path/to/your/game" mcp-config
```

The last command prints a JSON `mcpServers` entry with the actual Python executable, module and workspace. Paste that entry into clients that accept this JSON format. Clients with another configuration format use the same `command`, `args` and environment values in their MCP settings. No client configuration is changed automatically. If this checkout uses `server/.venv`, substitute that interpreter path consistently.

The server command is `python -m forma_bridge.mcp_server`. The package also installs `forma` and `forma-mcp` entry points into the Python environment. Set:

| Environment | Meaning |
| --- | --- |
| `FORMA_WORKSPACE` | Existing folder allowed for image inputs and model output. Defaults to the process working directory; set it explicitly in MCP clients. |
| `FORMA_API_URL` | Defaults to `http://127.0.0.1:8000`. This preview only accepts loopback API hosts. |

Provider credentials remain in the inference server. The bridge does not load `.env`, read provider keys or put them in MCP configuration. Files resolve inside the chosen workspace, including symlink targets. Downloads never overwrite an existing file and return a byte count and SHA-256 digest. Do not change the workspace symlinks while the bridge is writing files.

## CLI workflows

Use `--workspace` before the subcommand. Replace `run-ID`, `job-ID` and `a-ID` with returned identifiers.

```sh
# Text or photo -> concepts -> 3D. Submission invokes configured paid providers.
venv/bin/forma generate --prompt "A stylized stone watchtower"
venv/bin/forma --workspace "/path/to/game" generate --image references/tower.jpg --prompt "Keep the silhouette and stonework"

# Poll without regenerating. --wait emits the submission id on stderr first.
venv/bin/forma status run-ID --wait
venv/bin/forma assets --limit 10
venv/bin/forma --workspace "/path/to/game" pull a-ID --output assets/tower.glb

# Already prepared single image -> mesh, skipping the concept stage.
venv/bin/forma --workspace "/path/to/game" generate --workflow direct --image references/tower.png --seed 0

# Real, correctly labelled views of the same object. Hunyuan needs exactly these three.
venv/bin/forma --workspace "/path/to/game" generate --workflow direct --engine hunyuan3d-2.1 --image references/front.png --direction front --image references/back.png --direction back --image references/left.png --direction left

# OBJ is a ZIP containing the mesh and its material/texture companions.
venv/bin/forma --workspace "/path/to/game" pull a-ID --format obj --output assets/tower.zip
```

GLB is the preferred complete material handoff. STL and PLY do not retain the full GLB material setup. The bridge does not create collision meshes, rigging, LODs, native Unity/Unreal packages or scale calibration. Review the asset in the destination engine before use.

Concept mode accepts text and/or one image. Direct mode accepts up to five images, with explicit unique view labels for multiview. Text-only direct generation is exposed for Rodin. Files are limited to 20 MB each; exports to 512 MB. Generation POSTs are never automatically retried after a timeout: check Studio before submitting again, since the server may have accepted the first request. Direct job state currently lives in server memory and can be lost when the backend restarts.

## MCP tools

| Tool | Behavior |
| --- | --- |
| `studio_health` | Read engine and concept availability. |
| `list_assets` | Read real asset ids and metadata. |
| `generate_asset` | Submit one concept or direct job; returns an id immediately. May incur provider charges. |
| `generation_status` | Read the returned id until `done` or `failed`; successful results include `assetIds`. |
| `download_asset` | Write an export into the selected workspace without overwriting files. |

Example request to a connected agent: “Use Forma to turn references/tower.jpg into a stylized game prop. Wait for the job and download the GLB to assets/tower.glb.” The agent should submit once, poll, then download. Tool descriptions and MCP annotations distinguish reads, generation and local file writes.

## ChatGPT and hosted access

This implementation is a **stdio desktop bridge**, verified with the official MCP Python client. It has not been installed or tested inside Claude Code, Antigravity or ChatGPT, so there is no claim of client-specific certification.

OpenAI's current developer documentation supports a public HTTPS MCP endpoint or Secure MCP Tunnel for development; public submission still requires HTTPS. A private tunnel is not configured here. Production account tools also need authentication discovery. See [OpenAI connection documentation](https://developers.openai.com/plugins/deploy/connect-chatgpt) and the [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk/tree/v1.30.0).

Do not expose the current anonymous Studio API as a multi-user service. The production boundary and mobile roadmap are in [COMMERCIAL_FOUNDATION.md](COMMERCIAL_FOUNDATION.md).

## Verified September 9, 2026

- Package installation and `forma mcp-config` succeeded in the checkout venv.
- A real stdio MCP client initialized, discovered all five tools, read health/assets/an existing run, and downloaded the experimental TRELLIS.2 GLB (8,505,552 bytes).
- CLI downloaded the Rodin GLB (9,826,584 bytes). File signatures and hashes were checked; originals were preserved.
- Image upload and text submission pass through the actual FastAPI form handlers in tests, with billable workers replaced. Bridge verification made no additional paid generation calls.
- Twenty-one regression tests cover reconstruction contracts plus the bridge, including no retry after timeouts, traversal/symlink rejection, interrupted/invalid downloads, no overwrite and view labels.
- Browser checks at localhost:3000: setup menu, modal, copy feedback, Escape dismissal; screenshots at desktop 1280×720 and phone width 390×844; no console warnings/errors captured in the test tab. Phone camera hardware, native mobile apps, public transport, OAuth, billing and game-engine imports remain untested.
