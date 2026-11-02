package main

import (
	"context"
	"fmt"

	"dagger/uptime-kuma-monitoring/internal/dagger"
)

type UptimeKumaMonitoring struct{}

func (m *UptimeKumaMonitoring) docker(ctx context.Context, script string) error {
	_, err := dag.Container().From("docker:cli").
		WithExec([]string{"sh", "-lc", "apk add --no-cache docker-cli-compose"}).
		WithUnixSocket("/var/run/docker.sock", dag.Host().UnixSocket("/var/run/docker.sock")).
		WithMountedDirectory("/workspace", dag.Host().Directory(".")).
		WithWorkdir("/workspace").
		WithExec([]string{"sh", "-lc", script}).Stdout(ctx)
	return err
}

func (m *UptimeKumaMonitoring) prepare(ctx context.Context) error {
	return m.docker(ctx, "test -f .env || { echo 'Create .env from .env.example'; exit 1; }; docker network inspect kuma-observability >/dev/null 2>&1 || docker network create kuma-observability")
}

// The helper is attached to the Docker network. docker cp transfers workspace
// files through the Docker API; a bind mount would incorrectly resolve paths
// on the host daemon rather than inside the Dagger container.
func (m *UptimeKumaMonitoring) networkCommand(ctx context.Context, cmd string) error {
	script := "set -eu; name=kuma-dagger-helper; " +
		"docker rm -f $name >/dev/null 2>&1 || true; " +
		"docker run -d --name $name --network kuma-observability -v /var/run/docker.sock:/var/run/docker.sock alpine:3.21 sleep 3600 >/dev/null; " +
		"trap 'docker rm -f $name >/dev/null 2>&1 || true' EXIT; " +
		"docker exec $name mkdir -p /workspace; " +
		"docker cp scripts $name:/workspace/; docker cp grafana $name:/workspace/; docker cp .env $name:/workspace/.env; " +
		"docker exec $name apk add --no-cache curl python3 docker-cli >/dev/null; " +
		"docker exec -w /workspace $name sh -lc 'sh " + cmd + "'"
	return m.docker(ctx, script)
}

// DeployApp starts MariaDB and Uptime Kuma.
func (m *UptimeKumaMonitoring) DeployApp(ctx context.Context) (string, error) {
	if err := m.prepare(ctx); err != nil { return "", err }
	if err := m.docker(ctx, "docker compose --env-file .env -f compose/app.yml up -d --wait --wait-timeout 180"); err != nil {
		return "", fmt.Errorf("deploy-app: %w", err)
	}
	return "MariaDB and Uptime Kuma deployed.", nil
}

// DeployMonitoring starts Prometheus, Grafana and exporters.
func (m *UptimeKumaMonitoring) DeployMonitoring(ctx context.Context) (string, error) {
	if err := m.prepare(ctx); err != nil { return "", err }
	if err := m.docker(ctx, "docker compose --env-file .env -f compose/monitoring.yml up -d --wait --wait-timeout 180"); err != nil {
		return "", fmt.Errorf("deploy-monitoring: %w", err)
	}
	return "Prometheus, Grafana and exporters deployed.", nil
}

// ConfigureGrafana applies datasource and dashboard through Grafana HTTP API.
func (m *UptimeKumaMonitoring) ConfigureGrafana(ctx context.Context) (string, error) {
	if err := m.prepare(ctx); err != nil { return "", err }
	if err := m.networkCommand(ctx, "scripts/configure-grafana.sh"); err != nil {
		return "", fmt.Errorf("configure-grafana: %w", err)
	}
	return "Grafana datasource and dashboard configured.", nil
}

// DeployAll deploys both layers, configures Grafana and validates the stack.
func (m *UptimeKumaMonitoring) DeployAll(ctx context.Context) (string, error) {
	if _, err := m.DeployApp(ctx); err != nil { return "", err }
	if _, err := m.DeployMonitoring(ctx); err != nil { return "", err }
	if _, err := m.ConfigureGrafana(ctx); err != nil { return "", err }
	if err := m.networkCommand(ctx, "scripts/validate.sh"); err != nil {
		return "", fmt.Errorf("validation: %w", err)
	}
	return "Full stack deployed; validation passed.", nil
}

// Validate checks endpoints and Prometheus probes.
func (m *UptimeKumaMonitoring) Validate(ctx context.Context) (string, error) {
	if err := m.networkCommand(ctx, "scripts/validate.sh"); err != nil { return "", err }
	return "Validation passed.", nil
}

