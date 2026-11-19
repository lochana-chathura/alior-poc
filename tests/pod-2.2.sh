#!/usr/bin/env bash
# PoD 2.2 proof: gateways managed per environment or system.
# The control plane manages two gateways (pod-a-gw in region A, pod-b-gw in region B). API system-a 1.0.0 is deployed
# to pod-a-gw only (created 2026-11-19), while accounts 1.0.0 is deployed to both. Calls go through Front Door, which
# may pick either region, and each call's x-request-id is looked up in the router logs to see which gateway took it:
# region A answers system-a with 200, region B does not know it and answers 404.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh; source tests/lib/cp.sh
mkdir -p evidence/2.2; LOG=evidence/2.2/pod-2.2-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
T=$(mktemp -d); cp_connect || exit 1; trap 'kill $CP_PF 2>/dev/null; rm -rf "$T"' EXIT
echo "== $(date -u +%FT%TZ)  gateways registered in the control plane (Admin REST API)"
api "$CP/api/am/admin/v4/gateways" | j "[print('  %-10s %-45s active=%s visibility=%s' % (g['name'], g.get('description',''), g.get('isActive'), g.get('permissions',{}).get('permissionType'))) for g in d['list']]"
echo "== where each API is deployed"
for n in accounts system-a; do
  ID=$(api "$PUB/apis?query=name:$n" | j "l=[a['id'] for a in d['list'] if a['name']=='$n' and a['version']=='1.0.0']; print(l[0] if l else '')")
  printf '  %-10s -> ' "$n"; api "$PUB/apis/$ID/deployments" | j "L=d if isinstance(d,list) else d.get('list',[]); print(', '.join(sorted(set(x.get('name','') for x in L))) or 'none')"
done
echo "== 8 calls to system-a through Front Door, matched to the gateway that served each"
for i in $(seq 1 8); do curl -s -m 20 -D "$T/h$i" -o /dev/null "$FD/system-a/1.0.0/accounts"; done; sleep 15   # router access logs flush with a delay
for c in pod-a-aks pod-b-aks; do kubectl --context $c -n wso2-gw logs -l app.kubernetes.io/component=gateway-runtime --since=5m --tail=2000 --max-log-requests=10 --request-timeout=40s 2>/dev/null > "$T/log-$c"; done
a=0; b=0
for i in $(seq 1 8); do
  code=$(head -1 "$T/h$i" | awk '{print $2}'); rid=$(tr -d '\r' < "$T/h$i" | awk -F': ' 'tolower($1)=="x-request-id"{print $2}')
  where=unknown; grep -q "\"reqId\":\"$rid\"" "$T/log-pod-a-aks" && where=A; grep -q "\"reqId\":\"$rid\"" "$T/log-pod-b-aks" && where=B
  printf '  call %s -> HTTP %s from region %s\n' "$i" "$code" "$where"
  case "$where$code" in A200) a=$((a+1));; B404) b=$((b+1));; *) bad "call $i: region $where answered $code";; esac
done
[ $a -gt 0 ] && ok "region A (has system-a) answered 200 on $a calls" || echo "  info no call landed on region A this run"
[ $b -gt 0 ] && ok "region B (system-a not deployed) answered 404 on $b calls" || echo "  info no call landed on region B this run"
[ $((a+b)) -gt 0 ] || bad "no call could be matched to a gateway"
[ $fail = 0 ] && echo "POD 2.2 PASSED" || { echo "POD 2.2 FAILED"; exit 1; }
