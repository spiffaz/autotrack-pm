# AutoTrack PM

**Zero-token project management for Claude Code.**

AutoTrack replaces Jira, Linear, and markdown tracking files with automatic issue tracking that costs almost nothing. You don't invoke commands. You don't manage a backlog file. You just talk to Claude, and it tracks everything via GitHub Issues.

## The Problem

Every AI coding workflow has the same issue: tracking work burns tokens.

| Approach | Cost per interaction |
|---|---|
| Loading a BACKLOG.md file | ~3,000-9,000 tokens |
| MCP calls to Jira/Linear | ~500-2,000 tokens |
| CCPM slash commands | ~1,000-3,000 tokens |
| **AutoTrack** | **~0-200 tokens** |

AutoTrack uses Claude Code **hooks** (shell scripts, zero LLM cost) for state management and a **skill** that auto-activates only when PM-related work happens.

## How It Works

You just work. AutoTrack handles the rest.

```
You: "the quiz timer doesn't reset on retry, fix it"

What happens silently:
  1. Creates GitHub Issue #254 "Quiz timer doesn't reset on retry" [bug, P1]
  2. Fixes the bug
  3. Commits
  4. Closes #254 with summary

You: "the sidebar also breaks on mobile"

What happens:
  1. Creates GitHub Issue #255 "Sidebar breaks on mobile" [bug, P2]
  2. "Logged #255. Continuing current work."

You: "what's left to do?"

  Shows your open issues (one line each, ~200 tokens)
```

### Context compression? Handled.

```
Context compresses:
  Hook: PreCompact saves current state to GitHub Issue comment
  Hook: SessionStart reloads it after compression
  You notice nothing. Work continues seamlessly.
```

### New session? Handled.

```
You open Claude Code:
  Hook: SessionStart loads your active issue (~100 tokens injected)
  "Active: #254 - Quiz timer doesn't reset [bug, P1]"
  You're back in context immediately.
```

## Install

```bash
git clone https://github.com/spiffaz/autotrack-pm.git
cd autotrack-pm
bash install.sh
```

**Prerequisites:**
- [GitHub CLI](https://cli.github.com) (`gh`) installed and authenticated
- Claude Code
- Python 3 (for JSON handling in hooks)

## Uninstall

```bash
cd autotrack-pm
bash uninstall.sh
```

Your GitHub Issues and project state files are preserved.

## What Gets Installed

```
~/.claude/
  skills/pm/SKILL.md        # Auto-activating PM skill (~50 lines)
  scripts/pm-hook.sh        # Hook handler (~130 lines)
  settings.json              # Hooks merged into existing settings
```

Per-project (auto-created on first use):
```
.claude/pm-state.json        # 3 fields: repo, active_issue, sprint_label
```

## Architecture

AutoTrack has three components:

### 1. Skill (auto-activates, ~50 tokens in context)

The skill description sits in Claude's context budget. When you say anything related to work tracking, bugs, backlog, or tasks, Claude loads the full skill instructions and uses `gh` CLI for all operations.

The skill also activates on ANY work request (fix, build, refactor) to ensure tracking happens silently.

### 2. Hooks (zero tokens)

| Hook | When | What it does |
|---|---|---|
| `SessionStart` | New session, resume, or post-compact | Loads active issue context |
| `PreCompact` | Before context compression | Saves progress to GitHub Issue |
| `TaskCompleted` | Claude Code Task marked done | Syncs completion to GitHub |

Hooks are shell scripts. They run outside the LLM. Zero token cost.

### 3. State file (20 tokens)

`.claude/pm-state.json` holds three fields:
```json
{
  "repo": "owner/repo",
  "active_issue": 247,
  "sprint_label": "sprint-4"
}
```

## Usage

There are no commands to learn. Just talk naturally:

| What you say | What happens |
|---|---|
| "fix the login bug" | Creates issue, fixes it, closes it |
| "the X is also broken" | Logs separate issue, continues current work |
| "what should I work on?" | Shows prioritized open issues |
| "what's left?" | Shows open issues |
| "this is done" | Closes active issue, suggests next |
| "let's plan a sprint" | Helps pick issues, applies sprint label |
| "make #253 P1" | Reprioritizes |
| "show me what we did this week" | Lists recently closed issues |

## Labels

AutoTrack creates these labels on first use in a repo:

**Priority:** `P1` (critical), `P2` (important), `P3` (nice to have)

**Type:** `bug`, `feature`, `chore`, `epic`

## How This Replaces Jira

| Jira | AutoTrack |
|---|---|
| Create ticket | "fix X" or "add Y" (auto-created) |
| Board view | `gh issue list` or GitHub UI |
| Sprint planning | "plan sprint for auth work" |
| Priority | P1/P2/P3 labels (auto-inferred from tone) |
| Epic | Issue with `epic` label, children reference "part of #XX" |
| Status | open/closed + label transitions |
| Comments | Hooks auto-post progress |
| Dashboard | GitHub Issues UI (free) |
| Cross-project | Works in any repo (global skill) |
| Session handoff | Automatic via hooks |

## Comparison

| | AutoTrack | CCPM | Beads | Markdown files |
|---|---|---|---|---|
| Activation | Automatic | Manual `/pm:*` | Manual `bd` | Manual read/edit |
| Token cost | ~0-200 | ~1,000-3,000 | ~200-500 | ~3,000-9,000 |
| Session handoff | Auto (hooks) | Manual | Manual | Manual copy-paste |
| Install scope | Global | Per-project | Per-project | Per-project |
| Dependencies | `gh` CLI | None | Go binary + MCP | None |
| Learning curve | None | Commands | Commands | File conventions |

## Multi-Repo Support

AutoTrack works across all your repos, including non-GitHub repos and work projects.

### Hub Repo (Private)

On first use, AutoTrack asks you to set a **private** hub repo (e.g. `your-username/tracker`). This repo catches issues from:
- GitLab repos
- Work repos where you don't want AI-created issues appearing
- Directories without a git remote
- Any repo set to `"hub"` tracking mode

Hub issues are prefixed with the project name: `[my-api] Quiz timer bug`

### Tracking Modes

Each project has a `tracking` field in `.claude/pm-state.json`:

| Mode | Where issues go | Use for |
|---|---|---|
| `"hub"` (default) | Your private hub repo | Work repos, GitLab, unknown repos |
| `"local"` | Directly in the current repo | Personal GitHub repos you own |
| `"off"` | Nowhere | Repos where you don't want any tracking |

Change modes by telling Claude: "track issues locally" or "send issues to hub" or "turn off tracking"

### Global Config

`~/.claude/pm-config.json`:
```json
{
  "hub_repo": "your-username/tracker",
  "default_tracking": "hub"
}
```

### Per-Project State

`.claude/pm-state.json` (auto-created, add to `.gitignore`):
```json
{
  "repo": "owner/repo",
  "active_issue": 247,
  "sprint_label": "sprint-4",
  "tracking": "hub"
}
```

### Customizing labels

Edit the label creation section in `skills/pm/SKILL.md` to match your team's conventions.

### Disabling temporarily

```bash
# Disable all hooks temporarily
claude /hooks  # Toggle "disable all hooks"
```

## Contributing

Issues and PRs welcome. This project tracks its own work using AutoTrack (naturally).

## License

MIT
