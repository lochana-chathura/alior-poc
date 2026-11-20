#!/usr/bin/env bash
# PoD 4.3 proof: gateway behaviour when the backend does not answer.
#  1. Backend not there: API nobackend 1.0.0 points at a closed port (10.20.16.4:8099). Through Front Door the gateway
#     answers 503 "upstream connect error" straight away.
#  2. Backend too slow: the gateway's backend timeout is route_timeout_ms = 30000 (platform/gateway/region-*/gateway-values.yaml,
#     set 2026-11-20, chart default 60000). Front Door's origin timeout is 60 s, above it, so the call goes through Front
#     Door like a real client: 200 for a 5 s delay, and for 35 s the gateway gives up after 30 s with 504
#     "upstream request timeout" (the gateway's plain text body, not Front Door's HTML error page).
# Curl only, takes about 40 s.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/4.3; LOG=evidence/4.3/pod-4.3-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
echo "== $(date -u +%FT%TZ)  1. backend not there: GET $FD/nobackend/1.0.0/accounts"
out=$(curl -s -m 40 -w '\n%{http_code} %{time_total}' "$FD/nobackend/1.0.0/accounts"); echo "$out" | sed 's/^/     /'
code=$(echo "$out" | tail -1 | awk '{print $1}'); t=$(echo "$out" | tail -1 | awk '{print $2}')
[ "$code" = 503 ] && echo "$out" | grep -q "upstream connect error" && ok "gateway answered 503 upstream connect error in ${t}s" || bad "got ${code:-none} (want 503 from the gateway)"

echo "== 2. backend too slow, through Front Door (gateway timeout 30 s, Front Door 60 s)"
for d in 5000 35000; do
  out=$(curl -s -m 70 -H "x-mock-delay-ms: $d" -w '\n%{http_code} %{time_total}' "$FD/accounts/1.0.0/accounts")
  code=$(echo "$out" | tail -1 | awk '{print $1}'); t=$(echo "$out" | tail -1 | awk '{print $2}'); body=$(echo "$out" | sed '$d' | head -c 80)
  printf '     delay=%s ms -> HTTP %s in %ss  body=%s\n' "$d" "$code" "$t" "$body"
  if [ $d = 5000 ]; then [ "$code" = 200 ] && ok "5 s delay is inside the timeout: 200" || bad "5 s delay: got $code"
  else echo "$out" | grep -q 'upstream request timeout' && [ "$code" = 504 ] && python3 -c "import sys; sys.exit(0 if 29 <= float('${t:-0}') <= 32 else 1)" \
    && ok "35 s delay: the gateway gave up after ${t}s with 504 upstream request timeout" \
    || bad "35 s delay: HTTP $code after ${t}s (want 504 upstream request timeout from the gateway after about 30 s. An HTML OriginTimeout page means Front Door answered first)"; fi
done
[ $fail = 0 ] && echo "POD 4.3 PASSED" || { echo "POD 4.3 FAILED"; exit 1; }
