# ControlPlane Enterprise Distributions

This repository consolidates the ControlPlane enterprise distributions and the
artifact pins that describe what we ship to customers.

Each distribution lives in its own top-level directory:

| Distribution | Description |
|---|---|
| [`fluxcd/`](fluxcd/) | ControlPlane Enterprise for Flux CD |
| [`openbao/`](openbao/) | ControlPlane Enterprise for OpenBao |
| [`dex/`](dex/) | ControlPlane Enterprise for Dex |

## Registry layout

Products that publish through both registries keep their pins under a registry
directory:

```text
<product>/
  ghcr.io/   # deprecated legacy registry
  cpar.dev/  # ControlPlane Artifact Registry (main distribution channel)
```

See [`cpar.dev`](https://docs.cpar.dev) for the ControlPlane Artifact Registry
documentation. Customers still pulling from `ghcr.io` should contact us to
migrate to `cpar.dev`.

## Updating pins

The `Update images`, `Update addons`, and `Update Dex` workflows refresh pins in
both registries in a single pull request. Set the version input to `all` to
backfill every version already pinned under `ghcr.io` into `cpar.dev`.
