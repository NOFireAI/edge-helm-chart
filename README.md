# Nofire Client Helm Chart

A Helm chart for deploying the Nofire Client - Kubernetes Resource Graph & Causal Analysis monitoring client.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Basic Installation](#basic-installation)
  - [Custom Configuration](#custom-configuration)
  - [Upgrade](#upgrade)
  - [Uninstall](#uninstall)
- [Configuration](#configuration)
  - [Complete Configuration Reference](#complete-configuration-reference)
  - [Environment Variable Support](#environment-variable-support)
- [API Endpoints](#api-endpoints) 
- [Chart Structure](#chart-structure)
- [Contributing](#contributing)

## Prerequisites

Before installing the Nofire Client Helm chart, ensure you have the following prerequisites:

### Required Components

- **Kubernetes Cluster**: Version 1.19 or higher
- **Helm**: Version 3.0 or higher
- **kubectl**: Configured to access your Kubernetes cluster
- **Container Registry Access**: Ability to pull the Nofire Client container image
- **NOFire API Key**: Create an API key in the NOFire user interface for client authentication

### Optional Components

- **Prometheus Operator**: For metrics collection and monitoring
- **Datadog Account**: For service dependency analysis (if using Datadog integration)
- **NOFire API Access**: For data publishing and heartbeat functionality

### Service Dependency Analysis

The client can operate in two modes:

- **With Provider (Datadog)**: Identifies services AND their dependencies through observability data
- **Without Provider**: Identifies services but NOT their dependencies (provider set to null)

The Datadog provider is **not required** for basic operation. If `config.services.provider` is set to `null`, the client will still identify services based on Kubernetes labels but will not determine service dependencies.

### System Requirements

- **CPU**: Minimum 100m CPU request (200m limit recommended)
- **Memory**: Minimum 128Mi memory request (256Mi limit recommended)
- **Storage**: No persistent storage required
- **Network**: Outbound internet access for API calls and metrics publishing

### RBAC Requirements

The client requires the following Kubernetes permissions:
- **Read access** to pods, nodes, services, configmaps, secrets, and other monitored resources
- **List and watch** permissions for resource discovery
- **Service account** with appropriate cluster role bindings

### Network Requirements

- **Outbound HTTPS**: For API communication with NOFire services
- **Outbound HTTPS**: For Datadog API calls (if using Datadog integration)
- **Inbound HTTP**: For health checks and metrics endpoints (port 8080)

## Quick Start

### Basic Installation
```bash
# Install with default values
helm install nofire-client ./chart

# Install in specific namespace
helm install nofire-client ./chart -n monitoring --create-namespace
```

### Custom Configuration
```bash
# Create custom values
cat > custom-values.yaml << EOF
config:
  publisher:
    apiKey: "your-api-key"
    graph:
      url: "https://api.example.com/graph"
EOF

helm install nofire-client ./chart -f custom-values.yaml
```

### Upgrade
```bash
helm upgrade nofire-client ./chart -f custom-values.yaml
```

### Uninstall
```bash
helm uninstall nofire-client
```

## Configuration

The complete configuration reference is provided in the table below.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| **Chart Parameters** |
| `image.repository` | string | `"localhost:50001/nofire-client"` | Container image repository. Change it only if you have pulled the image to your own Docker repository |
| `image.tag` | string | `"latest"` | Container image tag |
| `replicaCount` | integer | `1` | Number of replicas |
| **Basic Configuration** |
| `config.logLevel` | string | `"info"` | Logging level (debug, info, warn, error) |
| `config.serverPort` | integer | `8080` | Server port for HTTP API |
| `config.maxWorkers` | integer | `4` | Maximum number of worker goroutines |
| `config.processInterval` | string | `"100ms"` | Interval between processing cycles |
| **Graph Configuration** |
| `config.graph.pruneInterval` | string | `"1h"` | How often to prune old graph data |
| `config.graph.maxPruneAge` | string | `"24h"` | Maximum age of graph data to keep |
| **Kubernetes Configuration** |
| `config.kube.configPath` | string | `""` | Path to kubeconfig file (empty for in-cluster) |
| `config.kube.resyncInterval` | string | `"5m"` | How often to resync with Kubernetes API |
| `config.kube.clusterName` | string | `"default-cluster"` | Name of the cluster |
| `config.kube.resources` | array | `["pods", "nodes", "services", "configmaps", "secrets", "persistentvolumeclaims", "persistentvolumes", "deployments", "replicasets", "statefulsets", "daemonsets", "jobs", "ingresses", "namespaces"]` | List of Kubernetes resources to monitor |
| **Causal Analysis Configuration** |
| `config.enableCausalAnalysis` | boolean | `false` | Enable causal analysis |
| `config.causal.algorithm` | string | `"granger"` | Causal analysis algorithm (granger, counterfactual, pc) |
| `config.causal.interval` | string | `"15m"` | How often to run causal analysis |
| **Services Configuration** |
| `config.services.nameLabels` | array | `["opentelemetry.io/service.name", "app.kubernetes.io/name", "service", "serviceName", "app"]` | Labels to check for service name identification |
| `config.services.versionLabels` | array | `["opentelemetry.io/service.version", "app.kubernetes.io/version", "version"]` | Labels to check for service version identification |
| `config.services.provider` | object | `null` | **Optional** observability solution for service dependency determination. Set to `null` to disable dependency analysis. Currently supports Datadog, with additional observability solutions planned for future releases |
| `config.services.provider.datadog.apiKey` | string | `""` | Datadog API key |
| `config.services.provider.datadog.appKey` | string | `""` | Datadog application key |
| `config.services.provider.datadog.url` | string | `""` | Datadog API URL |
| `config.services.provider.datadog.interval` | string | `""` | Datadog sync interval |
| `config.services.provider.datadog.timeout` | string | `""` | Datadog request timeout |
| `config.services.provider.datadog.env` | string | `""` | Datadog environment |
| **Publisher Configuration** |
| `config.enablePublishing` | boolean | `false` | Enable data publishing |
| `config.publisher.apiKey` | string | `""` | API key for publishing (REQUIRED) |
| `config.publisher.timeout` | string | `"5m"` | Request timeout |
| `config.publisher.maxRetries` | integer | `3` | Maximum retry attempts |
| `config.publisher.retryDelay` | string | `"1m"` | Delay between retries |
| `config.publisher.enableCompression` | boolean | `false` | Enable request compression |
| `config.publisher.graph.url` | string | `""` | Graph publishing URL (REQUIRED) |
| `config.publisher.graph.interval` | string | `"1h"` | Graph publishing interval |
| `config.publisher.heartbeat.url` | string | `""` | Heartbeat publishing URL (REQUIRED) |
| `config.publisher.heartbeat.interval` | string | `"1h"` | Heartbeat publishing interval |

### Environment Variable Support

The client supports environment variable substitution **only when configuring the Datadog provider** using the format `{ENV_VAR_NAME}`. This feature enables secure configuration management by allowing sensitive Datadog credentials to be stored as environment variables rather than hardcoded in configuration files.

#### Usage Pattern

**Datadog Provider Configuration**: Replace Datadog credentials with environment variables
```yaml
config:
  services:
    provider:
      datadog:
        apiKey: "{DATADOG_API_KEY}"      # Will be replaced with $DATADOG_API_KEY
        appKey: "{DATADOG_APP_KEY}"      # Will be replaced with $DATADOG_APP_KEY
        url: "{DATADOG_URL}"             # Will be replaced with $DATADOG_URL
        env: "{ENVIRONMENT}"              # Will be replaced with $ENVIRONMENT
```

#### Environment Variable Requirements

- Environment variables must be set before the client starts
- Empty or unset variables will cause configuration errors
- Variable names are case-sensitive
- Use descriptive names that clearly indicate their purpose
- **Note**: Environment variable substitution only works for Datadog provider configuration

Configure which Kubernetes resources to monitor:

```yaml
config:
  kube:
    resources:
      - "pods"
      - "services" 
      - "deployments"
      - "configmaps"
      - "secrets"
      # Add more as needed
```


### Development Setup
```bash
helm install nofire-client ./ -f examples/production-values.yaml
`
kubectl port-forward svc/nofire-client 8080:8080
curl http://localhost:8080/graph
```


## Chart Structure

```
./
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default values
├── manifests.yaml          # Raw Kubernetes manifests
├── datadog.yaml            # Datadog integration values
├── otel-datadog-values.yaml # OpenTelemetry + Datadog values
├── README.md              # This file
├── examples/              # Example configurations
│   └── production-values.yaml
└── templates/             # Helm templates
    ├── _helpers.tpl       # Template helpers
    ├── configmap.yaml     # Configuration
    ├── deployment.yaml    # Main deployment
    ├── ingress.yaml       # Ingress configuration
    ├── rbac.yaml          # RBAC resources
    ├── service.yaml       # Service definition
    ├── serviceaccount.yaml # Service account
    └── servicemonitor.yaml # Prometheus monitoring
```
