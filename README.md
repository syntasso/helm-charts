# Kratix Charts

This directory contains charts which you can use to install and operate
Kratix in either a single Kubernetes cluster, or across a multi-cluster setup.

To understand where to use each chart, you must understand a bit about the
way Kratix [schedules resources](https://docs.kratix.io/main/reference/destinations/multidestination-management)
across destinations.

## Usage

### Pre-requisites

* cert-manager must be installed

### Install

```bash
helm repo add syntasso https://syntasso.github.io/helm-charts
helm repo update
helm install kratix syntasso/kratix
```

Check the individual chart READMEs for more information.

## Charts

### `kratix` core installation

Whether you plan to schedule all work to a single cluster, or spread across
multiple, you will need to use the `kratix` chart.

For configuration options, see the [chart README](./kratix/README.md).

> **Note**
> The `kratix` chart installs the Kratix framework. If you are running a
> multi-cluster setup, this is typically installed on a `platform` or `admin`
> style cluster.

Using Kratix depends on access to a GitOps [state store](https://github.com/open-gitops/documents/blob/v0.1.0/PRINCIPLES.md#state-store).
It is suggested to register a Git repository or public cloud bucket, however
for a quick start, you can install and configure a local MinIO or other
cluster storage.

## SKE Operator

The SKE Operator chart deploys the Syntasso Kratix Enterprise Operator. This operator
is available only to Syntasso Kratix Enterprise users for the deployment and maintenance
of their Kratix deployments.

For configuration options, see the [chart README](./ske-operator/README.md).

## Common examples

* If you are running a single cluster setup, you will need to install both
charts on your cluster referring to the same state store configuration.

* If you are using any [compound promises](https://kratix.io/docs/main/guides/compound-promises),
you will also need to install both charts on the same cluster referring to
the same state store configuration.

* If you are running a multi-cluster setup, you will need to install the
`kratix` chart on your "platform" cluster and the `kratix-destination`
chart on all additional clusters, each with a unique state store
configuration.
