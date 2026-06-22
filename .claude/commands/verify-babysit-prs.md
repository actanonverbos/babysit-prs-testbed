---
description: Session-agnostic verification of the /babysit-prs skill against this testbed — drives the full suite (selection, fix paths, Codex + /code-review fallback, multi-agent hardenings, live drain), asserts outcomes, and always resets to broken baseline.
allowed-tools: Bash(gh:*), Bash(git:*), Bash(codex:*), Bash(npm:*), Bash(npx:*), Bash(node:*), Bash(test/babysit-harness.sh:*), Bash(bash:*), Bash(cat:*), Bash(mv:*), Read, Edit, Write, Skill, Agent, SendMessage, TaskStop, CronCreate, CronList, CronDelete
---

Verify that the global `/babysit-prs` skill actually works, end to end, against this testbed. **This command carries all the context you need — you do not need any prior session's memory.** Read it fully, then execute the protocol.

Parse `$ARGUMENTS`: empty → run the **full suite (A–G)**. Otherwise a space-separated list of scenario letters or keywords (`dry`, `fix`, `codex`, `fallback`, `hardenings`, `drain`) → run only those, but **always** run step 0 (preconditions) first and step G (reset) last.

## ⚠️ Hard rules
- **This mutates a live GitHub repo** (`actanonverbos/babysit-prs-testbed`). It is a throwaway testbed built for exactly this — but **always finish with step G (reset)**, even on failure/abort. Wrap the run so reset and `restore-codex` happen no matter what.
- **Never `gh pr merge`.** The skill never merges; neither does this verifier.
- **Never edit the skill under test** (`~/.claude/commands/babysit-prs.md`) from here — this verifies it, it doesn't change it.
- If anything is ambiguous or a step fails hard, record it and continue to the next independent step; do not get stuck. Report failures plainly at the end.

## What you're testing — read the skill first
`~/.claude/commands/babysit-prs.md` is the source of truth. **Read it now.** Summary: services ONE open PR per invocation (highest-priority needs-work), fixes the four checks (lint/typecheck/build/test), runs a Codex review and auto-fixes blocking findings, posts a `<!-- codex-review -->` marker, addresses CI + review comments, and—if CI-green + Codex-clean@HEAD + approved-or-no-review-required—adds `babysit:ready` and notifies once. Stateless; re-derives from `gh` each run.

## Hard-won context (gotchas a fresh session would otherwise rediscover painfully)
- **Codex hangs unless its MCP servers are disabled.** Always invoke `codex review` with `-c 'mcp_servers={}'`. Without it, failing/slow MCP servers (auth failures, a `node_repl` server with a long `startup_timeout_sec`) stall it indefinitely and wedge the loop. macOS has **no `timeout`** — bound codex with a portable background+watchdog (`codex … & CPID=$!; (sleep 600; kill -9 $CPID)& …; wait $CPID`).
- **Codex emits `P0`/`P1`/`P2`/`P3`, not "Critical/High", and calibrates conservatively** — it labels real correctness *and* security bugs (even a ReDoS) as **`P2`**. The skill auto-fixes `P0`/`P1`/`P2` and surfaces `P3`. If you see "no P0/P1 so nothing to fix," that's the old, wrong behavior.
- **`/code-review` fallback.** If `codex` is unusable (`command -v codex` fails, non-zero exit incl. 137=watchdog-kill, or empty output), the skill runs the **`/code-review` skill** (e.g. `/code-review high`, **never `ultra`** — that's billed cloud) to review instead; its correctness bugs → auto-fix, its cleanups → surface. The marker is headed `**/code-review fallback** (codex unavailable)`.
- **Worktree-collision message** (multi-agent §3): current git prints `fatal: '<branch>' is already used by worktree at ...` (older git: `already checked out at`). Any non-zero `gh pr checkout` = skip that PR and continue; never force.
- **Solo-approval gate (§8):** `main` here is **unprotected** → `required_approving_review_count` is absent → treat as 0 → a PR can reach `babysit:ready` with **no human approval** (a solo repo can't self-approve; gating on approval would wedge forever).
- **CodeRabbit auto-reviews every PR** on this account — its comments are real review signal but are NOT the Codex marker. Leave CodeRabbit comments alone; only the `<!-- codex-review -->` marker matters for the merge gate.

## The testbed — 10 open PRs, two fault classes
Deterministic faults (caught by the four checks, NOT Codex): #1 lint, #2 failing test, #3 type error, #4 lint (stack base of #5), #5 failing test (stacked on #4), #7 lint (overlaps #6 on `src/util.ts`). Green/review-only: #6 (no fault). **Reviewer-only** faults (compile/lint/test clean — only Codex catches): #8 `sortAsc` lexicographic sort (→P2), #9 `isValidId` ReDoS regex (→P2), #10 `lastN` off-by-one (→P2). Ordering rule: stacked base before child; overlapping files oldest-first; else oldest `updatedAt` (note: `updatedAt` drifts on every force-push, so don't assert a hard-coded "top PR" — assert the rules).

## Worktrees
Run the "loop" (the `/babysit-prs` invocations) from this repo dir (the loop terminal — `gh pr checkout` switches its branch). Use the sibling **`../babysit-prs-loop`** worktree (detached) as the isolated second actor for the collision and dev-agent steps. If it's missing, create it: `git worktree add --detach ../babysit-prs-loop origin/main`.

## Harness
`test/babysit-harness.sh` does the mechanical, must-be-reproducible bits. Subcommands: `baseline`, `assert-baseline`, `status`, `reset`, `hide-codex`, `restore-codex`, `markers <n>`, `assert-unchanged <branch> <sha>`. It refuses to run outside the testbed.

---

## Protocol

### 0. Preconditions (always)
`bash test/babysit-harness.sh assert-baseline` — must pass before starting. If it fails, run `reset` first, then re-assert. Capture `status` as the "before" snapshot.

### A. Selection / ordering (`dry`) — zero mutation
Run `/babysit-prs --dry-run`. **Assert:** every needs-work PR is listed; exactly one is selected; the ordering honors stack-base-before-child and overlap-oldest-first; **nothing was mutated** (`status` unchanged). Note which PR it picked and why.

### B. Deterministic fix path (`fix`)
Run `/babysit-prs 1`. **Assert:** it checks out `pr-lint-error`, lint fails on the unused var, it removes the var, lint passes, commits + pushes a fix; then Codex runs and a marker is posted; `gh pr checks 1` trends green. Confirm a fix commit exists on the branch.

### C. Primary Codex path (`codex`) — reviewer-only bug
Ensure `codex` is available (`command -v codex`). Run `/babysit-prs 8`. **Assert:** four checks pass (no deterministic fault); Codex runs **with MCP disabled** and flags the `sortAsc` lexicographic-sort bug (expect **P2**); it auto-fixes (numeric comparator, non-mutating), re-reviews clean, posts a `**Codex review**` marker at HEAD; #8 gets `babysit:ready` (solo gate). `markers 8` == 1.

### D. `/code-review` fallback (`fallback`) — the key recent change
`bash test/babysit-harness.sh hide-codex` (makes `command -v codex` fail). Then run `/babysit-prs 9`. **Assert:** the skill detects Codex is unavailable and runs **`/code-review`** (NOT a hand-review, NOT `ultra`); it catches the ReDoS in `isValidId`, fixes it, and posts a marker headed **`/code-review fallback (codex unavailable)`**. Always `bash test/babysit-harness.sh restore-codex` immediately after (even if the step failed).

### E. Multi-agent hardenings (`hardenings`) — deterministic races
1. **Skip labels/draft:** `gh pr edit 3 --add-label babysit:hold`; create+add `wip` to #5 (`gh label create wip 2>/dev/null; gh pr edit 5 --add-label wip`); `gh pr ready 6 --undo` (draft). Run `/babysit-prs --dry-run`. **Assert:** #3, #5, #6 absent from candidates. Then undo (`remove-label`, `gh pr ready 6`).
2. **Worktree-collision skip:** in `../babysit-prs-loop`, `git checkout <some-needs-work-branch>` (e.g. `pr-stack-a`). Back here, `gh pr checkout 4` → **assert** it fails with `already used by worktree at` and you stay put (no force); the skill would skip #4 and continue. Release: `git -C ../babysit-prs-loop checkout --detach origin/main`.
3. **Push-rejection safety:** `gh pr checkout 7`, fix its lint, commit locally (don't push). From `../babysit-prs-loop`: `git checkout --detach origin/pr-overlap-2 && git commit --allow-empty -m "interfering" && git push origin HEAD:pr-overlap-2`. Back here, `git push` → **assert** it's rejected (non-fast-forward), you do NOT `--force`, and `origin/pr-overlap-2` still holds the interfering commit. (Step G's reset restores #7.)

### F. Live multi-agent drain (`drain`) — the integration test
1. Set up: `gh pr ready 2 --undo` (Draft #2 — the dev-agent's PR); `gh pr edit 3 --add-label babysit:hold`. Note `origin/pr-type-error` SHA.
2. Spawn a **background dev-agent** (Agent tool, `isolation: 'worktree'`, `run_in_background: true`) told to: work ONLY branch `pr-failing-test` in its own worktree, fix the failing test, make ~2 commits, push, **keep #2 a Draft**, touch no labels and no other PR, never merge.
3. Arm the loop: `/loop 5m /babysit-prs` (CronCreate `*/5 * * * *`). Then execute 1–2 fires now (run `/babysit-prs`) — each services the next Ready PR.
4. **Assert:** the loop drains Ready PRs (they gain `babysit:ready`); **#2 (Draft)** is never serviced (no codex marker; only the dev-agent's commits — `markers 2` == 0); **#3 (`babysit:hold`)** is untouched (`assert-unchanged pr-type-error <noted-sha>`). No collision errors corrupt either side.
5. Tear down: `CronDelete` the loop (confirm with `CronList`), send the dev-agent a `shutdown_request` (SendMessage), `gh pr ready 2`, remove the hold label.

### G. Reset + report (always)
`bash test/babysit-harness.sh restore-codex` then `bash test/babysit-harness.sh reset`, then `assert-baseline` (must pass) and `CronList` (must be empty). Then print a **PASS/FAIL table**, one row per scenario run, with the observed evidence (commit SHAs, marker headers, labels, assertion results) and anything left for a human. State clearly whether the skill is verified working.
