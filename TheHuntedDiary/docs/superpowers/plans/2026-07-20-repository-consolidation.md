# Repository Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate the workspace-level and nested Git repositories into the workspace-level repository while retaining all current files, both inner branches, and their reachable commit history.

**Architecture:** Keep `/Users/dima/Documents/Tom's Diary/.git` as the only active repository metadata. Fetch the nested repository's branches into it, join the inner current branch to the outer current branch with a history-only merge, then move the nested `.git` directory to a temporary recovery directory after verification.

**Tech Stack:** Git, Xcode project files, zsh

## Global Constraints

- Preserve the current contents and modification state of `TheHuntedDiary/TheHuntedDiary.xcodeproj/project.xcworkspace/xcuserdata/dima.xcuserdatad/UserInterfaceState.xcuserstate`.
- Preserve the outer branch `codex/task-1-app-shell` and the inner branches `codex/task-2-plain-text-history` and `master`.
- Do not flatten or rename the existing `TheHuntedDiary/` project directory.
- Finish with exactly one `.git` directory inside `/Users/dima/Documents/Tom's Diary`.
- Keep the removed nested Git metadata recoverable in a unique directory under `/tmp` for the remainder of the session.

---

### Task 1: Record and import nested repository history

**Files:**
- Create: `TheHuntedDiary/docs/superpowers/plans/2026-07-20-repository-consolidation.md`
- Modify: `/Users/dima/Documents/Tom's Diary/.git/refs/heads/codex/task-2-plain-text-history`
- Modify: `/Users/dima/Documents/Tom's Diary/.git/refs/heads/master`

**Interfaces:**
- Consumes: nested Git refs under `TheHuntedDiary/.git/refs`
- Produces: outer-repository branches `codex/task-2-plain-text-history` and `master`

- [ ] **Step 1: Commit this consolidation plan without staging the modified Xcode state**

Run:

```bash
git add TheHuntedDiary/docs/superpowers/plans/2026-07-20-repository-consolidation.md
git commit -m "docs: plan repository consolidation"
```

Expected: one documentation commit; `git status --short` still reports only the pre-existing modified Xcode user-state file.

- [ ] **Step 2: Fetch both nested branches by their existing names**

Run:

```bash
git fetch ./TheHuntedDiary/.git refs/heads/codex/task-2-plain-text-history:refs/heads/codex/task-2-plain-text-history refs/heads/master:refs/heads/master
```

Expected: both branches appear in `git branch -vv` and retain their original commit IDs (`a4740e6` and `f7316f3`).

- [ ] **Step 3: Verify imported objects and branch reachability**

Run:

```bash
git fsck --full
git rev-parse codex/task-2-plain-text-history master
```

Expected: no repository corruption; output includes `a4740e6...` and `f7316f3...`.

### Task 2: Join histories and remove the nested repository boundary

**Files:**
- Modify: `/Users/dima/Documents/Tom's Diary/.git/objects`
- Move: `TheHuntedDiary/.git` to a unique `/tmp/toms-diary-inner-git.XXXXXX/` recovery directory

**Interfaces:**
- Consumes: imported branch `codex/task-2-plain-text-history`
- Produces: a two-parent consolidation commit on `codex/task-1-app-shell` and a single active workspace repository

- [ ] **Step 1: Connect the inner history without changing the outer working tree**

Run:

```bash
git merge --allow-unrelated-histories --strategy=ours codex/task-2-plain-text-history -m "chore: consolidate nested repository history"
```

Expected: a merge commit with the prior outer commit and `a4740e6` as parents; the modified Xcode user-state file remains modified and uncommitted.

- [ ] **Step 2: Create a recoverable temporary destination**

Run:

```bash
mktemp -d /tmp/toms-diary-inner-git.XXXXXX
```

Expected: a unique empty directory path under `/tmp`.

- [ ] **Step 3: Move the nested metadata to that exact temporary destination**

Run, replacing the destination with the path printed by Step 2:

```bash
mv TheHuntedDiary/.git /tmp/toms-diary-inner-git.XXXXXX/.git
```

Expected: `TheHuntedDiary/.git` no longer exists, while the temporary recovery copy does.

### Task 3: Verify the consolidated repository

**Files:**
- Verify: `/Users/dima/Documents/Tom's Diary/.git`
- Verify: `TheHuntedDiary/TheHuntedDiary.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: consolidated repository and working tree
- Produces: evidence that files, history, branches, and the pre-existing local modification survived

- [ ] **Step 1: Verify there is exactly one repository boundary**

Run:

```bash
find . -type d -name .git -prune -print
```

Expected: only `./.git`.

- [ ] **Step 2: Verify branch topology and repository integrity**

Run:

```bash
git log --graph --oneline --decorate --all -20
git fsck --full
```

Expected: all three branches are visible, the current branch has a two-parent merge commit, and `git fsck` reports no corruption.

- [ ] **Step 3: Verify the working tree modification was preserved**

Run:

```bash
git status --short --branch
```

Expected: current branch `codex/task-1-app-shell`; only the original Xcode `UserInterfaceState.xcuserstate` modification remains uncommitted.
