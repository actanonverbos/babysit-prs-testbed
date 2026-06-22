# Verify `/babysit-prs` — paste-in prompt

Open a **fresh Claude Code session inside the `babysit-prs-testbed` repo** and paste the block
below (everything between the rulers). It carries all the context needed — no prior session required.

---

You are verifying the global `/babysit-prs` skill end to end against this testbed. Work autonomously and thoroughly. You have everything you need here.

**Ground rules**
- This mutates a live but throwaway GitHub testbed (`actanonverbos/babysit-prs-testbed`). **Always reset to broken baseline at the end (SHAs below), even if a step fails or you abort.**
- **Never** run `gh pr merge`. **Never** edit the skill under test (`~/.claude/commands/babysit-prs.md`) — you are checking it, not changing it.
- **First, read `~/.claude/commands/babysit-prs.md`** — that is the skill you're testing. It services ONE open PR per run: fixes the four checks (lint/typecheck/build/test), runs a Codex review and auto-fixes blocking findings, posts a `<!-- codex-review -->` marker, then if CI-green + Codex-clean@HEAD + (approved or no review required) adds `babysit:ready` and notifies once. Stateless.

**Context you must not have to rediscover**
- **Codex hangs unless its MCP servers are disabled.** Always run `codex review` with `-c 'mcp_servers={}'`. Failing/slow MCP servers otherwise stall it forever and wedge the loop. macOS has **no `timeout`** — bound codex with a background+watchdog (`codex … & CPID=$!; (sleep 600; kill -9 $CPID)& …; wait $CPID`).
- **Codex emits `P0`/`P1`/`P2`/`P3`, not "Critical/High", and calibrates conservatively** — real correctness *and* security bugs (even a ReDoS) come back as **`P2`**. The skill auto-fixes `P0`/`P1`/`P2` and surfaces `P3`.
- **`/code-review` fallback:** if `codex` is unusable (`command -v codex` fails, non-zero exit incl. 137=watchdog-kill, or empty output), the skill runs the **`/code-review`** skill (`/code-review high`, **never `ultra`** — that's billed cloud) instead; correctness bugs → auto-fix, cleanups → surface; marker headed `**/code-review fallback** (codex unavailable)`.
- **Worktree-collision (multi-agent):** git prints `fatal: '<branch>' is already used by worktree at ...` (older git: `already checked out at`). Any non-zero `gh pr checkout` → skip that PR, continue, never force.
- **Solo gate:** `main` is unprotected → required approvals = 0 → a PR reaches `babysit:ready` with no human approval (a solo repo can't self-approve).
- **CodeRabbit auto-reviews every PR** — leave its comments alone; only the `<!-- codex-review -->` marker counts.

**Testbed map (10 open PRs)** — *deterministic* faults (caught by the four checks, not Codex): #1 lint, #2 failing test, #3 type error, #4 lint (stack base of #5), #5 failing test (stacked on #4), #7 lint (overlaps #6 on `src/util.ts`); #6 is green/review-only. *Reviewer-only* faults (compile/lint/test clean — only a review catches them): **#8** `sortAsc` lexicographic sort, **#9** `isValidId` ReDoS regex, **#10** `lastN` off-by-one. Ordering: stacked base before child; overlapping files oldest-first; else oldest `updatedAt` (don't assert a fixed "top PR" — `updatedAt` drifts on every force-push; assert the *rules*). Run `/babysit-prs` from this repo dir; use the sibling `../babysit-prs-loop` worktree (create with `git worktree add --detach ../babysit-prs-loop origin/main` if absent) as the isolated second actor.

**Checks to run (record PASS/FAIL + evidence for each):**
1. **Selection/ordering** — `/babysit-prs --dry-run`. All needs-work PRs listed, one selected, ordering rules honored, nothing mutated.
2. **Deterministic fix** — `/babysit-prs 1`: removes the unused var, lint passes, commits+pushes, posts a Codex marker.
3. **Primary Codex (reviewer-only)** — `/babysit-prs 8`: four checks pass, Codex (MCP-disabled) flags the sort bug (P2), auto-fixes it, re-reviews clean, marker posted, `babysit:ready` added.
4. **`/code-review` fallback** — hide codex (`mv "$(command -v codex)" "$(command -v codex).bak"`), then `/babysit-prs 9`: skill detects codex gone, runs `/code-review` (not `ultra`, not a hand-review), catches the ReDoS, fixes it, posts a `/code-review fallback` marker. **Restore codex right after** (`mv .../codex.bak .../codex`).
5. **Skip labels/draft** — add `babysit:hold` to #3, `wip` to #5, draft #6; `/babysit-prs --dry-run` → assert #3/#5/#6 are not candidates; then undo.
6. **Worktree-collision** — check out a needs-work branch in `../babysit-prs-loop`, then attempt to service it here → assert `gh pr checkout` fails (`already used by worktree at`), you don't force, and the run skips to the next candidate. Release the worktree after.
7. **Push-rejection** — checkout a lint PR (#7), fix+commit locally, race an interfering push to that branch from `../babysit-prs-loop`, then `git push` → assert non-fast-forward rejection, no `--force`, the other commit preserved.
8. **Live multi-agent drain** — draft #2 + `babysit:hold` #3; spawn a background dev-agent (its own worktree, `isolation:'worktree'`) that commits to `pr-failing-test` and keeps #2 Draft; arm `/loop 5m /babysit-prs` and run a couple fires → assert the loop drains Ready PRs (`babysit:ready`) while #2 (draft) and #3 (hold) are never touched (0 codex markers, branches unchanged). Then `CronDelete` the loop and shut the dev-agent down.

**Reset (ALWAYS do this last — restore broken baseline):**
If `test/babysit-harness.sh` exists, just run `bash test/babysit-harness.sh restore-codex && bash test/babysit-harness.sh reset && bash test/babysit-harness.sh assert-baseline`. Otherwise do it by hand: restore codex if hidden; for each branch `git fetch origin && git push origin +<sha>:refs/heads/<branch>`; `gh pr ready <n>` (undraft all); strip `babysit:ready`/`babysit:hold`/`wip` labels; delete every comment containing `<!-- codex-review -->` (leave CodeRabbit's). Confirm `CronList` is empty.

```
pr-lint-error      f67609bd3ee70d12d798a5d77d882a118513a958
pr-failing-test    e3e38f63c2abfd59a0e9d4b7b8d0d10d8b7d8147
pr-type-error      85a800d98a3bddf4721a3b3aeb71b466cb35dc6c
pr-stack-a         169a38a916079b3778f04d93158c33ce19087be0
pr-stack-b         2db956f65bc20df25ace2923264039a5f8ff4d7d
pr-overlap-1       ee44e3acce01c16c86d774dae0d213a97750b509
pr-overlap-2       7007d136afbbae6ce9a24fc08e4d954f0908ea08
pr-logic-sort      5de63d93f1d667fc8bc8d7e3ce25bba5b94897eb
pr-security-redos  a6bac49b458ccd1393bbea5d879b43b154a59db1
pr-edge-lastn      1fc134809a09e8e3d5725d98564e89321e516ecd
```

**Finally, report a PASS/FAIL table** — one row per check, with the evidence (commit SHAs, marker headers, labels, assertion results) — and state plainly whether `/babysit-prs` is verified working. If you want a smaller run, do only a subset but always reset at the end.

---
