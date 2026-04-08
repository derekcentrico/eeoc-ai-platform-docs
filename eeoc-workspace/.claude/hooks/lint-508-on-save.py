"""PostToolUse hook for Write|Edit — runs 508 lint on saved HTML/CSS files."""
import json
import os
import subprocess
import sys

data = json.load(sys.stdin)
path = data.get("tool_input", {}).get("file_path", "")

if path.endswith((".html", ".css")):
    hook_dir = os.path.dirname(os.path.abspath(__file__))
    result = subprocess.run(
        [sys.executable, os.path.join(hook_dir, "lint-508.py"), path],
        capture_output=True,
        text=True,
    )
    if result.stdout.strip():
        print("508 lint warnings:")
        print(result.stdout.strip())
