# ControlPlane Enterprise Distribution

[![SLSA 3](https://slsa.dev/images/gh-badge-level3.svg)](https://slsa.dev)
[![Sigstore](https://img.shields.io/badge/Sigstore-signed-2f855a)](https://docs.sigstore.dev/cosign/verifying/verify/)
[![SBOM](https://img.shields.io/badge/SBOM-SPDX-2f855a)](https://spdx.dev/)
[![Provenance](https://img.shields.io/badge/Provenance-attested-2f855a)](https://slsa.dev)
[![Hardened](https://img.shields.io/badge/Images-hardened-2f855a)](https://control-plane.io)
[![FIPS](https://img.shields.io/badge/FIPS-enabled-2f855a)](https://go.dev/doc/security/fips140)
[![Multi-arch](https://img.shields.io/badge/Platforms-amd64%20%7C%20arm64-2f855a)](https://docs.cpar.dev)

This repository contains the OCI artifact digests for
ControlPlane's enterprise distributions, including
hardened images and Helm charts. The digests for each
distribution are stored in the corresponding directories
listed below.

> [!TIP]
> For access to the ControlPlane Artifact Registry,
> see [docs](https://docs.cpar.dev).

| Directory | Distribution | Latest | Vulnerability | License |
|---|---|---|---|---|
| [`dex/`](dex/) | Enterprise for Dex | [![Version](https://img.shields.io/badge/version-v2.46.1-blue)](dex/) | [![Dex distroless](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-dex-distroless.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-dex-distroless.yaml) | [![Dex license](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-dex-license.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-dex-license.yaml) |
| [`fluxcd/`](fluxcd/) | Enterprise for Flux CD | [![Version](https://img.shields.io/badge/version-v2.10.0-blue)](fluxcd/) | [![Flux distroless](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-fluxcd-distroless.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-fluxcd-distroless.yaml) | [![Flux license](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-fluxcd-license.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-fluxcd-license.yaml) |
| [`openbao/`](openbao/) | Enterprise for OpenBao | [![Version](https://img.shields.io/badge/version-v2.7.2-blue)](openbao/) | [![OpenBao distroless](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-openbao-distroless.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-openbao-distroless.yaml) | [![OpenBao license](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-openbao-license.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-openbao-license.yaml) |
| [`spire/`](spire/) | Enterprise for SPIRE | [![Version](https://img.shields.io/badge/version-v1.15.5-blue)](spire/) | [![SPIRE distroless](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-spire-distroless.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-spire-distroless.yaml) | [![SPIRE license](https://img.shields.io/github/actions/workflow/status/controlplaneio/distribution/scan-spire-license.yaml?label=scan&branch=main)](https://github.com/controlplaneio/distribution/actions/workflows/scan-spire-license.yaml) |

The root [`LICENSE`](LICENSE) covers this repository's contents. The
referenced artifacts are licensed by their upstream projects and ControlPlane's
commercial terms.
