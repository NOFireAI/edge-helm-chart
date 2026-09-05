# NOFire Edge Helm Chart

A Helm chart for deploying NOFire Edge - Kubernetes Resource Graph & Causal Analysis monitoring client.

## Quick Start

### Add Helm Repository

```bash
helm repo add nofire https://nofireai.github.io/edge-helm-chart
helm repo update
```

### Install

```bash
helm install nofire-edge nofire/nofire-edge \
  --set config.publisher.apiKey=YOUR_API_KEY \
  -n nofire-system --create-namespace
```

**Important:**
- Replace `YOUR_API_KEY` with your actual API key from the NOFire dashboard
- The graph URL defaults to `https://my.nofire.ai/api/edge`
- ServiceMonitor is disabled by default (enable with `--set monitoring.serviceMonitor.enabled=true` if using Prometheus Operator)

## Key Configuration Values

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `config.publisher.apiKey` | API key for authentication | `""` | **Yes** |
| `config.publisher.graph.url` | NOFire API endpoint | `https://my.nofire.ai/api/edge` | No |
| `service.clusterIP` | Static ClusterIP (recommended) | `""` | No |
| `monitoring.serviceMonitor.enabled` | Enable Prometheus ServiceMonitor | `false` | No |

## Edge Proxy (On-Prem Connections)

To proxy requests from Brain to on-prem/internal backends, enable `edgeProxy` and configure `onPremConnections`.

**Prerequisites:**

- Create the `nofire-credentials` secret (used for Brain authentication):

```bash
kubectl create secret generic nofire-credentials --from-literal=api-key=YOUR_KEY -n nofire-system
```

**Supported connection types include** `prometheus`, `loki`, `tempo`, `grafana`, `elasticsearch`, `open_search`, `mongodb_atlas`, `custom_http`, `postgres`, and others.

**Example:**

```yaml
edgeProxy:
  enabled: true
  stream:
    serverAddress: "brain-host:443"

onPremConnections:
  prod-postgres:
    type: postgres
    name: "Production Postgres"
    secretName: postgres-creds
    dbHost: "postgres.default.svc.cluster.local"
    dbPort: 5432
    dbName: "app"
    dbSSLMode: "require"

  internal-api:
    type: custom_http
    name: "Internal API"
    secretName: internal-api-creds
    url: "https://api.internal.example.com"
```

**Notes:**

- `secretName` is optional, but recommended. The secret is mounted under `edgeProxy.secretsPath` and used for credentials (token/username/password).
- For `postgres`, the chart renders DB fields (`dbHost`, `dbPort`, `dbName`, `dbSSLMode`) instead of `url`.

## Advanced Installation with Static IP

For production deployments, it's recommended to use a static ClusterIP:

```bash
# Initial install to get ClusterIP
helm install nofire-edge nofire/nofire-edge \
  --set config.publisher.apiKey=YOUR_API_KEY \
  -n nofire-system --create-namespace

# Get the assigned ClusterIP
kubectl get service nofire-edge -n nofire-system

# Reinstall with static IP
helm uninstall nofire-edge -n nofire-system
helm install nofire-edge nofire/nofire-edge \
  --set config.publisher.apiKey=YOUR_API_KEY \
  --set service.clusterIP=<CLUSTER_IP_FROM_ABOVE> \
  -n nofire-system --create-namespace
```

## Using a Values File

Create a `values.yaml` file:

```yaml
config:
  publisher:
    apiKey: "your-api-key-here"
    graph:
      url: "https://my.nofire.ai/api/edge"  # Optional, this is the default

service:
  clusterIP: "10.96.145.200"  # Optional: Use static IP

monitoring:
  serviceMonitor:
    enabled: false  # Set to true if Prometheus Operator is installed
```

Install with values file:

```bash
helm install nofire-edge nofire/nofire-edge -f values.yaml -n nofire-system --create-namespace
```

## Troubleshooting

### ServiceMonitor CRD Not Found (if enabled)

**Error:** `no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"`

**Solution:** ServiceMonitor requires Prometheus Operator. Either install Prometheus Operator or keep ServiceMonitor disabled (default).

### Configuration Issues

Check the pod logs for errors:
```bash
kubectl logs -l app=nofire-edge -n nofire-system
```

### Verify Installation

```bash
# Check pod status
kubectl get pods -n nofire-system

# Check service
kubectl get svc nofire-edge -n nofire-system

# View logs
kubectl logs -f deployment/nofire-edge -n nofire-system
```

## Full Documentation

Complete installation guide, DNSTap configuration, and advanced settings:
- [Quick Start Guide](https://docs.nofire.ai/edge/quick-start)
- [Installation Guide](https://docs.nofire.ai/edge/installation)
- [Configuration Reference](https://docs.nofire.ai/edge/configuration)

## Support

For issues and questions:
- Documentation: https://docs.nofire.ai
- Email: team@nofire.ai

## AI policy

AI-assisted development is welcome in edge-helm-chart. See [AI_POLICY.md](AI_POLICY.md).
