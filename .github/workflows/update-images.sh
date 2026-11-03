#!/usr/bin/env bash
#
# Resolve and write image digest pins for one product version in both
# registries. Called by .github/workflows/update-images.yaml.
#
# Required env:
#   PRODUCT  - product directory: fluxcd or openbao
#   VERSION  - product version (e.g. v2.10.0), empty for the version in
#              <product>/ghcr.io/images/VERSION, or "all" to backfill every
#              version already present under <product>/ghcr.io/images/.
#
# Writes:
#   <product>/ghcr.io/images/<version>/<file>.yaml
#   <product>/cpar.dev/images/<version>/<file>.yaml

set -euo pipefail

PRODUCT="${PRODUCT:?PRODUCT is required}"
VERSION="${VERSION:-}"

ROOT_DIR="$(git rev-parse --show-toplevel)"
PRODUCT_DIR="${ROOT_DIR}/${PRODUCT}"
GHCR_IMAGES_DIR="${PRODUCT_DIR}/ghcr.io/images"
CPAR_IMAGES_DIR="${PRODUCT_DIR}/cpar.dev/images"
SCRIPT="${ROOT_DIR}/.github/workflows/update-images.sh"

case "$PRODUCT" in
  fluxcd)
    GHCR_BASE="ghcr.io/controlplaneio-fluxcd"
    CPAR_BASE="cpar.dev/fluxcd"
    VARIANTS=(alpine distroless distroless-fips)
    ;;
  openbao)
    GHCR_BASE="ghcr.io/controlplaneio"
    CPAR_BASE="cpar.dev/openbao"
    VARIANTS=(ubi ubi-fips distroless distroless-fips)
    ;;
  *)
    echo "unsupported product: $PRODUCT" >&2
    exit 1
    ;;
esac

if [ -z "$VERSION" ]; then
  VERSION="$(cat "${GHCR_IMAGES_DIR}/VERSION")"
fi

persist_version() {
  if [ -f "${GHCR_IMAGES_DIR}/VERSION" ]; then
    mkdir -p "${CPAR_IMAGES_DIR}"
    cp "${GHCR_IMAGES_DIR}/VERSION" "${CPAR_IMAGES_DIR}/VERSION"
  fi
}

if [ "$VERSION" = "all" ]; then
  found=0
  for dir in "${GHCR_IMAGES_DIR}"/v*/; do
    [ -d "$dir" ] || continue
    found=1
    PRODUCT="$PRODUCT" VERSION="$(basename "$dir")" "$SCRIPT"
  done
  if [ "$found" -eq 0 ]; then
    echo "no versions found under ${GHCR_IMAGES_DIR}" >&2
    exit 1
  fi
  persist_version
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

write_pins() {
  local out="$1"
  shift
  mkdir -p "$(dirname "$out")"
  {
    echo "images:"
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      local name="${ref%:*}" tag="${ref##*:}" digest
      digest="$(resolve_digest "$ref")"
      printf '  - name: %s\n    newTag: %s\n    digest: %s\n' "$name" "$tag" "$digest"
    done
  } >"$out"
  echo "wrote ${out}"
}

rewrite_cpar_ref() {
  local ref="$1"
  case "$PRODUCT" in
    fluxcd) printf '%s\n' "${ref/ghcr.io\/controlplaneio-fluxcd/$CPAR_BASE}" ;;
    openbao) printf '%s\n' "${ref/ghcr.io\/controlplaneio/$CPAR_BASE}" ;;
  esac
}

flux_refs() {
  local registry="$1" components minor
  components="image-reflector-controller,image-automation-controller"
  minor="$(echo "$VERSION" | cut -d'.' -f2)"
  if [ "$minor" -ge 7 ]; then
    components="${components},source-watcher"
  fi
  flux install --version "$VERSION" \
    --registry="$registry" \
    --components-extra="$components" \
    --export | grep 'ghcr.io/' | awk '{print $2}'
}

if [ "$PRODUCT" = "fluxcd" ]; then
  for variant in "${VARIANTS[@]}"; do
    refs="$(flux_refs "${GHCR_BASE}/${variant}")"
    write_pins "${GHCR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" <<<"$refs"

    cpar_refs="$(while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      rewrite_cpar_ref "$ref"
    done <<<"$refs")"
    write_pins "${CPAR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" <<<"$cpar_refs"
  done

  # Upstream Flux pins exist only in the legacy ghcr.io location; CPAR does
  # not mirror upstream images.
  refs="$(flux_refs "ghcr.io/fluxcd")"
  write_pins "${GHCR_IMAGES_DIR}/${VERSION}/upstream-alpine.yaml" <<<"$refs"
else
  for variant in "${VARIANTS[@]}"; do
    ghcr_ref="${GHCR_BASE}/${variant}/openbao:${VERSION}"
    cpar_ref="${CPAR_BASE}/${variant}/openbao:${VERSION}"
    write_pins "${GHCR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" <<<"$ghcr_ref"
    write_pins "${CPAR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" <<<"$cpar_ref"
  done
fi

persist_version
