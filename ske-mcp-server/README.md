# SKE MCP Server Helm chart

This chart deploys the [SKE MCP server](https://github.com/syntasso/ske-mcp-server),
which exposes Kratix platform capabilities to MCP clients over Streamable HTTP.

## Prerequisites

- Kubernetes with the Kratix `platform.kratix.io/v1alpha1` APIs installed
- Helm
- An OIDC issuer to validate tokens against, or a bearer token in a Kubernetes Secret
- For external access, an ingress controller, and a TLS certificate Secret unless
  TLS terminates upstream of the cluster

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
when the token must not be present in Helm release state. Set at most one of
`auth.token` and `auth.existingSecret.name`.

A static token identifies nobody: every caller is the same principal, so no call
can be attributed and revoking one caller revokes all of them. Prefer OIDC
wherever there is an issuer to point at.

## OIDC authorization

The server is an OAuth 2.1 resource server. It validates tokens against the
issuer's JWKS, requires its own canonical URI in each token's `aud`, and gates
every tool on scopes:

```yaml
auth:
  oidc:
    issuer: https://keycloak.example.com/realms/platform
    resourceURL: https://mcp.example.com/mcp
    # `sub` is opaque on most issuers and changes if the identity is recreated.
    subjectClaim: preferred_username
```

`issuer` and `resourceURL` are set together, and `resourceURL` must be the
audience the issuer puts in tokens — normally the public MCP endpoint, so it
agrees with `ingress.host` and the `/mcp` path. An issuer that omits it mints
tokens this server rejects while looking entirely correct.

The realm also needs the four tool scopes — `promises:read`, `requests:read`,
`requests:write`, `destinations:read` — and an audience mapper. See the server's
own `docs/keycloak-setup.md`.

OIDC and a static token may both be configured, so an installation can carry a
legacy token while callers migrate. **Configuring neither is refused**: the
server then serves `/mcp` with no authentication, and a chart that renders that
quietly is how it reaches a cluster.

## External access

The Service is a `ClusterIP` by default. An optional Ingress exposes the `/mcp`
endpoint, plus the two RFC 9728 protected-resource metadata paths when OIDC is
configured — an MCP client fetches those to discover the authorization server,
and routing only `/mcp` leaves them 404 through the Ingress:

```yaml
ingress:
  enabled: true
  className: nginx
  host: mcp.example.com
  tls:
    secretName: mcp-example-com-tls
```

`tls.secretName` is optional. Where TLS terminates upstream of the cluster — a
load balancer holding its own certificate — omit it and the `tls` block is left
out rather than naming a Secret that cannot exist.

Connect an MCP client to `https://mcp.example.com/mcp`.

## RBAC

The server needs explicit access to Promises, Destinations, Namespaces and
Events, which the chart always grants. Promise **request** resource types are
defined by Promises at runtime and so cannot be enumerated here; list the API
groups holding them:

```yaml
rbac:
  requestApiGroups:
    - example.kratix.io
```

Find them with
`kubectl get promises -o jsonpath='{.items[*].spec.api.spec.group}'`.

**This is an allowlist and not a wildcard, deliberately.** `apiGroups: ["*"]`
also matches the core group, where `list` on secrets returns their values — so a
wildcard makes this ServiceAccount a cluster-wide credential reader, and RBAC
cannot express an exception to walk that back. The chart rejects `"*"` as an
entry.

Leaving `requestApiGroups` empty is safe and still useful: the catalogue,
destinations and request status stay readable, and only submitting a request
fails.

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
| `auth.oidc.issuer` | `""` | Authorization server; set with `resourceURL` |
| `auth.oidc.resourceURL` | `""` | This server's canonical URI and required token audience |
| `auth.oidc.jwksURI` | `""` | Only for an issuer publishing no discovery document |
| `auth.oidc.subjectClaim` | `""` (`sub`) | Claim the audit subject is read from |
| `auth.oidc.groupsClaim` | `""` (`groups`) | Claim groups are read from |
| `auth.oidc.nameClaims` | `[]` | Ordered claims tried for the display name |
| `auth.oidc.allowedAlgorithms` | `[]` | JWS algorithm allowlist |
| `auth.oidc.clockSkew` | `""` (`60s`) | Tolerance for `exp` and `nbf` |
| `config.logLevel` | `info` | `debug`, `info`, `warn`, or `error` |
| `config.readinessMode` | `kubernetes` | Dependency-aware `kubernetes` or process-only `process` |
| `config.port` | `8080` | Server container port |
| `image.repository` | `ghcr.io/syntasso/ske-mcp-server` | Container image repository |
| `image.tag` | chart `appVersion` | Optional image tag override |
| `image.digest` | `""` | Optional digest; takes precedence over the tag |
| `rbac.create` | `true` | Create ClusterRole and ClusterRoleBinding |
| `rbac.requestApiGroups` | `[]` | API groups holding Promise request resources. `"*"` is rejected |
| `service.type` | `ClusterIP` | Kubernetes Service type |
| `service.port` | `80` | Kubernetes Service port |
| `ingress.enabled` | `false` | Create the `/mcp` Ingress |
| `ingress.tls.secretName` | `""` | Optional; omit where TLS terminates upstream |

See [values.yaml](values.yaml) for workload resources, probes, scheduling, and
security-context settings.

