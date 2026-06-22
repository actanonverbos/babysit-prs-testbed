#!/usr/bin/env bash
# babysit-harness.sh — reproducible, session-agnostic fixture/reset helper for verifying
# the /babysit-prs skill against this testbed. Driven by the /verify-babysit-prs command,
# but every subcommand is safe to run by hand.
#
# Mechanical, deterministic operations only (git/gh). The Claude-driven steps
# (running /babysit-prs, codex, /code-review) live in .claude/commands/verify-babysit-prs.md.
#
# Usage: test/babysit-harness.sh <subcommand> [args]
#   baseline            print the canonical broken-baseline SHA for every branch
#   assert-baseline     exit 0 iff every branch's remote head == its baseline SHA
#   status              print PR table (number, branch, draft, labels) + codex-marker counts
#   reset               restore broken baseline: branches→baseline SHAs, undraft all,
#                       strip babysit:ready/hold/wip labels, delete codex-review markers
#   hide-codex          move the codex binary aside (forces the /code-review fallback path)
#   restore-codex       move it back
#   markers <n>         count <!-- codex-review --> markers on PR n
#   assert-unchanged <branch> <sha>   exit nonzero if origin/<branch> != <sha>

set -euo pipefail

EXPECT_REPO="babysit-prs-testbed"

# branch<TAB>baseline-sha  (source of truth for resets; mirrors TEST-PLAN.md)
read -r -d '' BASELINES <<'EOF' || true
pr-lint-error	f67609bd3ee70d12d798a5d77d882a118513a958
pr-failing-test	e3e38f63c2abfd59a0e9d4b7b8d0d10d8b7d8147
pr-type-error	85a800d98a3bddf4721a3b3aeb71b466cb35dc6c
pr-stack-a	169a38a916079b3778f04d93158c33ce19087be0
pr-stack-b	2db956f65bc20df25ace2923264039a5f8ff4d7d
pr-overlap-1	ee44e3acce01c16c86d774dae0d213a97750b509
pr-overlap-2	7007d136afbbae6ce9a24fc08e4d954f0908ea08
pr-logic-sort	5de63d93f1d667fc8bc8d7e3ce25bba5b94897eb
pr-security-redos	a6bac49b458ccd1393bbea5d879b43b154a59db1
pr-edge-lastn	1fc134809a09e8e3d5725d98564e89321e516ecd
EOF

guard_repo() {
  local repo
  repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")
  case "$repo" in
    *"$EXPECT_REPO"*) : ;;
    *) echo "REFUSING: not in $EXPECT_REPO (got '$repo'). This harness force-pushes — wrong repo would be destructive." >&2; exit 2 ;;
  esac
}

cmd_baseline() { printf '%s\n' "$BASELINES"; }

cmd_assert_baseline() {
  guard_repo; git fetch origin --quiet
  local ok=1 br sha cur
  while IFS=$'\t' read -r br sha; do
    [ -z "$br" ] && continue
    cur=$(git rev-parse "origin/$br" 2>/dev/null || echo "MISSING")
    if [ "$cur" = "$sha" ]; then echo "  ✓ $br @ ${cur:0:7}"; else echo "  ✗ $br @ ${cur:0:7} (expected ${sha:0:7})"; ok=0; fi
  done <<< "$BASELINES"
  [ "$ok" = 1 ] || { echo "NOT at clean baseline"; exit 1; }
  echo "all branches at broken baseline"
}

cmd_status() {
  guard_repo
  gh pr list --state open --json number,headRefName,isDraft,labels \
    --jq 'sort_by(.number)[] | "#\(.number) \(.headRefName) draft=\(.isDraft) labels=[\([.labels[].name]|join(","))]"'
  echo "-- codex markers --"
  local n c
  for n in $(gh pr list --state open --json number --jq '.[].number'); do
    c=$(gh api "repos/{owner}/{repo}/issues/$n/comments" --jq '[.[]|select(.body|contains("<!-- codex-review -->"))]|length' 2>/dev/null || echo 0)
    [ "$c" != 0 ] && echo "  #$n: $c"
  done
  echo "(none shown above = 0)"
}

cmd_markers() { gh api "repos/{owner}/{repo}/issues/$1/comments" --jq '[.[]|select(.body|contains("<!-- codex-review -->"))]|length'; }

cmd_assert_unchanged() {
  guard_repo; git fetch origin --quiet
  local cur; cur=$(git rev-parse "origin/$1")
  if [ "$cur" = "$2" ]; then echo "  ✓ $1 unchanged @ ${cur:0:7}"; else echo "  ✗ $1 MOVED to ${cur:0:7} (expected ${2:0:7})"; exit 1; fi
}

cmd_reset() {
  guard_repo; git fetch origin --quiet
  echo "== reset branches to broken baseline =="
  local br sha
  while IFS=$'\t' read -r br sha; do
    [ -z "$br" ] && continue
    git push origin "+$sha:refs/heads/$br" >/dev/null 2>&1 && echo "  $br -> ${sha:0:7}" || echo "  $br FAILED (is $sha in local object store? run from a fresh clone if so)"
  done <<< "$BASELINES"
  echo "== undraft all + strip labels =="
  local n
  for n in $(gh pr list --state open --json number --jq '.[].number'); do
    gh pr ready "$n" >/dev/null 2>&1 || true
    gh pr edit "$n" --remove-label babysit:ready --remove-label babysit:hold --remove-label wip >/dev/null 2>&1 || true
  done
  echo "== delete codex-review markers (CodeRabbit comments left alone) =="
  local id
  for n in $(gh pr list --state open --json number --jq '.[].number'); do
    for id in $(gh api "repos/{owner}/{repo}/issues/$n/comments" --jq '.[]|select(.body|contains("<!-- codex-review -->"))|.id' 2>/dev/null); do
      gh api -X DELETE "repos/{owner}/{repo}/issues/comments/$id" >/dev/null 2>&1 && echo "  deleted marker $id (PR #$n)"
    done
  done
  echo "reset complete"
}

codex_path() { command -v codex 2>/dev/null || echo "/opt/homebrew/bin/codex"; }
cmd_hide_codex() {
  local p; p=$(command -v codex 2>/dev/null || true)
  [ -n "$p" ] || { echo "codex already not on PATH (fallback will trigger)"; return 0; }
  mv "$p" "$p.hidden-by-harness" && echo "hid codex: $p -> $p.hidden-by-harness (command -v codex now fails)"
}
cmd_restore_codex() {
  local p; for p in /opt/homebrew/bin/codex /usr/local/bin/codex; do
    [ -f "$p.hidden-by-harness" ] && { mv "$p.hidden-by-harness" "$p" && echo "restored codex: $p"; return 0; }
  done
  command -v codex >/dev/null 2>&1 && echo "codex already on PATH" || echo "WARNING: no hidden codex found to restore"
}

case "${1:-}" in
  baseline)          cmd_baseline ;;
  assert-baseline)   cmd_assert_baseline ;;
  status)            cmd_status ;;
  reset)             cmd_reset ;;
  hide-codex)        cmd_hide_codex ;;
  restore-codex)     cmd_restore_codex ;;
  markers)           cmd_markers "${2:?PR number}" ;;
  assert-unchanged)  cmd_assert_unchanged "${2:?branch}" "${3:?sha}" ;;
  *) echo "usage: $0 {baseline|assert-baseline|status|reset|hide-codex|restore-codex|markers <n>|assert-unchanged <branch> <sha>}" >&2; exit 1 ;;
esac
