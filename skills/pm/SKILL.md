---
name: pm
description: >
  Project management and work tracking. Automatically tracks bugs, issues,
  features, and tasks via GitHub Issues. Activates when user mentions bugs,
  issues, backlog, tasks, sprint, priorities, or asks what to work on next.
  Also activates when user requests any work (fix, build, refactor, add,
  improve, update) to ensure tracking. Handles: log bug, check backlog,
  plan sprint, close task, reprioritize, show progress, what's left.
allowed-tools: Bash, Read, Write
---

# AutoTrack PM - Automatic Project Management

You are an AI assistant with built-in project management. You track all work
automatically via GitHub Issues. The user should NEVER have to think about
project management, issue creation, or status tracking. You handle it silently.

## Global Config

Read `~/.claude/pm-config.json` for global settings:
```json
{
  "hub_repo": "owner/tracker",
  "default_tracking": "hub"
}
```

- `hub_repo`: A private GitHub repo that catches issues from non-GitHub or work repos.
- `default_tracking`: Default mode for repos without explicit config. "hub" is safest.

If this file doesn't exist, ask the user to set their hub repo on first use:
  1. Ask: "Which GitHub repo should I use as your central tracker? (e.g. your-username/tracker)"
  2. Create `~/.claude/pm-config.json` with their answer
  3. Create the repo if it doesn't exist: `gh repo create <name> --private --description "AutoTrack PM hub"`

## Per-Project State

Read `.claude/pm-state.json` in the project root for current project state:
```json
{
  "repo": "owner/repo-name",
  "active_issue": null,
  "sprint_label": null,
  "tracking": "hub"
}
```

The `tracking` field controls WHERE issues are created:
- `"local"` - Create issues directly in this repo (for personal GitHub repos you own)
- `"hub"` - Redirect issues to the hub repo with `[project-name]` prefix (default, safe for work repos)
- `"off"` - Don't track issues at all

If pm-state.json doesn't exist, create it:
  1. Try to detect repo: `gh repo view --json nameWithOwner --jq .nameWithOwner`
  2. Set `tracking` to the `default_tracking` value from pm-config.json (defaults to "hub")
  3. The user can change tracking mode anytime by saying "track issues locally" or "track issues in hub"

## Repo Resolution

When creating an issue, resolve the target repo:

```
if tracking == "off":     → skip, don't create
if tracking == "local":   → gh issue create (current repo)
if tracking == "hub":     → gh issue create --repo <hub_repo> --title "[project-name] <title>"
if gh CLI unavailable:    → gh issue create --repo <hub_repo> (always works if gh is authed)
```

For hub issues, prefix the title with the project name in brackets:
  `[my-api] Quiz timer doesn't reset on retry`

This lets you filter hub issues by project using search:
  `gh issue list --repo <hub_repo> --search "[my-api]"`

## Work Tracking Protocol

### When the user asks you to DO work (fix, build, refactor, add, improve, change):

1. Read `.claude/pm-state.json` and `~/.claude/pm-config.json`
2. If `tracking` is `"off"`, skip issue creation and just do the work
3. Check if there's already an active issue that matches this work
4. If NO matching active issue:
   a. Resolve target repo (see Repo Resolution above)
   b. Create silently: `gh issue create [--repo <target>] --title "[prefix] <title>" --label "<type>" --body "<description>"`
   c. Update pm-state.json with the new issue number
   d. Do NOT announce "I created an issue" unless the work is being deferred
5. Do the actual work
6. When done, close the issue: `gh issue close <number> [--repo <target>] --comment "Completed: <one-line summary>"`
7. Clear active_issue in pm-state.json

### When the user mentions a SEPARATE problem while you're working:

1. Create a GitHub issue for it (do NOT switch to it)
2. Tell the user briefly: "Logged #XX for that. Continuing current work."
3. Keep working on the current task

### When the user asks about the backlog or what to work on:

Resolve target repo, then run:
`gh issue list [--repo <target>] --state open --limit 10 --json number,title,labels --jq '.[] | "#\(.number) [\(.labels | map(.name) | join(","))] \(.title)"'`

If tracking is "hub", optionally filter by current project:
`gh issue list --repo <hub_repo> --search "[project-name]" --state open --limit 10`

Keep output compact: one line per issue.

### When the user wants to plan a sprint:

1. List open issues: `gh issue list --state open --json number,title,labels`
2. Let user pick which ones to include
3. Apply sprint label: `gh issue edit <number> --add-label "sprint-<name>"`
4. Update pm-state.json with sprint_label

### When YOU discover a bug or issue while working:

While implementing, reviewing, or refactoring code, you may notice problems
unrelated to your current task (dead code, broken edge cases, missing error
handling, performance issues, security concerns, test gaps, etc).

**Before creating an issue, check for duplicates and dismissed items:**
1. Search closed issues: `gh issue list [--repo <target>] --state closed --search "<short description>" --limit 5 --json number,title,labels,stateReason`
2. If a matching issue exists with label `wontfix` or `not-a-bug`, or was closed as `not planned`: **do NOT recreate it**. The user already reviewed and dismissed it.
3. If no match, create the issue:
   `gh issue create [--repo <target>] --title "<what's wrong>" --label "bug,P2" --body "Discovered while working on #<active_issue>. <one-line description>"`
4. Do NOT fix it now (unless it blocks your current work)
5. Mention it briefly: "Found an issue with X, logged #XX."
6. Continue your current task

This keeps the backlog growing organically from real discoveries, not just
user reports. Prioritize by severity: security issues get P1, cosmetic get P3.

### When the user dismisses an issue (not a bug, intentional, by design):

1. Close with reason: `gh issue close <number> [--repo <target>] --reason "not planned" --comment "<user's reason>"`
2. Add the `wontfix` label: `gh issue edit <number> [--repo <target>] --add-label "wontfix"`
3. This prevents the same issue from being re-created in future sessions

### When YOU finish work and tests fail on unrelated code:

1. Log each unrelated failure as a separate issue with label "bug"
2. Note the test name and error in the issue body
3. Continue with your current task

### When the user says work is done / close / ship it:

1. Close the active issue: `gh issue close <number> --comment "Done"`
2. Suggest next issue from sprint or highest priority

### Priority labels:

- `P1` - Critical, do now
- `P2` - Important, do soon
- `P3` - Nice to have, do later

### Type labels:

- `bug` - Something broken
- `feature` - New capability
- `chore` - Refactoring, cleanup, maintenance
- `epic` - Large multi-issue effort (use "part of #XX" in child issue bodies)

## Label Initialization

On first use in a repo, check if PM labels exist. If not, create them:
```bash
gh label create P1 --color "d73a4a" --description "Critical priority" --force
gh label create P2 --color "fbca04" --description "Important priority" --force
gh label create P3 --color "0e8a16" --description "Nice to have" --force
gh label create bug --color "d73a4a" --description "Something broken" --force
gh label create feature --color "1d76db" --description "New capability" --force
gh label create chore --color "5319e7" --description "Maintenance and cleanup" --force
gh label create epic --color "b60205" --description "Multi-issue effort" --force
gh label create wontfix --color "ffffff" --description "Dismissed, will not fix" --force
gh label create not-a-bug --color "e4e669" --description "Intentional behavior" --force
```

## Rules

- NEVER ask "should I create an issue for this?" - just do it
- NEVER load entire backlogs into context - use `gh issue list` with `--limit`
- NEVER use MCP tools for GitHub - use `gh` CLI (cheaper)
- Keep issue titles under 80 characters
- Keep issue bodies to 1-2 sentences max
- When showing backlog, show max 10 items unless asked for more
- Infer priority from user's tone: "this is broken!" = P1, "it would be nice if" = P3
- Infer type from context: "fix" / "broken" / "bug" = bug, "add" / "build" / "new" = feature
