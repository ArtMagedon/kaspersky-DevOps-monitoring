#!/bin/sh
set -eu
curl -fsS --max-time 10 http://uptime-kuma:3001/ >/dev/null
curl -fsS --max-time 10 http://prometheus:9090/-/healthy >/dev/null
curl -fsS --max-time 10 http://grafana:3000/api/health >/dev/null

# Allow at least one Prometheus scrape after the stack has become healthy.
attempt=0
while [ "$attempt" -lt 40 ]; do
  if python3 - <<'PY'
import json,sys,urllib.parse,urllib.request
checks={"Uptime Kuma HTTP":'probe_success{job="blackbox-uptime-kuma"}',"MariaDB TCP":'probe_success{job="blackbox-mariadb"}',"MariaDB exporter":"mysql_up"}
for name,query in checks.items():
    url="http://prometheus:9090/api/v1/query?query="+urllib.parse.quote(query)
    try:
        with urllib.request.urlopen(url,timeout=5) as r:
            rows=json.load(r).get("data",{}).get("result",[])
    except Exception:
        sys.exit(1)
    if not rows or float(rows[0]["value"][1]) != 1:
        sys.exit(1)
print("All Prometheus checks are UP.")
PY
  then
    exit 0
  fi
  attempt=$((attempt+1))
  sleep 3
done
echo "Prometheus probes/exporter did not become healthy in time." >&2
exit 1
