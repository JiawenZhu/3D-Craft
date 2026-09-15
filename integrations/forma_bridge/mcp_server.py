"""Stdio MCP for desktop agents. This process is never a public file server."""
from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from .client import StudioClient

mcp = FastMCP(
    "Forma Studio",
    instructions="Create 3D assets using the user's local Forma Studio. Read health first. Generation invokes configured paid providers; submit only when the user requests generation, then poll the returned id. Never resubmit on a timeout. File paths must stay within FORMA_WORKSPACE. Multiview inputs must depict the same rigid object from correctly labelled views. Generated assets need visual review before game use.",
)
READ = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)
WRITE = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False, openWorldHint=True)


def call(method, *args, **kwargs):
    client = StudioClient()
    try:
        return getattr(client, method)(*args, **kwargs)
    finally:
        client.close()


@mcp.tool(annotations=READ)
def studio_health() -> dict:
    """Check available reconstruction engines and concept generation on the local Studio."""
    return call("health")


@mcp.tool(annotations=READ)
def list_assets(limit: int = 20) -> list[dict]:
    """List real generated assets, newest first, including ids and mesh metadata."""
    return call("assets", limit)


@mcp.tool(annotations=WRITE)
def generate_asset(prompt: str = "", images: list[str] | None = None, directions: list[str] | None = None, workflow: str = "concept", engine: str = "trellis-2", seed: int | None = None) -> dict:
    """Start ONE generation; paid providers may charge. Returns an id to poll.

    concept: text and/or one local image -> concept -> 3D.
    direct: 1-5 local images -> 3D (text-only supported by rodin).
    Engines: trellis-2, hunyuan3d-2.1, rodin.
    Multiple images need matching unique directions (front/back/left/right).
    Hunyuan requires exactly front/back/left. Images must be in FORMA_WORKSPACE.
    """
    return call("generate", prompt, images, directions, workflow, engine, seed)


@mcp.tool(annotations=READ)
def generation_status(generation_id: str) -> dict:
    """Poll a run- or job- id. On done, use assetIds with download_asset. No regeneration."""
    return call("status", generation_id)


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False, openWorldHint=False))
def download_asset(asset_id: str, output: str, format: str = "glb") -> dict:
    """Download an asset to FORMA_WORKSPACE without overwriting files. Returns path, byte size and SHA-256.

    glb includes materials; obj must use a .zip output (mesh + textures).
    stl and ply are supported but do not retain the complete GLB material setup.
    """
    return call("download", asset_id, output, format)


def main():
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
