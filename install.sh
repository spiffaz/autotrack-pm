#!/usr/bin/env bash
# AutoTrack PM - Installer
# Installs the PM skill and hooks globally for Claude Code

set -euo pipefail

AUTOTRACK_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "AutoTrack PM - Installing..."
echo ""

# Check prerequisites
if ! command -v gh &>/dev/null; then
  echo "Error: GitHub CLI (gh) is required. Install: https://cli.github.com"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "Error: GitHub CLI not authenticated. Run: gh auth login"
  exit 1
fi

# 1. Install skill globally
SKILL_DIR="$CLAUDE_DIR/skills/pm"
mkdir -p "$SKILL_DIR"
cp "$AUTOTRACK_DIR/skills/pm/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "Installed skill: $SKILL_DIR/SKILL.md"

# 2. Install hook script globally
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
mkdir -p "$SCRIPTS_DIR"
cp "$AUTOTRACK_DIR/scripts/pm-hook.sh" "$SCRIPTS_DIR/pm-hook.sh"
chmod +x "$SCRIPTS_DIR/pm-hook.sh"
echo "Installed script: $SCRIPTS_DIR/pm-hook.sh"

# 3. Merge hooks into user settings
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Use python3 to safely merge hooks into existing settings
python3 << 'PYEOF'
import json, sys, os

settings_path = os.path.expanduser("~/.claude/settings.json")
scripts_dir = os.path.expanduser("~/.claude/scripts")

with open(settings_path) as f:
    settings = json.load(f)

hook_command_base = f'bash "{scripts_dir}/pm-hook.sh"'

new_hooks = {
    "SessionStart": [
        {
            "matcher": "startup|compact|resume",
            "hooks": [
                {
                    "type": "command",
                    "command": f'{hook_command_base} session-start',
                    "timeout": 10000,
                    "statusMessage": "Loading project state..."
                }
            ]
        }
    ],
    "PreCompact": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": f'{hook_command_base} pre-compact',
                    "timeout": 10000,
                    "async": True
                }
            ]
        }
    ],
    "TaskCompleted": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": f'{hook_command_base} task-completed',
                    "timeout": 10000,
                    "async": True
                }
            ]
        }
    ]
}

if "hooks" not in settings:
    settings["hooks"] = {}

# Merge: add autotrack hooks without overwriting existing hooks for same events
for event, handlers in new_hooks.items():
    if event not in settings["hooks"]:
        settings["hooks"][event] = handlers
    else:
        # Check if autotrack hook already exists
        existing_commands = [
            h.get("command", "")
            for group in settings["hooks"][event]
            for h in group.get("hooks", [])
        ]
        if not any("pm-hook.sh" in cmd for cmd in existing_commands):
            settings["hooks"][event].extend(handlers)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Merged hooks into settings.json")
PYEOF

echo ""
echo "Installation complete!"
echo ""
echo "AutoTrack PM is now active globally for all Claude Code sessions."
echo ""
echo "How it works:"
echo "  - Just talk to Claude normally. It tracks work automatically."
echo "  - Say 'fix the login bug' -- Claude creates an issue, fixes it, closes it."
echo "  - Say 'the sidebar also breaks' mid-work -- Claude logs it separately."
echo "  - Say 'what's left to do?' -- Claude shows your open issues."
echo "  - Context compresses? State auto-saves and auto-restores."
echo ""
echo "No commands to learn. No workflow to follow. Just work."
