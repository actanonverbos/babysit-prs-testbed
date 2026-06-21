# /babysit-prs — self-contained test plan

This repo exists only to test the `/babysit-prs` Claude Code command end to end.
Everything you need is in this file — no other context required.

## What `/babysit-prs` is

A global Claude Code command at `~/.claude/commands/babysit-prs.md`. **Read that file first** —
it is the source of truth for behaviour. Summary:

- Services **one open PR per invocation** — the highest-priority one that still needs work — then exits.
- Run under `/loop` (e.g. `/loop 10m /babysit-prs`) to babysit the whole open-PR queue.
- Per PR: run the four checks (lint/build/test/typecheck) and fix failures → run Codex review and
  **auto-fix Critical/High** findings, post the `<!-- codex-review -->` marker → fix CI → address review
  comments → if green + Codex-clean@HEAD + approved, **notify once** (never merges, never creates PRs).
- Stateless: every cycle re-derives from `gh`. State lives in GitHub (CI status, the Codex marker,
  approval, a `babysit:ready` label).
- Ordering (which PR is picked): **stacked base before child**; **overlapping files oldest-first**; else
  oldest `updatedAt`.
- Args: optional PR number (limit to one PR); `--dry-run` (report only, no mutations).

## This repo

- Tiny TypeScript project. Four checks, all wired to npm scripts and to GitHub Actions CI:
  - `npm run lint` (ESLint flat config), `npm run typecheck` (`tsc --noEmit`), `npm run build` (`tsc`), `npm test` (Vitest).
- `main` is a **green** baseline. Each open PR introduces one deliberate, fixable problem, arranged to
  exercise the loop's ordered one-PR-per-cycle selection.
- Repo: https://github.com/actanonverbos/babysit-prs-testbed (public, so Actions runs free).

## The PRs

| PR | Branch | Base | Deliberate fault | Tests |
|----|--------|------|------------------|-------|
| #1 | `pr-lint-error` | main | unused variable | lint fix path |
| #2 | `pr-failing-test` | main | wrong `subtract` impl | test fix path |
| #3 | `pr-type-error` | main | `repeat` returns number as string | typecheck/build fix path |
| #4 | `pr-stack-a` | main | unused variable | lint fix; **base of #5** |
| #5 | `pr-stack-b` | `pr-stack-a` | failing test + inherits #4's lint | stacked ordering (**#4 before #5**) |
| #6 | `pr-overlap-1` | main | none (all green) | review-only path; **overlaps #7** |
| #7 | `pr-overlap-2` | main | unused variable | lint fix; **overlaps #6** (both edit `src/util.ts`) |

Expected first selection on a full queue: **#4** (oldest `updatedAt`, and the stack base — correctly before #5).
The overlap pair sorts **#6 before #7**.

## Original broken-state SHAs (for resets)

Reset any branch to its untouched broken state with these. Capture them before testing in case branches drift.

```
main            9bd4fba1029775ea56e2e5b0e2bf50736c1c5651
pr-lint-error   f67609bd3ee70d12d798a5d77d882a118513a958
pr-failing-test e3e38f63c2abfd59a0e9d4b7b8d0d10d8b7d8147
pr-type-error   85a800d98a3bddf4721a3b3aeb71b466cb35dc6c
pr-stack-a      169a38a916079b3778f04d93158c33ce19087be0
pr-stack-b      2db956f65bc20df25ace2923264039a5f8ff4d7d
pr-overlap-1    ee44e3acce01c16c86d774dae0d213a97750b509
pr-overlap-2    7007d136afbbae6ce9a24fc08e4d954f0908ea08
```

## Test scenarios

Run all of these from inside this repo (`cd` here first). Read `~/.claude/commands/babysit-prs.md` before starting.

### A. Selection + ordering (dry-run, no mutation)

1. `/babysit-prs --dry-run` → expect: all 7 PRs listed as needing work; **selected = #4**; reason = oldest + stack base; overlap pair ordered #6 before #7.
2. `/babysit-prs 5 --dry-run` → expect: report notes #5 is stacked on **#4**, so #4 is serviced first.
3. Confirm nothing was mutated: `gh pr view 4 --json comments`.

### B. The four-checks fix paths (real — mutates branches)

4. `/babysit-prs 1` → checks out `pr-lint-error`, lint fails, removes the unused var, lint passes, pushes. Then runs Codex review and posts the marker. Verify: `gh pr checks 1` trends green; a fix commit exists on the branch.
5. `/babysit-prs 2` → fixes the wrong `subtract` impl, test passes, pushes.
6. `/babysit-prs 3` → fixes the `repeat` return type, typecheck + build pass, pushes.

### C. Codex review-only path (real)

7. `/babysit-prs 6` → four checks already pass (no fix commits); Codex runs; marker posted at #6's head SHA. Verify: exactly one `<!-- codex-review -->` comment, SHA == `git rev-parse origin/pr-overlap-1`.
8. Re-run `/babysit-prs 6` → **idempotency**: sees a current marker, does nothing, no second marker.

### D. Stacked ordering (real)

9. With #4 and #5 both broken, run `/babysit-prs` → expect it services **#4 first** (the base). After #4 is fixed, run again → it can pick up #5.

### E. Review comments

10. Post a fake comment: `gh pr comment 6 --body "Please rename greet to greeting."` Run `/babysit-prs 6` → expect the comment surfaced in the summary (renaming a public API is a judgment call). Post a *question* comment → expect a **drafted reply in the summary, not posted**.

### F. Notify-once + never-merge

11. Get a PR fully green + marker, then approve it. Run `/babysit-prs <n>` → prints "ready to merge" once and adds `babysit:ready`. Re-run → silent (already announced). Confirm no `gh pr merge` ever runs.

### G. Loop drain (real, end to end)

12. Reset all branches (below). Run `/babysit-prs` repeatedly → confirm the drain order honours the rules (#4 before #5; overlap oldest-first) and serviced PRs drop out of later cycles (no thrash).
13. `/loop 5m /babysit-prs` for two cycles on a small subset → confirm each idle fire services one PR. Stop with `/loop` off or `CronDelete`.

## Reset procedure

After a real run, restore branches to broken state and clear test artefacts:

```bash
git fetch origin
# repeat per touched branch:
git checkout <branch> && git reset --hard <original-sha-from-above> && git push --force-with-lease
git checkout main
# remove test artefacts:
gh pr edit <n> --remove-label babysit:ready 2>/dev/null
# delete any codex marker / fake review comments via: gh pr view <n> --json comments  then  gh api -X DELETE ...
```

## Caveats

- **CodeRabbit** auto-reviews every PR on this account — a free source of real review comments, but it can
  also duplicate the Codex pass. Disable it on this repo if it muddies a test.
- The `actanonverbos` account has GitHub Actions **disabled for private repos** (billing). This repo is
  **public** to get free Actions — don't flip it back to private or CI dies.

## Paste-in prompt to start a fresh session here

```
I'm in the babysit-prs-testbed repo. Read TEST-PLAN.md and ~/.claude/commands/babysit-prs.md,
then run the test scenarios in order. Start with A (dry-run selection/ordering), confirm the
expected results, then ask me before any real (mutating) run.
```
