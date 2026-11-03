# ControlPlane Enterprise Distribution

[![SLSA 3](https://slsa.dev/images/gh-badge-level3.svg)](https://slsa.dev)

This repository contains the OCI artifact digests for
ControlPlane's enterprise distributions, including
hardened images and Helm charts. The digests for each
distribution are stored in the corresponding directories
listed below.

> [!INFO]
> For access to the ControlPlane Artifact Registry,
> see [docs](https://docs.cpar.dev).

| Directory | Distribution | Version | Distroless scan | License scan |
|---|---|---|---|---|
| [`fluxcd/`](fluxcd/) | Enterprise for Flux CD | [![Version](https://img.shields.io/badge/version-v2.10.0-blue)](fluxcd/) | [![Distroless scan](https://github.com/controlplaneio/distribution/actions/workflows/scan-fluxcd-distroless.yaml/badge.svg)](https://github.com/controlplaneio/distribution/actions/workflows/scan-fluxcd-distroless.yaml) | [![License scan](https://github.com/controlplaneio/distribution/actions/workflows/scan-fluxcd-license.yaml/badge.svg)](https://github.com/controlplaneio/distribution/actions/workflows/scan-fluxcd-license.yaml) |
| [`openbao/`](openbao/) | Enterprise for OpenBao | [![Version](https://img.shields.io/badge/version-v2.7.2-blue)](openbao/) | [![Distroless scan](https://github.com/controlplaneio/distribution/actions/workflows/scan-openbao-distroless.yaml/badge.svg)](https://github.com/controlplaneio/distribution/actions/workflows/scan-openbao-distroless.yaml) | — |
| [`dex/`](dex/) | Enterprise for Dex | [![Version](https://img.shields.io/badge/version-v2.45.1-blue)](dex/) | [![Distroless scan](https://github.com/controlplaneio/distribution/actions/workflows/scan-dex.yaml/badge.svg)](https://github.com/controlplaneio/distribution/actions/workflows/scan-dex.yaml) | — |
