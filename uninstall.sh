#!/usr/bin/env bash
# AutoTrack PM - Uninstaller
# Removes the PM skill, scripts, and hooks

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"

echo "AutoTrack PM - Uninstalling..."

# 1. Remove skill
rm -rf "$CLAUDE_DIR/skills/pm"
echo "Removed skill"

# 2. Remove script
rm -f "$CLAUDE_DIR/scripts/pm-hook.sh"
echo "Removed script"

# 3. Remove hooks from settings
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
  python3 << 'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")

with open(settings_path) as f:
    settings = json.load(f)

if "hooks" in settings:
    for event in list(settings["hooks"].keys()):
        settings["hooks"][event] = [
            group for group in settings["hooks"][event]
            if not any("pm-hook.sh" in h.get("command", "") for h in group.get("hooks", []))
        ]
        if not settings["hooks"][event]:
            del settings["hooks"][event]
    if not settings["hooks"]:
        del settings["hooks"]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Removed hooks from settings.json")
PYEOF
fi

echo ""
echo "AutoTrack PM has been uninstalled."
echo "Your GitHub Issues and pm-state.json files in projects are untouched."
