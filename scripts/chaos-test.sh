#!/bin/sh
set -eu

TARGET="$1"
case "$TARGET" in
 uptime-kuma) CONTAINER=uptime-kuma; JOB=blackbox-uptime-kuma; APP_PROCESS=uptime-kuma ;;
 mariadb) CONTAINER=mariadb; JOB=blackbox-mariadb; APP_PROCESS=mariadbd ;;
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
 echo "Timed out waiting for $JOB=$expected; last=$value" >&2
 return 1
}

container_snapshot() {
 echo "--- Docker inspect: $CONTAINER ---" >&2
 docker inspect -f 'id={{.Id}} state={{.State.Status}} running={{.State.Running}} restarting={{.State.Restarting}} pid={{.State.Pid}} exit={{.State.ExitCode}} error={{.State.Error}} oom_killed={{.State.OOMKilled}} restart_count={{.RestartCount}} restart_policy={{.HostConfig.RestartPolicy.Name}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' "$CONTAINER" >&2 || true
 echo "--- Docker process list: $CONTAINER ---" >&2
 docker top "$CONTAINER" -eo pid,ppid,user,stat,comm,args >&2 || true
}

wait_restarted() {
 previous_count="$1";attempt=0
 while [ "$attempt" -lt 45 ]; do
  state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)"
  restart_count="$(docker inspect -f '{{.RestartCount}}' "$CONTAINER" 2>/dev/null || echo 0)"
  if [ "$state" = "running" ] && [ "$restart_count" -gt "$previous_count" ]; then
   echo "Container restarted automatically (restart count: $previous_count -> $restart_count)."
   return 0
  fi
  attempt=$((attempt+1));sleep 2
 done
 echo "Automatic restart failed: state=$state, restart_count=$restart_count, expected > $previous_count" >&2
 container_snapshot
 return 1
}

restart_policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER")"
[ "$restart_policy" = "unless-stopped" ] || {
 echo "Unexpected restart policy for $CONTAINER: $restart_policy" >&2
 exit 1
}

# A manual stop/start first verifies that monitoring observes downtime and recovery.
# Starting the container again re-enables its restart policy.
docker stop --time 5 "$CONTAINER" >/dev/null
wait_probe 0
docker start "$CONTAINER" >/dev/null
wait_probe 1

previous_count="$(docker inspect -f '{{.RestartCount}}' "$CONTAINER")"
echo "Restart test baseline: restart_count=$previous_count"
container_snapshot

# Crash the application process, not the container via Docker Engine.
# A manual docker kill/stop is treated as an intentional stop and suppresses
# restart-policy handling. Killing the main child lets dumb-init exit naturally.
echo "--- Killing the main application process inside $CONTAINER ---" >&2
if ! docker exec --user 0 "$CONTAINER" sh -c '
 found=0
 for proc in /proc/[0-9]*; do
  [ -r "$proc/comm" ] || continue
  IFS= read -r name < "$proc/comm" || continue
  if [ "$name" = "$APP_PROCESS" ]; then
   pid="${proc##*/}"
   echo "Sending SIGKILL to application PID $pid (comm=$name)" >&2
   kill -KILL "$pid"
   found=1
   break
  fi
 done
 [ "$found" -eq 1 ] || { echo "Could not find application process: $APP_PROCESS" >&2; exit 1; }
'; then
 echo "Failed to terminate the application process" >&2
 container_snapshot
 exit 1
fi

wait_restarted "$previous_count"
wait_probe 1
echo "Chaos test passed: $TARGET"
