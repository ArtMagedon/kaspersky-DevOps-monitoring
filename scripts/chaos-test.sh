#!/bin/sh
set -eu
TARGET="$1"
case "$TARGET" in
 uptime-kuma) CONTAINER=uptime-kuma; JOB=blackbox-uptime-kuma ;;
 mariadb) CONTAINER=mariadb; JOB=blackbox-mariadb ;;
 *) echo "Usage: chaos-test.sh uptime-kuma|mariadb" >&2; exit 2 ;;
esac
probe_value() {
 python3 - "$JOB" <<'PY'
import json,sys,urllib.parse,urllib.request
job=sys.argv[1];query='probe_success{job="'+job+'"}'
url="http://prometheus:9090/api/v1/query?query="+urllib.parse.quote(query)
try:
 with urllib.request.urlopen(url,timeout=5) as r: rows=json.load(r).get("data",{}).get("result",[])
 print(rows[0]["value"][1] if rows else "missing")
except Exception: print("missing")
PY
}
wait_probe() {
 expected="$1";attempt=0
 while [ "$attempt" -lt 45 ]; do
  value="$(probe_value)"
  [ "$value" = "$expected" ] && { echo "Observed $JOB=$expected";return 0; }
  attempt=$((attempt+1));sleep 2
 done
 echo "Timed out waiting for $JOB=$expected; last=$value" >&2;return 1
}
docker stop --time 5 "$CONTAINER" >/dev/null
wait_probe 0
docker start "$CONTAINER" >/dev/null
wait_probe 1
sleep 12
docker kill "$CONTAINER" >/dev/null
attempt=0;running=false
while [ "$attempt" -lt 30 ]; do
 running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
 [ "$running" = "true" ] && break
 attempt=$((attempt+1));sleep 2
done
[ "$running" = "true" ] || { echo "Restart policy did not recover container" >&2;exit 1; }
wait_probe 1
echo "Chaos test passed: $TARGET"
