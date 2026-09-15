"""JSON output on stdout, actionable failures on stderr."""
import argparse
import json
import sys

from .client import DIRECTIONS, ENGINES, FORMATS, StudioClient


def main():
    parser = argparse.ArgumentParser(prog="forma", description="Generate and pull 3D assets from your local Forma Studio")
    parser.add_argument("--workspace", help="Directory allowed for image inputs and model downloads (default: FORMA_WORKSPACE or cwd)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("health")
    sub.add_parser("mcp-config", help="Print a JSON MCP configuration with this Python executable and workspace")
    assets = sub.add_parser("assets")
    assets.add_argument("--limit", type=int, default=20)
    gen = sub.add_parser("generate")
    gen.add_argument("--prompt", default="")
    gen.add_argument("--image", action="append", default=[])
    gen.add_argument("--direction", action="append", choices=DIRECTIONS, default=[])
    gen.add_argument("--workflow", choices=("concept", "direct"), default="concept")
    gen.add_argument("--engine", choices=ENGINES, default="trellis-2")
    gen.add_argument("--seed", type=int)
    gen.add_argument("--wait", action="store_true")
    gen.add_argument("--timeout", type=int, default=1800)
    status = sub.add_parser("status")
    status.add_argument("id")
    status.add_argument("--wait", action="store_true")
    status.add_argument("--timeout", type=int, default=1800)
    pull = sub.add_parser("pull")
    pull.add_argument("asset_id")
    pull.add_argument("--output", required=True)
    pull.add_argument("--format", choices=FORMATS, default="glb")
    args = parser.parse_args()
    client = None
    try:
        client = StudioClient(workspace=args.workspace)
        if args.command == "mcp-config":
            result = {"mcpServers": {"forma": {"command": sys.executable, "args": ["-m", "forma_bridge.mcp_server"], "env": {"FORMA_WORKSPACE": str(client.workspace), "FORMA_API_URL": client.base_url}}}}
        elif args.command == "health":
            result = client.health()
        elif args.command == "assets":
            result = client.assets(args.limit)
        elif args.command == "generate":
            result = client.generate(args.prompt, args.image, args.direction, args.workflow, args.engine, args.seed)
            if args.wait:
                # Emit the identifier before polling so an interrupted wait is resumable.
                print(json.dumps(result), file=sys.stderr, flush=True)
                result = client.wait(result["id"], args.timeout)
        elif args.command == "status":
            result = client.wait(args.id, args.timeout) if args.wait else client.status(args.id)
        else:
            result = client.download(args.asset_id, args.output, args.format)
        print(json.dumps(result, indent=2))
        if isinstance(result, dict) and result.get("status") in ("failed", "cancelled"):
            return 1
        return 0
    except Exception as exc:
        print(f"forma: {exc}", file=sys.stderr)
        return 1
    finally:
        if client:
            client.close()


if __name__ == "__main__":
    sys.exit(main())
