# babysit-prs-testbed

Throwaway repo to test the `/babysit-prs` Claude Code loop end-to-end.

`main` is a green baseline. Open PRs each introduce one deliberate, fixable problem
(lint error, failing test, type error, etc.) and are arranged to exercise the loop's
ordered one-PR-per-cycle selection (stacked PRs, overlapping PRs, review-only PRs).

## Checks

CI (`.github/workflows/ci.yml`) and local scripts both run the four checks:

- `npm run lint` — ESLint (flat config, typescript-eslint)
- `npm run typecheck` — `tsc --noEmit`
- `npm run build` — `tsc`
- `npm test` — Vitest

## Not for real use

This repo exists only to give `/babysit-prs` real open PRs with real CI to act on.
Delete it when the loop is validated.
