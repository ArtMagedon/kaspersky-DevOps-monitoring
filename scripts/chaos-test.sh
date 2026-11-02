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
 echo "Timed out waiting for $JOB=$expected; last=$value" >&2
 return 1
}

container_snapshot() {
 echo "--- Docker inspect: $CONTAINER ---" >&2
 docker inspect -f 'id={{.Id}} state={{.State.Status}} running={{.State.Running}} restarting={{.State.Restarting}} pid={{.State.Pid}} exit={{.State.ExitCode}} error={{.State.Error}} oom_killed={{.State.OOMKilled}} restart_count={{.RestartCount}} restart_policy={{.HostConfig.RestartPolicy.Name}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' "$CONTAINER" >&2 || true
 echo "--- Docker process list: $CONTAINER ---" >&2
 docker top "$CONTAINER" -eo pid,ppid,user,stat,comm,args >&2 || true
 echo "--- Container PID namespace process snapshot ---" >&2
 docker exec --user 0 "$CONTAINER" sh -c '
  echo "identity:"; id
  echo "PID 1 status:"; sed -n "1,8p" /proc/1/status 2>&1 || true
  echo "PID 1 command:"; tr "\000" " " </proc/1/cmdline 2>/dev/null; echo
  echo "PID 1 children:"; cat /proc/1/task/1/children 2>&1 || true
  for p in /proc/[0-9]*; do
   [ -r "$p/cmdline" ] || continue
   printf "pid=%s cmd=" "${p#/proc/}"
   tr "\000" " " <"$p/cmdline" 2>/dev/null || true
   echo
  done
 ' >&2 || true
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
 container_snapshot
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

previous_count="$(docker inspect -f '{{.RestartCount}}' "$CONTAINER")"
echo "Restart test baseline: restart_count=$previous_count"
container_snapshot

# Attempt to terminate PID 1 from inside the container and preserve the
# command output/status. PID 1 may be protected by Linux PID-namespace rules;
# do not hide that result behind '|| true'.
echo "--- Attempting SIGKILL to container PID 1 ---" >&2
if signal_output="$(docker exec --user 0 "$CONTAINER" sh -c '
 echo "exec identity:"; id
 echo "PID 1 command:"; tr "\000" " " </proc/1/cmdline; echo
 echo "PID 1 children:"; cat /proc/1/task/1/children
 kill -KILL 1
 echo "kill command returned successfully"
' 2>&1)"; then
 signal_status=0
else
 signal_status=$?
fi
printf '%s\n' "$signal_output" >&2
echo "docker exec signal command exit_code=$signal_status" >&2
container_snapshot

if [ "$signal_status" -ne 0 ]; then
 echo "Could not signal PID 1 from inside the container; automatic restart was not tested." >&2
 exit 1
fi

wait_restarted "$previous_count"
wait_probe 1
echo "Chaos test passed: $TARGET"
