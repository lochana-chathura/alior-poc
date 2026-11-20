#!/usr/bin/env bash
# PoD 4.7 proof: route conflicts and priorities. API routes 1.0.0 (context /routes, backend mock v1) has overlapping
# operations: POST /transfers, POST /transfers/instant and the wildcard POST /transfers/* (listed FIRST on purpose).
# An API-level request-rewrite (ReplacePrefixMatch to /matched) replaces the prefix of the operation that matched and
# keeps the rest, so the path the mock echoes shows which route won:
#   exact /transfers/instant won   -> backend gets /matched
#   wildcard /transfers/* won      -> backend gets /matched/<rest>
# Part 2, overlapping URLs on DIFFERENT services (the bank's case, added 2026-11-20). Two APIs whose contexts overlap:
#   transfers          context /{version}/transfers           routes POST / and POST /*  -> mock v1 (http://10.20.16.4:8081/transfers)
#   transfers-instant  context /{version}/transfers/instant   routes POST / and POST /*  -> mock v2 (http://10.20.16.4:8082/transfers/instant)
# /1.0.0/transfers/instant matches both (the transfers wildcard covers it), and the more specific transfers-instant wins.
# The version goes first in the context so the two URLs really overlap. (A different backend per route inside ONE API
# needs upstreamDefinitions, which APIM 4.7.0.23 does not send. Default version, to drop the version from the URL,
# is not supported by the API Platform gateway: its context always holds the version.)
# Curl only (no az/kubectl needed). APIs created through the Publisher REST API (routes 2026-11-19, the other two 2026-11-20).
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
echo "== overlapping URLs on different services: $FD/1.0.0/transfers..."
svc(){ # client-path expected "version backend-path" meaning
  local got; got=$(curl -s -m 20 -X POST -H 'content-type: application/json' -d '{}' "$FD$1" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["version"],d["path"])' 2>/dev/null)
  printf '  client %-30s service %s\n' "$1" "${got:-unreadable}"
  [ "$got" = "$2" ] && ok "$3" || bad "$3 (want $2)"
}
svc /1.0.0/transfers             "v1 /transfers"            "/transfers goes to the transfers service (mock v1)"
svc /1.0.0/transfers/instant     "v2 /transfers/instant"    "/transfers/instant goes to its own service (mock v2), although the transfers wildcard also matches"
svc /1.0.0/transfers/other       "v1 /transfers/other"      "/transfers/other has no specific API, so the transfers service takes it"
svc /1.0.0/transfers/instant/x   "v2 /transfers/instant/x"  "/transfers/instant/x stays with the instant service"
[ $fail = 0 ] && echo "POD 4.7 PASSED" || { echo "POD 4.7 FAILED"; exit 1; }
