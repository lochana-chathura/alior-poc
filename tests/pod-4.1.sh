#!/usr/bin/env bash
# PoD 4.1 proof: a client is routed to a microservice through the gateway.
# Curl only (no az/kubectl needed): calls the published accounts API through Front Door.
#   200 + x-mock-version: v1  -> the request reached mock v1 on pod-b-vm
#   x-envoy-upstream-service-time -> added by the gateway's Envoy router, so the call went through the gateway
#   404 for an unpublished path -> only published APIs are routed
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
done
echo "== response of try 3"; cat "$T/h3"; cat "$T/b3"; echo
body=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["host"],d["port"],d["path"])' "$T/b3" 2>/dev/null)
[ "$body" = "pod-b-vm 8081 /accounts" ] && ok "backend that answered: $body (mock v1 on the VM)" || bad "backend that answered: ${body:-unreadable} (want pod-b-vm 8081 /accounts)"
echo "== GET $FD/nope/1.0.0/accounts (not published)"
curl -s -m 20 -D "$T/hn" -o "$T/bn" "$FD/nope/1.0.0/accounts"; cat "$T/hn" "$T/bn"; echo
code=$(head -1 "$T/hn" | awk '{print $2}'); [ "$code" = 404 ] && ok "unpublished path -> $code" || bad "unpublished path -> ${code:-none} (want 404)"
[ $fail = 0 ] && echo "POD 4.1 PASSED" || { echo "POD 4.1 FAILED"; exit 1; }
