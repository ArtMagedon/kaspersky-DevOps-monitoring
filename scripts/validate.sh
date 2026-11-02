#!/bin/sh
set -eu
curl -fsS --max-time 10 http://uptime-kuma:3001/ >/dev/null
curl -fsS --max-time 10 http://prometheus:9090/-/healthy >/dev/null
curl -fsS --max-time 10 http://grafana:3000/api/health >/dev/null
python3 - <<'PY'
import json,sys,urllib.parse,urllib.request
checks={"Uptime Kuma HTTP":'probe_success{job="blackbox-uptime-kuma"}',"MariaDB TCP":'probe_success{job="blackbox-mariadb"}',"MariaDB exporter":"mysql_up"}
for name,query in checks.items():
 url="http://prometheus:9090/api/v1/query?query="+urllib.parse.quote(query)
 with urllib.request.urlopen(url,timeout=10) as r: rows=json.load(r).get("data",{}).get("result",[])
 if not rows or float(rows[0]["value"][1])!=1:
  print("FAIL:",name,rows,file=sys.stderr);sys.exit(1)
 print("OK:",name)
PY
