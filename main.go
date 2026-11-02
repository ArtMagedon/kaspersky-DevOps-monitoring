package main
import("context";"fmt";"dagger/uptime-kuma-monitoring/internal/dagger")
type UptimeKumaMonitoring struct{}
func(m *UptimeKumaMonitoring) docker(ctx context.Context,script string)error{
 _,err:=dag.Container().From("docker:cli").WithExec([]string{"sh","-lc","apk add --no-cache docker-cli-compose"}).
 WithUnixSocket("/var/run/docker.sock",dag.Host().UnixSocket("/var/run/docker.sock")).
 WithMountedDirectory("/workspace",dag.Host().Directory(".")).WithWorkdir("/workspace").
 WithExec([]string{"sh","-lc",script}).Stdout(ctx);return err
}
func(m *UptimeKumaMonitoring) prepare(ctx context.Context)error{return m.docker(ctx,"test -f .env || { echo 'Create .env from .env.example'; exit 1; }; docker network inspect kuma-observability >/dev/null 2>&1 || docker network create kuma-observability")}
func(m *UptimeKumaMonitoring) networkCommand(ctx context.Context,cmd string)error{return m.docker(ctx,"docker run --rm --network kuma-observability -v /var/run/docker.sock:/var/run/docker.sock -v \"$PWD:/workspace\" -w /workspace docker:cli sh -lc 'apk add --no-cache curl python3 >/dev/null && "+cmd+"'")}
// DeployApp starts MariaDB and Uptime Kuma.
func(m *UptimeKumaMonitoring) DeployApp(ctx context.Context)(string,error){if e:=m.prepare(ctx);e!=nil{return "",e};if e:=m.docker(ctx,"docker compose --env-file .env -f compose/app.yml up -d --wait --wait-timeout 180");e!=nil{return "",fmt.Errorf("deploy-app: %w",e)};return "MariaDB and Uptime Kuma deployed.",nil}
// DeployMonitoring starts Prometheus, Grafana and exporters.
func(m *UptimeKumaMonitoring) DeployMonitoring(ctx context.Context)(string,error){if e:=m.prepare(ctx);e!=nil{return "",e};if e:=m.docker(ctx,"docker compose --env-file .env -f compose/monitoring.yml up -d --wait --wait-timeout 180");e!=nil{return "",fmt.Errorf("deploy-monitoring: %w",e)};return "Prometheus, Grafana and exporters deployed.",nil}
// ConfigureGrafana applies datasource and dashboard through Grafana HTTP API.
func(m *UptimeKumaMonitoring) ConfigureGrafana(ctx context.Context)(string,error){if e:=m.prepare(ctx);e!=nil{return "",e};if e:=m.networkCommand(ctx,"sh scripts/configure-grafana.sh");e!=nil{return "",fmt.Errorf("configure-grafana: %w",e)};return "Grafana datasource and dashboard configured.",nil}
// DeployAll deploys both layers, configures Grafana and validates the stack.
func(m *UptimeKumaMonitoring) DeployAll(ctx context.Context)(string,error){if _,e:=m.DeployApp(ctx);e!=nil{return "",e};if _,e:=m.DeployMonitoring(ctx);e!=nil{return "",e};if _,e:=m.ConfigureGrafana(ctx);e!=nil{return "",e};if e:=m.networkCommand(ctx,"sh scripts/validate.sh");e!=nil{return "",fmt.Errorf("validation: %w",e)};return "Full stack deployed; validation passed.",nil}
// Validate checks endpoints and Prometheus probes.
func(m *UptimeKumaMonitoring) Validate(ctx context.Context)(string,error){if e:=m.networkCommand(ctx,"sh scripts/validate.sh");e!=nil{return "",e};return "Validation passed.",nil}
// ChaosTest checks DOWN/UP and restart-policy recovery.
func(m *UptimeKumaMonitoring) ChaosTest(ctx context.Context,target string)(string,error){if target!="uptime-kuma"&&target!="mariadb"{return "",fmt.Errorf("target must be uptime-kuma or mariadb")};if e:=m.networkCommand(ctx,"sh scripts/chaos-test.sh "+target);e!=nil{return "",e};return "Chaos test passed for "+target+".",nil}
