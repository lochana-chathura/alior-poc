#!/usr/bin/env bash
# PoD 4.1 proof: a client is routed to a microservice through the gateway.
# Calls the published accounts API through Front Door.
#   200 + x-mock-version: v1  -> the request reached mock v1 on pod-b-vm
#   x-pod-gateway: wso2-api-platform-gateway -> set by the set-headers policy on the API (deployed 2026-11-19), so
#       the call went through the gateway. The mock and Front Door cannot add it.
#   x-envoy-upstream-service-time -> added by the gateway's Envoy router (supporting sign)
#   404 for an unpublished path -> only published APIs are routed
#   which gateway answered: each call's x-request-id is looked up in the router access logs of both regions
#       (needs kubectl access to pod-a-aks and pod-b-aks, skipped otherwise)
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/4.1; LOG=evidence/4.1/pod-4.1-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
hdr(){ tr -d '\r' < "$1" | grep -i "^$2:" | head -1 | cut -d: -f2- | xargs; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
echo "== $(date -u +%FT%TZ)  GET $FD/accounts/1.0.0/accounts (3 tries)"
for i in 1 2 3; do
  curl -s -m 20 -D "$T/h$i" -o "$T/b$i" "$FD/accounts/1.0.0/accounts"
  code=$(head -1 "$T/h$i" | awk '{print $2}'); ver=$(hdr "$T/h$i" x-mock-version); env=$(hdr "$T/h$i" x-envoy-upstream-service-time)
  [ "$code" = 200 ] && [ "$ver" = v1 ] && ok "try $i -> $code, x-mock-version=$ver" || bad "try $i -> ${code:-none}, x-mock-version=${ver:-none} (want 200, v1)"
  [ -n "$env" ] && ok "try $i gateway header x-envoy-upstream-service-time=$env" || bad "try $i no x-envoy-upstream-service-time header"
  pg=$(hdr "$T/h$i" x-pod-gateway); [ "$pg" = wso2-api-platform-gateway ] && ok "try $i policy header x-pod-gateway=$pg" || bad "try $i no x-pod-gateway header (set-headers policy)"
done
echo "== response of try 3"; cat "$T/h3"; cat "$T/b3"; echo
body=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["host"],d["port"],d["path"])' "$T/b3" 2>/dev/null)
[ "$body" = "pod-b-vm 8081 /accounts" ] && ok "backend that answered: $body (mock v1 on the VM)" || bad "backend that answered: ${body:-unreadable} (want pod-b-vm 8081 /accounts)"
echo "== GET $FD/nope/1.0.0/accounts (not published)"
curl -s -m 20 -D "$T/hn" -o "$T/bn" "$FD/nope/1.0.0/accounts"; cat "$T/hn" "$T/bn"; echo
code=$(head -1 "$T/hn" | awk '{print $2}'); [ "$code" = 404 ] && ok "unpublished path -> $code" || bad "unpublished path -> ${code:-none} (want 404)"
if kubectl --context pod-a-aks get ns default --request-timeout=20s >/dev/null 2>&1; then
  echo "== which gateway answered (x-request-id looked up in the router access logs)"; sleep 5
  for c in pod-a-aks pod-b-aks; do kubectl --context $c -n wso2-gw logs -l app.kubernetes.io/component=gateway-runtime --since=5m --tail=2000 --max-log-requests=10 --request-timeout=40s 2>/dev/null > "$T/log-$c"; done
  for i in 1 2 3; do rid=$(hdr "$T/h$i" x-request-id); where=""
    grep -q "\"reqId\":\"$rid\"" "$T/log-pod-a-aks" && where="region A (pod-a-gw)"
    grep -q "\"reqId\":\"$rid\"" "$T/log-pod-b-aks" && where="${where:+$where and }region B (pod-b-gw)"
    [ -n "$where" ] && ok "try $i (x-request-id $rid) was served by the gateway in $where" || bad "try $i request $rid not found in either router log"
  done
else echo "  info kubectl not available, skipping the per-gateway lookup"; fi
[ $fail = 0 ] && echo "POD 4.1 PASSED" || { echo "POD 4.1 FAILED"; exit 1; }
