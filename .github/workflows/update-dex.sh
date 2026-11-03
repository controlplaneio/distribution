#!/usr/bin/env bash
#
# Resolve and write Dex image + chart pins for both registries.
# Called by .github/workflows/update-dex.yaml.
#
# Required env:
#   DEX_VERSION   - Dex image version (e.g. v2.45.1). "skip" updates charts only.
# Optional env:
#   CHART_VERSION - Helm chart version (e.g. 0.26.0).
#                   Empty = latest chart; "all" = every chart version already
#                   pinned under dex/ghcr.io/charts/; "skip" = no chart update.
#
# Writes:
#   dex/ghcr.io/{images,charts}/...
#   dex/cpar.dev/{images,charts}/...

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
GHCR_DIR="${ROOT_DIR}/dex/ghcr.io"
CPAR_DIR="${ROOT_DIR}/dex/cpar.dev"
DEX_VERSION="${DEX_VERSION:?DEX_VERSION is required (or skip)}"
CHART_VERSION="${CHART_VERSION:-}"

GHCR_IMAGE_REPO="ghcr.io/controlplaneio-fluxcd/distroless-fips/dex"
CPAR_IMAGE_REPO="cpar.dev/dex/distroless-fips/dex"
GHCR_CHART_REPO="ghcr.io/controlplaneio-fluxcd/charts/dex"
CPAR_CHART_REPO="cpar.dev/dex/charts/dex"

resolve_digest() {
  local ref="$1" digest
  digest="$(docker buildx imagetools inspect "$ref" --format '{{json .}}' | jq -r .manifest.digest)"
  if [ -z "$digest" ] || [ "$digest" = "null" ]; then
    echo "no digest for ${ref}" >&2
    return 1
  fi
  printf '%s\n' "$digest"
}

write_chart_pin() {
  local version="$1" tmp pulled ghcr_digest cpar_digest
  if [ -z "$version" ]; then
    tmp="$(mktemp -d)"
    pulled="$(helm pull "oci://${GHCR_CHART_REPO}" --destination "$tmp" 2>&1)"
    echo "$pulled"
    version="$(echo "$pulled" | awk -F: '/^Pulled:/ {print $NF}')"
    rm -rf "$tmp"
  fi
  [ -n "$version" ] || { echo "could not resolve Dex chart version" >&2; exit 1; }

  ghcr_digest="$(resolve_digest "${GHCR_CHART_REPO}:${version}")"
  cpar_digest="$(resolve_digest "${CPAR_CHART_REPO}:${version}")"

  mkdir -p "${GHCR_DIR}/charts/${version}" "${CPAR_DIR}/charts/${version}"
  cat >"${GHCR_DIR}/charts/${version}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: dex
spec:
  url: oci://${GHCR_CHART_REPO}
  ref:
    tag: ${version}
    digest: ${ghcr_digest}
EOF
  cat >"${CPAR_DIR}/charts/${version}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: dex
spec:
  url: oci://${CPAR_CHART_REPO}
  ref:
    tag: ${version}
    digest: ${cpar_digest}
EOF
}

if [ "$DEX_VERSION" != "skip" ]; then
  GHCR_IMAGE_DIR="${GHCR_DIR}/images/${DEX_VERSION}"
  CPAR_IMAGE_DIR="${CPAR_DIR}/images/${DEX_VERSION}"
  mkdir -p "$GHCR_IMAGE_DIR" "$CPAR_IMAGE_DIR"

  ghcr_digest="$(resolve_digest "${GHCR_IMAGE_REPO}:${DEX_VERSION}")"
  cpar_digest="$(resolve_digest "${CPAR_IMAGE_REPO}:${DEX_VERSION}")"

  cat >"${GHCR_IMAGE_DIR}/enterprise-distroless-fips.yaml" <<EOF
images:
  - name: ${GHCR_IMAGE_REPO}
    newTag: ${DEX_VERSION}
    digest: ${ghcr_digest}
EOF
  cat >"${CPAR_IMAGE_DIR}/enterprise-distroless-fips.yaml" <<EOF
images:
  - name: ${CPAR_IMAGE_REPO}
    newTag: ${DEX_VERSION}
    digest: ${cpar_digest}
EOF
fi

case "$CHART_VERSION" in
  skip) ;;
  all)
    for dir in "${GHCR_DIR}/charts"/*/; do
      [ -d "$dir" ] || continue
      write_chart_pin "$(basename "$dir")"
    done
    ;;
  *)
    write_chart_pin "$CHART_VERSION"
    ;;
esac

if [ -f "${GHCR_DIR}/images/VERSION" ]; then
  mkdir -p "${CPAR_DIR}/images"
  cp "${GHCR_DIR}/images/VERSION" "${CPAR_DIR}/images/VERSION"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    [ "$DEX_VERSION" != "skip" ] && echo "dex_version=${DEX_VERSION}"
    [ "$CHART_VERSION" != "skip" ] && echo "chart_version=${CHART_VERSION}"
  } >>"$GITHUB_OUTPUT"
fi
