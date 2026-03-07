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
GLOBAL_CONFIG="$HOME/.claude/pm-config.json"
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

# Get project name (directory name as fallback)
get_project_name() {
  local repo
  repo=$(get_state "repo")
  if [[ -n "$repo" && "$repo" != "None" ]]; then
    basename "$repo"
  else
    basename "$PROJECT_ROOT"
  fi
}

# Read global config
get_global_config() {
  local field="$1"
  if [[ -f "$GLOBAL_CONFIG" ]]; then
    python3 -c "import sys,json; d=json.load(open('$GLOBAL_CONFIG')); print(d.get('$field','') or '')" 2>/dev/null
  else
    echo ""
  fi
}

# Resolve target repo for gh commands
resolve_repo_flag() {
  local tracking
  tracking=$(get_state "tracking")
  if [[ "$tracking" == "local" ]]; then
    echo ""  # no --repo flag needed, uses current repo
  elif [[ "$tracking" == "off" ]]; then
    echo "OFF"
  else
    # hub mode (default)
    local hub
    hub=$(get_global_config "hub_repo")
    if [[ -n "$hub" ]]; then
      echo "--repo $hub"
    else
      echo ""  # no hub configured, fall back to local
    fi
  fi
}

# --- Event Handlers ---

handle_session_start() {
  local source
  source=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('source','startup'))" 2>/dev/null || echo "startup")

  # Ensure state file exists
  if [[ ! -f "$STATE_FILE" ]]; then
    local repo
    repo=$(detect_repo)
    local default_tracking
    default_tracking=$(get_global_config "default_tracking")
    default_tracking="${default_tracking:-hub}"
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "{\"repo\":\"${repo:-null}\",\"active_issue\":null,\"sprint_label\":null,\"tracking\":\"$default_tracking\"}" > "$STATE_FILE"
  fi

  local active_issue
  active_issue=$(get_state "active_issue")

  # Build context to inject
  local context=""

  local tracking
  tracking=$(get_state "tracking")
  if [[ "$tracking" == "off" ]]; then
    return
  fi

  local repo_flag
  repo_flag=$(resolve_repo_flag)

  if [[ -n "$active_issue" && "$active_issue" != "None" ]]; then
    local issue_info
    issue_info=$(gh issue view "$active_issue" $repo_flag --json title,labels,state --jq '"\(.state) | #'"$active_issue"' \(.title) [\(.labels | map(.name) | join(","))]"' 2>/dev/null || echo "")
    if [[ -n "$issue_info" ]]; then
      context="[AutoTrack] Active issue: $issue_info"
      if [[ -n "$repo_flag" ]]; then
        context="$context (in hub)"
      fi
    fi
  fi

  local sprint
  sprint=$(get_state "sprint_label")
  if [[ -n "$sprint" && "$sprint" != "None" ]]; then
    local sprint_count
    sprint_count=$(gh issue list $repo_flag --label "$sprint" --state open --json number --jq 'length' 2>/dev/null || echo "0")
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
  local tracking
  tracking=$(get_state "tracking")
  if [[ "$tracking" == "off" ]]; then return; fi

  local active_issue
  active_issue=$(get_state "active_issue")

  if [[ -n "$active_issue" && "$active_issue" != "None" ]]; then
    local repo_flag
    repo_flag=$(resolve_repo_flag)
    local diff_stat
    diff_stat=$(git diff --stat HEAD 2>/dev/null | tail -5 || echo "no changes")
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    local project
    project=$(get_project_name)

    gh issue comment "$active_issue" $repo_flag --body "**AutoTrack: Context snapshot (pre-compact)**
Project: \`$project\`
Branch: \`$branch\`
Changes:
\`\`\`
$diff_stat
\`\`\`" 2>/dev/null || true
  fi
}

handle_task_completed() {
  local tracking
  tracking=$(get_state "tracking")
  if [[ "$tracking" == "off" ]]; then return; fi

  local active_issue
  active_issue=$(get_state "active_issue")

  if [[ -n "$active_issue" && "$active_issue" != "None" ]]; then
    local repo_flag
    repo_flag=$(resolve_repo_flag)
    local last_commit
    last_commit=$(git log -1 --oneline 2>/dev/null || echo "work completed")
    gh issue comment "$active_issue" $repo_flag --body "Task completed: $last_commit" 2>/dev/null || true
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
