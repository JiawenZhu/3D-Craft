"""Reproducible Godot web export, native physics checks, and real scene captures."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "games/forma-playground"
OUTPUT = ROOT / "public/games/forma"

def run(command, *, logfile=None):
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if logfile:
        Path(logfile).write_text(result.stdout)
    # Godot can return zero for a failed script import. Check diagnostics as well.
    if result.returncode or "SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout:
        print(result.stdout, file=sys.stderr)
        raise SystemExit(result.returncode or 1)
    print("\n".join(line for line in result.stdout.splitlines() if line.startswith(("PASS", "RESULT", "CAPTURE", "Prepared"))))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", action="store_true", help="Run production physics and full level completion tests")
    parser.add_argument("--covers", action="store_true", help="Render cover images with the real Godot viewport (requires a GPU)")
    args = parser.parse_args()
    choices = [os.environ.get("GODOT_BIN"), shutil.which("godot"), "/Applications/Godot.app/Contents/MacOS/Godot", str(Path.home()/"Downloads/Godot.app/Contents/MacOS/Godot")]
    godot = next((p for p in choices if p and Path(p).is_file()), None)
    if not godot:
        parser.error("Set GODOT_BIN to your installed Godot 4.7.2 executable.")
    run([sys.executable, str(ROOT/"scripts/prepare_game_assets.py")])
    base = [godot, "--headless", "--path", str(PROJECT)]
    run(base + ["--editor", "--import"], logfile="/tmp/forma-game-import.log")
    texture_changes = False
    for texture_import in (PROJECT/"assets").glob("*.import"):
        if texture_import.name.endswith((".png.import", ".webp.import")):
            original = texture_import.read_text()
            limited = original.replace("process/size_limit=0", "process/size_limit=2048")
            if original != limited:
                texture_import.write_text(limited)
                texture_changes = True
    if texture_changes:
        run(base + ["--editor", "--import"], logfile="/tmp/forma-game-texture-import.log")
    if args.test:
        cases = [("physics_test", mode, "scout") for mode in ["arena", "race", "ruins"]]
        cases += [("competition_test", mode, vehicle) for mode in ["arena", "race"] for vehicle in ["scout", "heavy", "cat"]]
        cases += [("physics_test", "ruins", "cat"), ("dragon_test", "dragon", "scout"), ("survivor_test", "survivor", "scout"), ("survivor_controls_test", "survivor", "scout")]
        for suite, mode, vehicle in cases:
            print(f"Testing {suite}: {mode} / {vehicle}", flush=True)
            run(base + ["--fixed-fps", "60", "--script", f"res://tests/{suite}.gd", "--", f"mode={mode}", f"vehicle={vehicle}"], logfile=f"/tmp/forma-{suite}-{mode}-{vehicle}.log")
        return
    if args.covers:
        covers = ROOT/"public/games/covers"
        covers.mkdir(parents=True, exist_ok=True)
        for mode in ["arena", "race", "ruins", "dragon", "survivor"]:
            run([godot, "--path", str(PROJECT), "--fixed-fps", "60", "--script", "res://tests/capture.gd", "--", f"mode={mode}"], logfile=f"/tmp/forma-capture-{mode}.log")
            shutil.copyfile(f"/tmp/forma-game-{mode}.jpg", covers/f"{mode}.jpg")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    run(base + ["--export-release", "Web", str(OUTPUT/"index.html")], logfile="/tmp/forma-game-export.log")
    for name in ["index.html", "index.js", "index.wasm", "index.pck"]:
        if not (OUTPUT/name).is_file() or (OUTPUT/name).stat().st_size == 0:
            raise SystemExit(f"Missing or empty export: {name}")
    # Smoke the actual packed resources: source-tree tests cannot catch missing exports.
    for mode in ["arena", "race", "ruins", "dragon", "survivor"]:
        run([godot, "--headless", "--main-pack", str(OUTPUT/"index.pck"), "--quit-after", "12", "--", f"mode={mode}"], logfile=f"/tmp/forma-packed-{mode}.log")
    html = OUTPUT/"index.html"
    content = html.read_text()
    marker = "function displayFailureNotice(err) {"
    if marker not in content:
        raise SystemExit("Godot HTML failure callback changed; update error forwarding before shipping.")
    content = content.replace(marker, marker + "\n\t\t\twindow.parent.postMessage({channel:'forma-error',message:String(err)},location.origin);")
    prewarm_marker = "(function () {"
    prewarm_code = """(function () {
\tconst params = new URLSearchParams(window.location.search);
\tif (params.get('prewarm') === '1') {
\t\tPromise.all([fetch('index.wasm'), fetch('index.pck'), fetch('index.js')])
\t\t\t.then(() => {
\t\t\t\ttry { window.webkit?.messageHandlers?.craftGame?.postMessage({ action: 'prewarmed' }); } catch (e) {}
\t\t\t\ttry { window.parent?.postMessage({ channel: 'forma-prewarmed' }, '*'); } catch (e) {}
\t\t\t}).catch(console.error);
\t\treturn;
\t}"""
    if prewarm_marker in content and "params.get('prewarm')" not in content:
        content = content.replace(prewarm_marker, prewarm_code, 1)
    progress_marker = "'onProgress': function (current, total) {"
    progress_code = """'onProgress': function (current, total) {
\t\t\t\tif (window.parent && window.parent !== window) {
\t\t\t\t\twindow.parent.postMessage({ channel: 'forma-progress', current, total, percent: total > 0 ? Math.min(100, Math.round((current / total) * 100)) : 0 }, '*');
\t\t\t\t}"""
    if progress_marker in content and "forma-progress" not in content:
        content = content.replace(progress_marker, progress_code, 1)
    html.write_text(content)
    size = sum((OUTPUT/name).stat().st_size for name in ["index.js", "index.wasm", "index.pck"])
    print(f"Web export ready: {OUTPUT} ({size/1024**2:.1f} MiB before HTTP compression)")
    print("Open localhost:3000 and select Game. This command does not deploy the site.")

if __name__ == "__main__":
    main()
