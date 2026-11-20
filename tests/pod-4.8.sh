#!/usr/bin/env bash
# PoD 4.8 proof: several routes lead to one microservice (mock v1 on pod-b-vm:8081).
# Three operations of the accounts API and a second API (accounts-rewrite, another context) all reach the same backend.
# Then three public GET routes (/accounts, /balances, /customer/accounts) all reach the same backend call, GET /accounts.
# The mock reports its version, host and port, so the answers show it is the same service. Curl only (no az/kubectl needed).
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/4.8; LOG=evidence/4.8/pod-4.8-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
WANT="v1 pod-b-vm 8081"
RAW=evidence/4.8/routes.txt; echo "# $(date -u +%FT%TZ)  raw responses through $FD" > "$RAW"
echo "== $(date -u +%FT%TZ)  routes through Front Door, all expected to reach: $WANT"
route(){ # method path [body]
  local out code svc
  out=$(curl -s -m 20 -X "$1" -H 'content-type: application/json' ${3:+-d "$3"} -w '\n%{http_code}' "$FD$2")
  code=$(printf '%s' "$out" | tail -1); body=$(printf '%s' "$out" | sed '$d')
  printf '\n## %s %s -> HTTP %s\n%s\n' "$1" "$2" "$code" "$body" >> "$RAW"
  svc=$(printf '%s' "$body" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["version"],d["host"],d["port"],d["path"])' 2>/dev/null)
  [ "$code" = 200 ] && [ "${svc% *}" = "$WANT" ] && ok "$1 $2 -> $code from ${svc% *} (backend path ${svc##* })" || bad "$1 $2 -> ${code:-none} from ${svc:-unreadable} (want 200 from $WANT)"
}
route GET  /accounts/1.0.0/accounts
route POST /accounts/1.0.0/transfers '{"amount":1}'
route POST /accounts/1.0.0/transfers/instant '{"amount":1}'
route GET  /accounts-rewrite/1.0.0/accounts
# Same backend call through several public routes: GET /balances and GET /customer/accounts on the accounts API carry a
# route-level request-rewrite to /accounts (added 2026-11-20), so all three GET routes land on the backend's GET /accounts.
same_call(){ local got; got=$(curl -s -m 20 "$FD$1" | tee -a "$RAW" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["version"],d["host"],d["port"],d["path"])' 2>/dev/null); echo >> "$RAW"
  [ "$got" = "$WANT /accounts" ] && ok "GET $1 -> same backend call: ${got##* } on ${got% *}" || bad "GET $1 -> ${got:-unreadable} (want $WANT /accounts)"; }
echo "== the same backend call (GET /accounts) through three public routes"
for p in /accounts/1.0.0/accounts /accounts/1.0.0/balances /accounts/1.0.0/customer/accounts; do printf '\n## GET %s\n' "$p" >> "$RAW"; same_call "$p"; done
[ $fail = 0 ] && echo "POD 4.8 PASSED" || { echo "POD 4.8 FAILED"; exit 1; }
