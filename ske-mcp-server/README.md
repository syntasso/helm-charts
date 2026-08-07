# SKE MCP Server Helm chart

This chart deploys the [SKE MCP server](https://github.com/syntasso/ske-mcp-server),
which exposes Kratix platform capabilities to MCP clients over Streamable HTTP.

## Prerequisites

- Kubernetes with the Kratix `platform.kratix.io/v1alpha1` APIs installed
- Helm
- A bearer token stored in a Kubernetes Secret, or supplied during installation
- For external access, an ingress controller and an existing TLS certificate Secret

Kratix is an eventually consistent prerequisite. The chart installs without
performing live API checks, but the Pod remains unready until it can list the
Promises, Destinations, and Namespaces required by the server.

## Install with an existing Secret

Using an externally managed Secret is recommended for production and GitOps
workflows. The Secret must contain the bearer token under `token`, or under the
key configured with `auth.existingSecret.key`.

```sh
kubectl create namespace kratix-platform-system
kubectl create secret generic ske-mcp-server-auth \
  --namespace kratix-platform-system \
  --from-literal=token='<strong-random-token>'

helm upgrade --install ske-mcp-server syntasso/ske-mcp-server \
  --namespace kratix-platform-system \
  --set auth.existingSecret.name=ske-mcp-server-auth
```

The external Secret is not part of the Helm release. Restart the Deployment
after rotating its token, or configure an external secret reloader through
`podAnnotations`.

## Install with a chart-managed Secret

For a simple installation, the chart can create the Secret:

```sh
helm upgrade --install ske-mcp-server syntasso/ske-mcp-server \
  --namespace kratix-platform-system \
  --create-namespace \
  --set-string auth.token='<strong-random-token>'
```

Helm stores supplied values in the release Secret. Prefer `auth.existingSecret`
when the token must not be present in Helm release state. Exactly one of
`auth.token` and `auth.existingSecret.name` must be configured.

## External access

The Service is a `ClusterIP` by default. An optional Ingress exposes only the
`/mcp` endpoint and requires an existing TLS Secret:

```yaml
auth:
  existingSecret:
    name: ske-mcp-server-auth

ingress:
  enabled: true
  className: nginx
  host: mcp.example.com
  tls:
    secretName: mcp-example-com-tls
```

Connect an MCP client to `https://mcp.example.com/mcp` with both headers:

```text
Authorization: Bearer <token>
X-User-Identity: <user identity>
```

`X-User-Identity` is caller-asserted audit information, not verified identity.
OAuth authorization will be introduced in a future server and chart release.

## RBAC

The server discovers Promise request resource types at runtime. Its current
release therefore requires cluster-wide wildcard `list` and `create` access in
addition to explicit access to Promises, Destinations, Namespaces, and Events.
The chart creates these permissions when `rbac.create=true`.

Set both `rbac.create=false` and `serviceAccount.create=false` to supply a
pre-provisioned ServiceAccount and authorization:

```yaml
rbac:
  create: false
serviceAccount:
  create: false
  name: existing-ske-mcp-server
```

Restricting the supplied permissions without changing the server leaves some
advertised MCP tools unavailable at runtime.

## Availability

The current MCP transport stores sessions in process memory for 30 minutes.
The chart consequently enforces one replica and uses a `Recreate` update
strategy. Clients reconnect during upgrades. Horizontal scaling will require a
future stateless or shared-session server implementation.

## Configuration

| Value | Default | Description |
|---|---|---|
| `auth.token` | `""` | Token for a chart-managed Secret |
| `auth.existingSecret.name` | `""` | Existing bearer-token Secret |
| `auth.existingSecret.key` | `token` | Key in the existing Secret |
| `config.logLevel` | `info` | `debug`, `info`, `warn`, or `error` |
| `config.readinessMode` | `kubernetes` | Dependency-aware `kubernetes` or process-only `process` |
| `config.port` | `8080` | Server container port |
| `image.repository` | `ghcr.io/syntasso/ske-mcp-server` | Container image repository |
| `image.tag` | chart `appVersion` | Optional image tag override |
| `image.digest` | `""` | Optional digest; takes precedence over the tag |
| `rbac.create` | `true` | Create ClusterRole and ClusterRoleBinding |
| `service.type` | `ClusterIP` | Kubernetes Service type |
| `service.port` | `80` | Kubernetes Service port |
| `ingress.enabled` | `false` | Create the TLS-only `/mcp` Ingress |

See [values.yaml](values.yaml) for workload resources, probes, scheduling, and
security-context settings.

