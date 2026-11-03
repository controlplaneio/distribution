#!/usr/bin/env bash
#
# Resolve and write chart + image pins for one Flux CD addon in both
# registries. Called by .github/workflows/update-addons.yaml.
#
# Required env:
#   ADDON           - addon name (mcp)
#   IMAGE_REGISTRY  - ghcr.io/controlplaneio-fluxcd
#   CHART_REGISTRY  - ghcr.io/controlplaneio-fluxcd/charts
# Optional env:
#   ADDON_VERSION   - addon image version (e.g. v0.4.4). Empty = latest tag
#                     in the registry; "all" = backfill every version dir.
#   CHART_VERSION   - Helm chart version (e.g. 0.4.4). Empty = latest chart.
#                     "all" = backfill every chart version dir.
#
# Writes:
#   fluxcd/ghcr.io/addons/<addon>/{charts,images}/...
#   fluxcd/cpar.dev/addons/<addon>/{charts,images}/...

set -euo pipefail

ADDON="${ADDON:?ADDON is required}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:?IMAGE_REGISTRY is required}"
CHART_REGISTRY="${CHART_REGISTRY:?CHART_REGISTRY is required}"
ADDON_VERSION="${ADDON_VERSION:-}"
CHART_VERSION="${CHART_VERSION:-}"

ROOT_DIR="$(git rev-parse --show-toplevel)"
GHCR_ADDON_DIR="${ROOT_DIR}/fluxcd/ghcr.io/addons/${ADDON}"
CPAR_ADDON_DIR="${ROOT_DIR}/fluxcd/cpar.dev/addons/${ADDON}"
CPAR_REGISTRY="cpar.dev/fluxcd"
SCRIPT="${ROOT_DIR}/.github/workflows/update-addons.sh"

case "$ADDON" in
  mcp)
    CHART_NAME=flux-mcp-enterprise
    GHCR_IMAGE_REPOS=( "flux-mcp-enterprise" "flux-mcp-enterprise" )
    CPAR_IMAGE_REPOS=( "distroless-fips/flux-mcp-enterprise" "distroless-fips/flux-mcp-enterprise" )
    IMAGE_TAG_SUFFIXES=( "" "-stdio-readonly" )
    IMAGE_FILES=( "enterprise-http.yaml" "enterprise-stdio-readonly.yaml" )
    ;;
  *)
    echo "unsupported addon: $ADDON" >&2
    exit 1
    ;;
esac

# Backfill modes. "skip" is an internal sentinel that turns off one half.
if [ "$ADDON_VERSION" = "all" ] && [ "$CHART_VERSION" = "all" ]; then
  for dir in "${GHCR_ADDON_DIR}"/images/*/; do
    [ -d "$dir" ] || continue
    ADDON="$ADDON" IMAGE_REGISTRY="$IMAGE_REGISTRY" CHART_REGISTRY="$CHART_REGISTRY" \
      ADDON_VERSION="$(basename "$dir")" CHART_VERSION="skip" "$SCRIPT"
  done
  for dir in "${GHCR_ADDON_DIR}"/charts/*/; do
    [ -d "$dir" ] || continue
    ADDON="$ADDON" IMAGE_REGISTRY="$IMAGE_REGISTRY" CHART_REGISTRY="$CHART_REGISTRY" \
      ADDON_VERSION="skip" CHART_VERSION="$(basename "$dir")" "$SCRIPT"
  done
  exit 0
fi
if [ "$ADDON_VERSION" = "all" ]; then
  for dir in "${GHCR_ADDON_DIR}"/images/*/; do
    [ -d "$dir" ] || continue
    ADDON="$ADDON" IMAGE_REGISTRY="$IMAGE_REGISTRY" CHART_REGISTRY="$CHART_REGISTRY" \
      ADDON_VERSION="$(basename "$dir")" CHART_VERSION="skip" "$SCRIPT"
  done
  exit 0
fi
if [ "$CHART_VERSION" = "all" ]; then
  for dir in "${GHCR_ADDON_DIR}"/charts/*/; do
    [ -d "$dir" ] || continue
    ADDON="$ADDON" IMAGE_REGISTRY="$IMAGE_REGISTRY" CHART_REGISTRY="$CHART_REGISTRY" \
      ADDON_VERSION="skip" CHART_VERSION="$(basename "$dir")" "$SCRIPT"
  done
  exit 0
fi

CHART_REPO="${CHART_REGISTRY}/${CHART_NAME}"
CPAR_CHART_REPO="${CPAR_REGISTRY}/charts/${CHART_NAME}"

resolve_digest() {
  local ref="$1" digest
  digest="$(docker buildx imagetools inspect "$ref" --format '{{json .}}' | jq -r .manifest.digest)"
  if [ -z "$digest" ] || [ "$digest" = "null" ]; then
    echo "no digest for ${ref}" >&2
    return 1
  fi
  printf '%s\n' "$digest"
}

if [ "$ADDON_VERSION" != "skip" ] && [ -z "$ADDON_VERSION" ]; then
  ADDON_VERSION="$(skopeo list-tags "docker://${IMAGE_REGISTRY}/${GHCR_IMAGE_REPOS[0]}" \
    | jq -r '.Tags[]' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -n1)"
  [ -n "$ADDON_VERSION" ] || { echo "no semver tags found for ${GHCR_IMAGE_REPOS[0]}" >&2; exit 1; }
fi

# ---- chart pin -------------------------------------------------------------
if [ "$CHART_VERSION" != "skip" ]; then
  CHART_TMP="$(mktemp -d)"
  trap 'rm -rf "$CHART_TMP"' EXIT
  HELM_PULL_ARGS=( "oci://${CHART_REPO}" --destination "$CHART_TMP" )
  [ -n "${CHART_VERSION}" ] && HELM_PULL_ARGS+=( --version "$CHART_VERSION" )
  HELM_OUT="$(helm pull "${HELM_PULL_ARGS[@]}" 2>&1)"
  echo "$HELM_OUT"
  CHART_VERSION="$(echo "$HELM_OUT" | awk -F: '/^Pulled:/ {print $NF}')"
  [ -n "$CHART_VERSION" ] || { echo "could not resolve chart version" >&2; exit 1; }

  GHCR_CHART_DIGEST="$(resolve_digest "${CHART_REPO}:${CHART_VERSION}")"
  CPAR_CHART_DIGEST="$(resolve_digest "${CPAR_CHART_REPO}:${CHART_VERSION}")"

  mkdir -p "${GHCR_ADDON_DIR}/charts/${CHART_VERSION}" "${CPAR_ADDON_DIR}/charts/${CHART_VERSION}"
  cat >"${GHCR_ADDON_DIR}/charts/${CHART_VERSION}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: ${ADDON}
spec:
  url: oci://${CHART_REPO}
  ref:
    tag: ${CHART_VERSION}
    digest: ${GHCR_CHART_DIGEST}
EOF
  cat >"${CPAR_ADDON_DIR}/charts/${CHART_VERSION}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: ${ADDON}
spec:
  url: oci://${CPAR_CHART_REPO}
  ref:
    tag: ${CHART_VERSION}
    digest: ${CPAR_CHART_DIGEST}
EOF
fi

# ---- image pins ------------------------------------------------------------
if [ "$ADDON_VERSION" != "skip" ]; then
  GHCR_IMAGES_DIR="${GHCR_ADDON_DIR}/images/${ADDON_VERSION}"
  CPAR_IMAGES_DIR="${CPAR_ADDON_DIR}/images/${ADDON_VERSION}"
  mkdir -p "$GHCR_IMAGES_DIR" "$CPAR_IMAGES_DIR"

  for i in "${!GHCR_IMAGE_REPOS[@]}"; do
    image_tag="${ADDON_VERSION}${IMAGE_TAG_SUFFIXES[$i]}"
    ghcr_repo="${IMAGE_REGISTRY}/${GHCR_IMAGE_REPOS[$i]}"
    cpar_repo="${CPAR_REGISTRY}/${CPAR_IMAGE_REPOS[$i]}"

    ghcr_digest="$(resolve_digest "${ghcr_repo}:${image_tag}")"
    cpar_digest="$(resolve_digest "${cpar_repo}:${image_tag}")"

    cat >"${GHCR_IMAGES_DIR}/${IMAGE_FILES[$i]}" <<EOF
images:
  - name: ${ghcr_repo}
    newTag: ${image_tag}
    digest: ${ghcr_digest}
EOF
    cat >"${CPAR_IMAGES_DIR}/${IMAGE_FILES[$i]}" <<EOF
images:
  - name: ${cpar_repo}
    newTag: ${image_tag}
    digest: ${cpar_digest}
EOF
  done
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    [ "$ADDON_VERSION" != "skip" ] && echo "addon_version=${ADDON_VERSION}"
    [ "$CHART_VERSION" != "skip" ] && echo "chart_version=${CHART_VERSION}"
  } >>"$GITHUB_OUTPUT"
fi
