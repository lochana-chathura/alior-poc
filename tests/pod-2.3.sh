#!/usr/bin/env bash
# PoD 2.3 proof (pipeline half): a new API version rolled out by script, the way a CI/CD job would do it.
# Steps, all through the Publisher REST API: copy accounts 1.0.0 to a new version (default 2.0.0), point the new
# version at mock v2 (pod-b-vm:8082), create a revision, deploy it to both gateways, publish. Rerunnable: an existing
# version is updated and redeployed. Then both versions are called through Front Door: 1.0.0 must answer from v1 and
# the new version from v2, so old clients keep working while new clients use the new version.
# The GUI half is the Publisher's "Create New Version" button (see docs/pod-demo-guide.md, item 2.3).
# Usage: bash tests/pod-2.3.sh [NEW_VERSION]
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh; source tests/lib/cp.sh
NV=${1:-2.0.0}; EP=http://10.20.16.4:8082
mkdir -p evidence/2.3; LOG=evidence/2.3/pod-2.3-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
cp_connect || exit 1; trap 'kill $CP_PF 2>/dev/null' EXIT
id_of(){ api "$PUB/apis?query=name:accounts" | j "l=[a['id'] for a in d['list'] if a['name']=='accounts' and a['version']=='$1']; print(l[0] if l else '')"; }
echo "== $(date -u +%FT%TZ)  pipeline: accounts 1.0.0 -> $NV on $EP"
OLD=$(id_of 1.0.0); NEW=$(id_of "$NV")
if [ -z "$NEW" ]; then NEW=$(api -X POST "$PUB/apis/copy-api?newVersion=$NV&apiId=$OLD&defaultVersion=false" | j "print(d.get('id') or sys.exit('copy failed: '+json.dumps(d)))") || exit 1; echo "  new version created ($NEW)"
else echo "  version $NV exists ($NEW), updating it"; fi
api "$PUB/apis/$NEW" | python3 -c "import sys,json; d=json.load(sys.stdin)
for k in ('production_endpoints','sandbox_endpoints'): d['endpointConfig'][k]['url']='$EP'
print(json.dumps(d))" > /tmp/claude-api-$NEW.json
api -X PUT -H "Content-Type: application/json" "$PUB/apis/$NEW" --data-binary @/tmp/claude-api-$NEW.json -o /dev/null -w "  endpoint set to $EP -> %{http_code}\n"; rm -f /tmp/claude-api-$NEW.json
for old in $(api "$PUB/apis/$NEW/revisions?query=deployed:false" | j "print(' '.join(r['id'] for r in d.get('list',[])))"); do api -X DELETE "$PUB/apis/$NEW/revisions/$old" -o /dev/null; done
REV=$(api -X POST -H "Content-Type: application/json" "$PUB/apis/$NEW/revisions" -d '{"description":"pipeline '"$(date -u +%FT%TZ)"'"}' | j "print(d.get('id') or sys.exit('revision failed: '+json.dumps(d)))") || exit 1
api -X POST -H "Content-Type: application/json" "$PUB/apis/$NEW/deploy-revision?revisionId=$REV" -d '[{"name":"pod-a-gw","vhost":"pod-a-gw.alior-poc.local","displayOnDevportal":true},{"name":"pod-b-gw","vhost":"pod-b-gw.alior-poc.local","displayOnDevportal":true}]' -o /dev/null -w "  deploy to pod-a-gw + pod-b-gw -> %{http_code}\n"
api -X POST "$PUB/apis/change-lifecycle?apiId=$NEW&action=Publish" -o /dev/null -w "  publish -> %{http_code} (400 = already published)\n"
echo "== both versions through Front Door (waiting 15 s for the gateways)"; sleep 15
for v in 1.0.0 "$NV"; do
  want=v1; [ "$v" = "$NV" ] && want=v2
  got=$(curl -s -m 20 -D - -o /dev/null "$FD/accounts/$v/accounts" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-mock-version"{print $2}')
  [ "$got" = "$want" ] && ok "accounts $v answers from mock $got" || bad "accounts $v answered from ${got:-nothing} (want $want)"
done
[ $fail = 0 ] && echo "POD 2.3 PASSED" || { echo "POD 2.3 FAILED"; exit 1; }
