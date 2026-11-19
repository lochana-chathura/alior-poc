#!/usr/bin/env bash
# PoD 4.6 proof: path prefix stripping. The client calls /accounts/1.0.0/accounts (API context /accounts + version 1.0.0 +
# resource /accounts); the gateway removes the context and version and the backend receives only /accounts.
# The mock echoes the path it received in the JSON body. Curl only (no az/kubectl needed).
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/4.6; LOG=evidence/4.6/pod-4.6-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=${FD:-https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net}
REQ=/accounts/1.0.0/accounts
echo "== $(date -u +%FT%TZ)  client calls GET $FD$REQ"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
curl -s -m 20 -D "$T/h" -o "$T/b" "$FD$REQ"
# raw response kept as its own evidence file (overwritten on every run)
{ echo "# $(date -u +%FT%TZ)  GET $FD$REQ"; cat "$T/h"; cat "$T/b"; echo; } | tee evidence/4.6/backend-path.txt
got=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["path"])' "$T/b" 2>/dev/null)
echo "  client sent : $REQ"
echo "  backend got : ${got:-unreadable}"
[ "$got" = /accounts ] && ok "prefix /accounts/1.0.0 stripped before the backend" || bad "backend path is '${got:-unreadable}' (want /accounts)"
[ "$got" != "$REQ" ] && ok "backend path differs from the client path" || bad "backend received the unstripped path"
# Configured rewrite: API accounts-rewrite carries request-rewrite (ReplacePrefixMatch to /legacy/accounts, fixed 2026-11-19).
REQ2=/accounts-rewrite/1.0.0/accounts
echo "== client calls GET $FD$REQ2 (request-rewrite policy on the API)"
curl -s -m 20 -D "$T/h2" -o "$T/b2" "$FD$REQ2"
{ echo "# $(date -u +%FT%TZ)  GET $FD$REQ2"; cat "$T/h2"; cat "$T/b2"; echo; } | tee evidence/4.6/configured-rewrite.txt
got2=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["path"])' "$T/b2" 2>/dev/null)
echo "  client sent : $REQ2"
echo "  backend got : ${got2:-unreadable}"
[ "$got2" = /legacy/accounts ] && ok "configured rewrite: /accounts forwarded as /legacy/accounts" || bad "backend path is '${got2:-unreadable}' (want /legacy/accounts)"
[ $fail = 0 ] && echo "POD 4.6 PASSED" || { echo "POD 4.6 FAILED"; exit 1; }
