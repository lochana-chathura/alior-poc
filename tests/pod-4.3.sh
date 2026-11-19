#!/usr/bin/env bash
# PoD 4.3 proof: gateway behaviour when the backend does not answer.
#  1. Backend not there: API nobackend 1.0.0 points at a closed port (10.20.16.4:8099). Through Front Door the gateway
#     answers 503 "upstream connect error" straight away.
#  2. Backend too slow: the gateway's upstream timeout is route_timeout_ms = 60000 (gateway config, live value checked
#     2026-11-19). Front Door's origin timeout is 30 s, so this case is called inside region A (curl pod -> gateway
#     ClusterIP) to see the gateway's own answer: 200 for a 5 s delay, 504 "upstream request timeout" after 60 s for 65 s.
# Needs kubectl access to pod-a-aks for part 2 (takes about 70 s).
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/4.3; LOG=evidence/4.3/pod-4.3-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
echo "== $(date -u +%FT%TZ)  1. backend not there: GET $FD/nobackend/1.0.0/accounts"
out=$(curl -s -m 40 -w '\n%{http_code} %{time_total}' "$FD/nobackend/1.0.0/accounts"); echo "$out" | sed 's/^/     /'
code=$(echo "$out" | tail -1 | awk '{print $1}'); t=$(echo "$out" | tail -1 | awk '{print $2}')
[ "$code" = 503 ] && echo "$out" | grep -q "upstream connect error" && ok "gateway answered 503 upstream connect error in ${t}s" || bad "got ${code:-none} (want 503 from the gateway)"

echo "== 2. backend too slow, called inside region A (gateway ClusterIP, Front Door not in the path)"
GW="http://pod-a-gw-gw-gateway-gateway-runtime.wso2-gw.svc.cluster.local:8080/accounts/1.0.0/accounts"
out=$(kubectl --context pod-a-aks --request-timeout=200s -n apps run curl-pod-4-3 --rm -i --restart=Never --image=curlimages/curl:8.11.1 --quiet -- sh -c "
  sleep 2; for d in 5000 65000; do curl -s -m 100 -H 'Host: pod-a-gw.alior-poc.local' -H \"x-mock-delay-ms: \$d\" -o /tmp/b -w 'code=%{http_code} time=%{time_total} ' $GW; printf 'body=%s delay=%s\n' \"\$(head -c 80 /tmp/b)\" \$d; done" 2>/dev/null)
echo "$out" | sed 's/^/     /'
l1=$(echo "$out" | grep 'delay=5000$'); l2=$(echo "$out" | grep 'delay=65000$')
echo "$l1" | grep -q 'code=200' && ok "5 s delay is inside the timeout: 200" || bad "5 s delay: ${l1:-no answer}"
t2=$(echo "$l2" | sed -n 's/.*time=\([0-9.]*\).*/\1/p')
echo "$l2" | grep -q 'code=504' && echo "$l2" | grep -q 'upstream request timeout' && python3 -c "import sys; sys.exit(0 if 59 <= float('${t2:-0}') <= 62 else 1)" \
  && ok "65 s delay: gateway gave up after ${t2}s with 504 upstream request timeout" || bad "65 s delay: ${l2:-no answer} (want 504 after about 60 s)"
[ $fail = 0 ] && echo "POD 4.3 PASSED" || { echo "POD 4.3 FAILED"; exit 1; }
