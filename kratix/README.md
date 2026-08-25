# Kratix

This chart is for installing [Kratix](https://kratix.io/) on your Platform cluster.

## Installation

The Helm Chart can be installed without providing any values, this will install
the Kratix controllers and CRDs only.

```bash
export PLATFORM=kind-platform # or your platform cluster context

helm repo add syntasso https://syntasso.github.io/helm-charts
helm repo update
helm --kube-context ${PLATFORM} install kratix syntasso/kratix --wait
```

### Optional Configuration

Kratix will often be configured with one or more [Destinations](https://kratix.io/docs/main/reference/destinations/intro)
and [StateStores](https://kratix.io/docs/main/reference/statestore/intro). If you
know at installation time the values for these resources you can provide
them as values. Alternatively you can manually install later on. For example to
configure a worker destination and a [BucketStateStore](https://kratix.io/docs/main/reference/statestore/bucketstatestore)
at installation time you could provide the following `values.yaml` file:

```yaml
additionalResources:
- kind: BucketStateStore
  apiVersion: platform.kratix.io/v1alpha1
  metadata:
    name: default
  spec:
    endpoint: minio.kratix-platform-system.svc.cluster.local
    insecure: true
    bucketName: kratix
    authMethod: accessKey
    secretRef:
      name: minio-credentials
      namespace: default
- kind: Destination
  apiVersion: platform.kratix.io/v1alpha1
  metadata:
    name: worker-1
    labels:
      environment: dev
  spec:
    stateStoreRef:
      name: default
      kind: BucketStateStore
    path: path/in/statestore
- apiVersion: v1
  kind: Secret
  metadata:
    name: minio-credentials
    namespace: default
  type: Opaque
  data:
    accessKeyID: foo
    secretAccessKey: bar
```

See [the values file for more example configuration](./values.yaml). To pass the values file
in during the helm install run as follows:

```bash
export PLATFORM=kind-platform # or your platform cluster context
helm --kube-context ${PLATFORM} install kratix charts/kratix/ -f values.yaml
```
