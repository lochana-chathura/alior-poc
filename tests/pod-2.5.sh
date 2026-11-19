#!/usr/bin/env bash
# PoD 2.5 proof: auditing configuration changes ("who added this route, and when").
# Shows, for one API (default: routes), the APIM audit log lines (performedBy, action, time, gateways) and the
# Publisher revision history. Read only.
# Note: audit.log lives inside the control plane pod and starts empty after each restart (daily office-hours start),
# so it only covers changes made since the last start.
# Usage: bash tests/pod-2.5.sh [API_NAME]
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh; source tests/lib/cp.sh
N=${1:-routes}
mkdir -p evidence/2.5; LOG=evidence/2.5/pod-2.5-$N-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
echo "== $(date -u +%FT%TZ)  APIM audit log entries for API $N (control plane pod in pod-a-aks)"
P=$(kubectl --context pod-a-aks -n wso2-cp get pods -o name | grep am-deployment | head -1)
lines=$(kubectl --context pod-a-aks -n wso2-cp exec "$P" -- sh -c 'grep performedBy /home/wso2carbon/wso2am-4.7.0/repository/logs/audit.log' 2>/dev/null | grep "\"name\":\"$N\"")
printf '%s\n' "$lines" | python3 -c '
import sys, json, re
for l in sys.stdin:
    m = re.search(r"\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", l); j = l[l.find("{\"performedBy"):]
    try: d = json.loads(j)
    except Exception: continue
    i = d.get("info", {})
    print("  %s UTC  by %-8s %-8s %s %s %s" % (m.group(1) if m else "?", d["performedBy"], d["action"], i.get("name"), i.get("context"), ",".join(i.get("environments", []))))'
[ -n "$lines" ] && ok "audit log names who changed $N and when" || bad "no audit lines for $N since the last control plane start"
cp_connect || exit 1; trap 'kill $CP_PF 2>/dev/null' EXIT
echo "== Publisher revision history for $N"
ID=$(api "$PUB/apis?query=name:$N" | j "l=[a['id'] for a in d['list'] if a['name']=='$N']; print(l[0] if l else '')")
api "$PUB/apis/$ID/revisions" | j "import datetime; [print('  %s UTC  %-12s deployed to: %s  (%s)' % (datetime.datetime.utcfromtimestamp(int(r.get('createdTime',0))/1000).strftime('%Y-%m-%d %H:%M:%S'), r.get('displayName'), ','.join(x.get('name','') for x in r.get('deploymentInfo',[])) or '-', r.get('description',''))) for r in d.get('list',[])]"
[ -n "$ID" ] && ok "revision history listed" || bad "API $N not found"
[ $fail = 0 ] && echo "POD 2.5 PASSED" || { echo "POD 2.5 FAILED"; exit 1; }
