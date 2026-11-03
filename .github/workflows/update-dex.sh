#!/usr/bin/env bash
#
# Resolve and write Dex image + chart pins for both registries.
# Called by .github/workflows/update-dex.yaml.
#
# Optional env:
#   DEX_VERSION   - Dex image version (e.g. v2.45.1). Empty = the version
#                   in dex/ghcr.io/images/VERSION or the latest pinned dir.
#                   "all" = backfill every image version dir.
#   CHART_VERSION - Helm chart version (e.g. 0.26.0). Empty = latest chart.
#                   "all" = backfill every chart version dir.
#
# Writes:
#   dex/ghcr.io/{images,charts}/...
#   dex/cpar.dev/{images,charts}/...

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
GHCR_DIR="${ROOT_DIR}/dex/ghcr.io"
CPAR_DIR="${ROOT_DIR}/dex/cpar.dev"
DEX_VERSION="${DEX_VERSION:-}"
CHART_VERSION="${CHART_VERSION:-}"
SCRIPT="${ROOT_DIR}/.github/workflows/update-dex.sh"

GHCR_IMAGE_REPO="ghcr.io/controlplaneio-fluxcd/distroless-fips/dex"
CPAR_IMAGE_REPO="cpar.dev/dex/distroless-fips/dex"
GHCR_CHART_REPO="ghcr.io/controlplaneio-fluxcd/charts/dex"
CPAR_CHART_REPO="cpar.dev/dex/charts/dex"

if [ "$DEX_VERSION" = "all" ] && [ "$CHART_VERSION" = "all" ]; then
  for dir in "${GHCR_DIR}"/images/*/; do
    [ -d "$dir" ] || continue
    DEX_VERSION="$(basename "$dir")" CHART_VERSION="skip" "$SCRIPT"
  done
  for dir in "${GHCR_DIR}"/charts/*/; do
    [ -d "$dir" ] || continue
    DEX_VERSION="skip" CHART_VERSION="$(basename "$dir")" "$SCRIPT"
  done
  exit 0
fi
if [ "$DEX_VERSION" = "all" ]; then
  for dir in "${GHCR_DIR}"/images/*/; do
    [ -d "$dir" ] || continue
    DEX_VERSION="$(basename "$dir")" CHART_VERSION="skip" "$SCRIPT"
  done
  exit 0
fi
if [ "$CHART_VERSION" = "all" ]; then
  for dir in "${GHCR_DIR}"/charts/*/; do
    [ -d "$dir" ] || continue
    DEX_VERSION="skip" CHART_VERSION="$(basename "$dir")" "$SCRIPT"
  done
  exit 0
fi

resolve_digest() {
  local ref="$1" digest
  digest="$(docker buildx imagetools inspect "$ref" --format '{{json .}}' | jq -r .manifest.digest)"
  if [ -z "$digest" ] || [ "$digest" = "null" ]; then
    echo "no digest for ${ref}" >&2
    return 1
  fi
  printf '%s\n' "$digest"
}

if [ "$DEX_VERSION" != "skip" ] && [ -z "$DEX_VERSION" ]; then
  if [ -f "${GHCR_DIR}/images/VERSION" ]; then
    DEX_VERSION="$(cat "${GHCR_DIR}/images/VERSION")"
  else
    DEX_VERSION="$(ls "${GHCR_DIR}/images" | grep -E '^v[0-9]' | sort -V | tail -n1)"
  fi
  [ -n "$DEX_VERSION" ] || { echo "could not resolve Dex version" >&2; exit 1; }
fi

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

if [ "$CHART_VERSION" != "skip" ]; then
  CHART_TMP="$(mktemp -d)"
  trap 'rm -rf "$CHART_TMP"' EXIT
  HELM_PULL_ARGS=( "oci://${GHCR_CHART_REPO}" --destination "$CHART_TMP" )
  [ -n "${CHART_VERSION}" ] && HELM_PULL_ARGS+=( --version "$CHART_VERSION" )
  HELM_OUT="$(helm pull "${HELM_PULL_ARGS[@]}" 2>&1)"
  echo "$HELM_OUT"
  CHART_VERSION="$(echo "$HELM_OUT" | awk -F: '/^Pulled:/ {print $NF}')"
  [ -n "$CHART_VERSION" ] || { echo "could not resolve Dex chart version" >&2; exit 1; }

  ghcr_chart_digest="$(resolve_digest "${GHCR_CHART_REPO}:${CHART_VERSION}")"
  cpar_chart_digest="$(resolve_digest "${CPAR_CHART_REPO}:${CHART_VERSION}")"

  mkdir -p "${GHCR_DIR}/charts/${CHART_VERSION}" "${CPAR_DIR}/charts/${CHART_VERSION}"
  cat >"${GHCR_DIR}/charts/${CHART_VERSION}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: dex
spec:
  url: oci://${GHCR_CHART_REPO}
  ref:
    tag: ${CHART_VERSION}
    digest: ${ghcr_chart_digest}
EOF
  cat >"${CPAR_DIR}/charts/${CHART_VERSION}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: dex
spec:
  url: oci://${CPAR_CHART_REPO}
  ref:
    tag: ${CHART_VERSION}
    digest: ${cpar_chart_digest}
EOF
fi

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
