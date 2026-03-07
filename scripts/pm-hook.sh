#!/usr/bin/env bash
# AutoTrack PM - Hook handler
# Called by Claude Code hooks for automatic state management
# Usage: pm-hook.sh <event> [args]

set -euo pipefail

# Find project root (where .claude/ lives)
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.claude" ]] || [[ -d "$dir/.git" ]]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo "$PWD"
}

PROJECT_ROOT="$(find_project_root)"
STATE_FILE="$PROJECT_ROOT/.claude/pm-state.json"
INPUT=$(cat)

# Read state file
read_state() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo '{"repo":null,"active_issue":null,"sprint_label":null}'
  fi
}

# Get a field from state
get_state() {
  local field="$1"
  read_state | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field','') or '')" 2>/dev/null
}

# Update state field
set_state() {
  local field="$1"
  local value="$2"
  mkdir -p "$(dirname "$STATE_FILE")"
  if [[ -f "$STATE_FILE" ]]; then
    python3 -c "
import json,sys
with open('$STATE_FILE') as f: d=json.load(f)
d['$field']=$value
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2)
"
  else
    python3 -c "
import json
d={'repo':None,'active_issue':None,'sprint_label':None}
d['$field']=$value
with open('$STATE_FILE','w') as f: json.dump(d,f,indent=2)
"
  fi
}

# Detect repo name
detect_repo() {
  gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo ""
}

# --- Event Handlers ---

handle_session_start() {
  local source
  source=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('source','startup'))" 2>/dev/null || echo "startup")

  # Ensure state file exists
  if [[ ! -f "$STATE_FILE" ]]; then
    local repo
    repo=$(detect_repo)
    if [[ -n "$repo" ]]; then
      mkdir -p "$(dirname "$STATE_FILE")"
      echo "{\"repo\":\"$repo\",\"active_issue\":null,\"sprint_label\":null}" > "$STATE_FILE"
    fi
  fi

  local active_issue
  active_issue=$(get_state "active_issue")

  # Build context to inject
  local context=""

  if [[ -n "$active_issue" && "$active_issue" != "None" ]]; then
    local issue_info
    issue_info=$(gh issue view "$active_issue" --json title,labels,state --jq '"\(.state) | #'"$active_issue"' \(.title) [\(.labels | map(.name) | join(","))]"' 2>/dev/null || echo "")
    if [[ -n "$issue_info" ]]; then
      context="[AutoTrack] Active issue: $issue_info"
    fi
  fi

  local sprint
  sprint=$(get_state "sprint_label")
  if [[ -n "$sprint" && "$sprint" != "None" ]]; then
    local sprint_count
    sprint_count=$(gh issue list --label "$sprint" --state open --json number --jq 'length' 2>/dev/null || echo "0")
    context="$context | Sprint: $sprint ($sprint_count open)"
  fi

  if [[ -n "$context" ]]; then
    # Return context for injection via hookSpecificOutput
    python3 -c "
import json
output = {
  'hookSpecificOutput': {
    'hookEventName': 'SessionStart',
    'additionalContext': '''$context'''
  }
}
print(json.dumps(output))
"
  fi
}

handle_pre_compact() {
  local active_issue
  active_issue=$(get_state "active_issue")

  if [[ -n "$active_issue" && "$active_issue" != "None" ]]; then
    # Save current work state as issue comment
    local diff_stat
    diff_stat=$(git diff --stat HEAD 2>/dev/null | tail -5 || echo "no changes")
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")

    gh issue comment "$active_issue" --body "**AutoTrack: Context snapshot (pre-compact)**
Branch: \`$branch\`
Changes:
\`\`\`
$diff_stat
\`\`\`" 2>/dev/null || true
  fi
}

handle_task_completed() {
  # When a Claude Code Task completes, check if we should sync to GitHub
  local active_issue
  active_issue=$(get_state "active_issue")

  if [[ -n "$active_issue" && "$active_issue" != "None" ]]; then
    local last_commit
    last_commit=$(git log -1 --oneline 2>/dev/null || echo "work completed")
    gh issue comment "$active_issue" --body "Task completed: $last_commit" 2>/dev/null || true
  fi
}

# --- Main ---

EVENT="${1:-}"

case "$EVENT" in
  session-start)
    handle_session_start
    ;;
  pre-compact)
    handle_pre_compact
    ;;
  task-completed)
    handle_task_completed
    ;;
  *)
    echo "Unknown event: $EVENT" >&2
    exit 1
    ;;
esac
