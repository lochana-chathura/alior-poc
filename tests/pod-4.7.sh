#!/usr/bin/env bash
# PoD 4.7 proof: route conflicts and priorities. API routes 1.0.0 (context /routes, backend mock v1) has overlapping
# operations: POST /transfers, POST /transfers/instant and the wildcard POST /transfers/* (listed FIRST on purpose).
# An API-level request-rewrite (ReplacePrefixMatch to /matched) replaces the prefix of the operation that matched and
# keeps the rest, so the path the mock echoes shows which route won:
#   exact /transfers/instant won   -> backend gets /matched
#   wildcard /transfers/* won      -> backend gets /matched/<rest>
# Curl only (no az/kubectl needed). The API was created on 2026-11-19 through the Publisher REST API.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/4.7; LOG=evidence/4.7/pod-4.7-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
echo "== $(date -u +%FT%TZ)  overlapping routes on $FD/routes/1.0.0"
check(){ # client-path expected-backend-path meaning
  local got; got=$(curl -s -m 20 -X POST -H 'content-type: application/json' -d '{}' "$FD/routes/1.0.0$1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["path"])' 2>/dev/null)
  printf '  client %-24s backend %s\n' "$1" "${got:-unreadable}"
  [ "$got" = "$2" ] && ok "$3" || bad "$3 (want backend path $2)"
}
check /transfers            /matched              "/transfers matched its own exact route"
check /transfers/instant    /matched              "/transfers/instant matched the exact route, not the wildcard listed before it"
check /transfers/other      /matched/other        "/transfers/other fell through to the wildcard /transfers/*"
check /transfers/instant/x  /matched/instant/x    "/transfers/instant/x is deeper than the exact route, so the wildcard took it"
[ $fail = 0 ] && echo "POD 4.7 PASSED" || { echo "POD 4.7 FAILED"; exit 1; }
