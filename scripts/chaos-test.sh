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
wait_restarted() {
 previous_count="$1";attempt=0
 while [ "$attempt" -lt 45 ]; do
  state="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
  restart_count="$(docker inspect -f '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo 0)"
  if [ "$state" = "true" ] && [ "$restart_count" -gt "$previous_count" ]; then
   echo "Container restarted automatically (restart count: $previous_count -> $restart_count)."
   return 0
  fi
  attempt=$((attempt+1));sleep 2
 done
 echo "Automatic restart failed: running=$state, restart_count=$restart_count, expected > $previous_count" >&2
 docker inspect -f 'state={{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}} restart_policy={{.HostConfig.RestartPolicy.Name}}' "$CONTAINER" >&2 || true
 return 1
}
restart_policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER")"
[ "$restart_policy" = "unless-stopped" ] || {
 echo "Unexpected restart policy for $CONTAINER: $restart_policy" >&2
 exit 1
}
docker stop --time 5 "$CONTAINER" >/dev/null
wait_probe 0
docker start "$CONTAINER" >/dev/null
wait_probe 1
# Simulate an unexpected process crash rather than an explicit Docker stop/kill.
# Killing PID 1 makes the container exit naturally, allowing restart policy handling.
previous_count="$(docker inspect -f '{{.RestartCount}}' "$CONTAINER")"
docker exec "$CONTAINER" sh -c 'kill -9 1' >/dev/null 2>&1 || true
wait_restarted "$previous_count"
wait_probe 1
echo "Chaos test passed: $TARGET"
