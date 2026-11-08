#!/usr/bin/env bash
#
# Resolve and write image/chart digest pins for one update target and version.
# Called by .github/workflows/update-pins.yaml.
#
# Required env:
#   TARGET  - fluxcd, openbao, dex, spire, or flux-mcp-enterprise
#   VERSION - target image version (e.g. v2.10.0 / v2.46.1 / v0.4.4)
# Optional env:
#   CHART_VERSION - chart version to update. "skip" updates images only.
#                   Empty resolves the latest chart. "all" updates every chart
#                   version already pinned (dex only).
#   SPIRE_CONTROLLER_MANAGER_VERSION - spire-controller-manager image tag.
#   SPIFFE_CSI_DRIVER_VERSION - spiffe-csi-driver image tag.
#   SPIRE_CRDS_CHART_VERSION - spire-crds chart version.
#   OPENBAO_K8S_VERSION - OpenBao injector image tag.
#   OPENBAO_CSI_PROVIDER_VERSION - OpenBao CSI provider image tag.
#   OPENBAO_SNAPSHOT_AGENT_VERSION - OpenBao snapshot agent image tag.
#   INCLUDE_OPENBAO_COMPONENTS - add auxiliary OpenBao images to the latest
#                                pinned OpenBao version only.
#
# The workflow matrix handles multi-version backfills, so this script always
# operates on exactly one image version.

set -euo pipefail

TARGET="${TARGET:?TARGET is required}"
VERSION="${VERSION:?VERSION is required}"
CHART_VERSION="${CHART_VERSION:-}"
SPIRE_CONTROLLER_MANAGER_VERSION="${SPIRE_CONTROLLER_MANAGER_VERSION:-}"
SPIFFE_CSI_DRIVER_VERSION="${SPIFFE_CSI_DRIVER_VERSION:-}"
SPIRE_CRDS_CHART_VERSION="${SPIRE_CRDS_CHART_VERSION:-}"
OPENBAO_K8S_VERSION="${OPENBAO_K8S_VERSION:-}"
OPENBAO_CSI_PROVIDER_VERSION="${OPENBAO_CSI_PROVIDER_VERSION:-}"
OPENBAO_SNAPSHOT_AGENT_VERSION="${OPENBAO_SNAPSHOT_AGENT_VERSION:-}"
INCLUDE_OPENBAO_COMPONENTS="${INCLUDE_OPENBAO_COMPONENTS:-false}"

ROOT_DIR="$(git rev-parse --show-toplevel)"

resolve_digest() {
  local ref="$1" digest attempt
  for attempt in 1 2 3 4 5; do
    if digest="$(docker buildx imagetools inspect "$ref" --format '{{json .}}' 2>/dev/null | jq -r .manifest.digest)"; then
      if [ -n "$digest" ] && [ "$digest" != "null" ]; then
        printf '%s\n' "$digest"
        return 0
      fi
    fi
    echo "digest lookup failed for ${ref} (attempt ${attempt}/5), retrying..." >&2
    sleep 3
  done
  echo "no digest for ${ref}" >&2
  return 1
}

write_pin_file() {
  local out="$1"
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

write_chart_pin() {
  local ghcr_repo="$1" cpar_repo="$2" chart_name="$3" \
    ghcr_dir="$4" cpar_dir="$5" version="$6" lookup_repo="${7:-$1}"
  local tmp pulled ghcr_digest cpar_digest

  if [ -z "$version" ]; then
    tmp="$(mktemp -d)"
    pulled="$(helm pull "oci://${lookup_repo}" --destination "$tmp" 2>&1)"
    echo "$pulled"
    version="$(echo "$pulled" | awk -F: '/^Pulled:/ {print $NF}')"
    rm -rf "$tmp"
  fi
  [ -n "$version" ] || { echo "could not resolve chart version for ${lookup_repo}" >&2; exit 1; }

  ghcr_digest="$(resolve_digest "${ghcr_repo}:${version}")"
  cpar_digest="$(resolve_digest "${cpar_repo}:${version}")"

  mkdir -p "${ghcr_dir}/${version}" "${cpar_dir}/${version}"
  cat >"${ghcr_dir}/${version}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: ${chart_name}
spec:
  url: oci://${ghcr_repo}
  ref:
    tag: ${version}
    digest: ${ghcr_digest}
EOF
  cat >"${cpar_dir}/${version}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: ${chart_name}
spec:
  url: oci://${cpar_repo}
  ref:
    tag: ${version}
    digest: ${cpar_digest}
EOF
  echo "wrote chart ${version} for ${ghcr_repo}"
}

write_cpar_chart_pin() {
  local cpar_repo="$1" chart_name="$2" cpar_dir="$3" version="${4:-}"
  local tmp pulled cpar_digest

  if [ -z "$version" ]; then
    tmp="$(mktemp -d)"
    pulled="$(helm pull "oci://${cpar_repo}" --destination "$tmp" 2>&1)"
    echo "$pulled"
    version="$(echo "$pulled" | awk -F: '/^Pulled:/ {print $NF}')"
    rm -rf "$tmp"
  fi
  [ -n "$version" ] || { echo "could not resolve chart version for ${cpar_repo}" >&2; exit 1; }

  cpar_digest="$(resolve_digest "${cpar_repo}:${version}")"
  mkdir -p "${cpar_dir}/${version}"
  cat >"${cpar_dir}/${version}/enterprise.yaml" <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: ${chart_name}
spec:
  url: oci://${cpar_repo}
  ref:
    tag: ${version}
    digest: ${cpar_digest}
EOF
  echo "wrote chart ${version} for ${cpar_repo}"
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

case "$TARGET" in
  fluxcd)
    GHCR_IMAGES_DIR="${ROOT_DIR}/fluxcd/ghcr.io (deprecated)/images"
    CPAR_IMAGES_DIR="${ROOT_DIR}/fluxcd/cpar.dev/images"
    GHCR_BASE="ghcr.io/controlplaneio-fluxcd"
    CPAR_BASE="cpar.dev/fluxcd"
    VARIANTS=(alpine distroless distroless-fips)

    # Older Flux releases predate distroless-fips. Backfill only the variants
    # already pinned for an existing version.
    variants_to_update=("${VARIANTS[@]}")
    if [ -d "${GHCR_IMAGES_DIR}/${VERSION}" ]; then
      existing=()
      for file in "${GHCR_IMAGES_DIR}/${VERSION}"/enterprise-*.yaml; do
        [ -f "$file" ] || continue
        v="$(basename "$file")"
        v="${v#enterprise-}"
        v="${v%.yaml}"
        existing+=("$v")
      done
      [ "${#existing[@]}" -gt 0 ] && variants_to_update=("${existing[@]}")
    fi

    for variant in "${variants_to_update[@]}"; do
      refs="$(flux_refs "${GHCR_BASE}/${variant}")"
      write_pin_file "${GHCR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" <<<"$refs"

      cpar_refs="$(while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        printf '%s\n' "${ref/ghcr.io\/controlplaneio-fluxcd/$CPAR_BASE}"
      done <<<"$refs")"
      write_pin_file "${CPAR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" <<<"$cpar_refs"
    done

    refs="$(flux_refs "ghcr.io/fluxcd")"
    write_pin_file "${GHCR_IMAGES_DIR}/${VERSION}/upstream-alpine.yaml" <<<"$refs"
    ;;

  openbao)
    GHCR_IMAGES_DIR="${ROOT_DIR}/openbao/ghcr.io (deprecated)/images"
    CPAR_IMAGES_DIR="${ROOT_DIR}/openbao/cpar.dev/images"
    GHCR_BASE="ghcr.io/controlplaneio"
    CPAR_BASE="cpar.dev/openbao"
    VARIANTS=(ubi ubi-fips distroless distroless-fips)

    variants_to_update=("${VARIANTS[@]}")
    if [ -d "${GHCR_IMAGES_DIR}/${VERSION}" ]; then
      existing=()
      for file in "${GHCR_IMAGES_DIR}/${VERSION}"/enterprise-*.yaml; do
        [ -f "$file" ] || continue
        v="$(basename "$file")"
        v="${v#enterprise-}"
        v="${v%.yaml}"
        existing+=("$v")
      done
      [ "${#existing[@]}" -gt 0 ] && variants_to_update=("${existing[@]}")
    fi

    if [ "$INCLUDE_OPENBAO_COMPONENTS" = "true" ]; then
      [ -n "$OPENBAO_K8S_VERSION" ] || { echo "OPENBAO_K8S_VERSION is required when pinning OpenBao components" >&2; exit 1; }
      [ -n "$OPENBAO_CSI_PROVIDER_VERSION" ] || { echo "OPENBAO_CSI_PROVIDER_VERSION is required when pinning OpenBao components" >&2; exit 1; }
      [ -n "$OPENBAO_SNAPSHOT_AGENT_VERSION" ] || { echo "OPENBAO_SNAPSHOT_AGENT_VERSION is required when pinning OpenBao components" >&2; exit 1; }
    fi

    for variant in "${variants_to_update[@]}"; do
      ghcr_refs=("${GHCR_BASE}/${variant}/openbao:${VERSION}")
      cpar_refs=("${CPAR_BASE}/${variant}/openbao:${VERSION}")
      if [ "$INCLUDE_OPENBAO_COMPONENTS" = "true" ]; then
        # These component images are published to CPAR; the deprecated GHCR
        # pin namespace only contains the main OpenBao image.
        cpar_refs+=(
          "${CPAR_BASE}/${variant}/openbao-k8s:${OPENBAO_K8S_VERSION}"
          "${CPAR_BASE}/${variant}/openbao-csi-provider:${OPENBAO_CSI_PROVIDER_VERSION}"
          "${CPAR_BASE}/${variant}/openbao-snapshot-agent:${OPENBAO_SNAPSHOT_AGENT_VERSION}"
        )
      fi
      write_pin_file "${GHCR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" \
        < <(printf '%s\n' "${ghcr_refs[@]}")
      write_pin_file "${CPAR_IMAGES_DIR}/${VERSION}/enterprise-${variant}.yaml" \
        < <(printf '%s\n' "${cpar_refs[@]}")
    done

    cpar_chart_repo="cpar.dev/openbao/charts/openbao"
    case "$CHART_VERSION" in
      skip) ;;
      ''|all)
        write_cpar_chart_pin "$cpar_chart_repo" openbao \
          "${ROOT_DIR}/openbao/cpar.dev/charts" ""
        ;;
      *)
        write_cpar_chart_pin "$cpar_chart_repo" openbao \
          "${ROOT_DIR}/openbao/cpar.dev/charts" "$CHART_VERSION"
        ;;
    esac
    ;;

  dex)
    GHCR_IMAGES_DIR="${ROOT_DIR}/dex/ghcr.io (deprecated)/images"
    CPAR_IMAGES_DIR="${ROOT_DIR}/dex/cpar.dev/images"
    ghcr_image_repo="ghcr.io/controlplaneio-fluxcd/distroless-fips/dex"
    cpar_image_repo="cpar.dev/dex/distroless-fips/dex"
    write_pin_file "${GHCR_IMAGES_DIR}/${VERSION}/enterprise-distroless-fips.yaml" \
      <<<"${ghcr_image_repo}:${VERSION}"
    write_pin_file "${CPAR_IMAGES_DIR}/${VERSION}/enterprise-distroless-fips.yaml" \
      <<<"${cpar_image_repo}:${VERSION}"

    ghcr_chart_repo="ghcr.io/controlplaneio-fluxcd/charts/dex"
    cpar_chart_repo="cpar.dev/dex/charts/dex"
    case "$CHART_VERSION" in
      skip) ;;
      all)
        for dir in "${ROOT_DIR}/dex/ghcr.io (deprecated)/charts"/*/; do
          [ -d "$dir" ] || continue
          write_chart_pin "$ghcr_chart_repo" "$cpar_chart_repo" dex \
            "${ROOT_DIR}/dex/ghcr.io (deprecated)/charts" "${ROOT_DIR}/dex/cpar.dev/charts" \
            "$(basename "$dir")" "$cpar_chart_repo"
        done
        ;;
      *)
        write_chart_pin "$ghcr_chart_repo" "$cpar_chart_repo" dex \
          "${ROOT_DIR}/dex/ghcr.io (deprecated)/charts" "${ROOT_DIR}/dex/cpar.dev/charts" \
          "$CHART_VERSION" "$cpar_chart_repo"
        ;;
    esac
    ;;

  spire)
    CPAR_IMAGES_DIR="${ROOT_DIR}/spire/cpar.dev/images"
    spire_tag="${VERSION#v}"
    cm_tag="${SPIRE_CONTROLLER_MANAGER_VERSION#v}"
    csi_tag="${SPIFFE_CSI_DRIVER_VERSION#v}"
    [ -n "$cm_tag" ] || { echo "SPIRE_CONTROLLER_MANAGER_VERSION is required for spire" >&2; exit 1; }
    [ -n "$csi_tag" ] || { echo "SPIFFE_CSI_DRIVER_VERSION is required for spire" >&2; exit 1; }

    refs="$(cat <<EOF
cpar.dev/spire/distroless-fips/spire-server:${spire_tag}
cpar.dev/spire/distroless-fips/spire-agent:${spire_tag}
cpar.dev/spire/distroless-fips/oidc-discovery-provider:${spire_tag}
cpar.dev/spire/distroless-fips/spire-controller-manager:${cm_tag}
cpar.dev/spiffe/distroless-fips/spiffe-csi-driver:${csi_tag}
EOF
)"
    write_pin_file "${CPAR_IMAGES_DIR}/${VERSION}/enterprise-distroless-fips.yaml" <<<"$refs"

    if [ "$CHART_VERSION" != "skip" ]; then
      spire_chart_version="$CHART_VERSION"
      [ "$spire_chart_version" = "all" ] && spire_chart_version=""
      crds_chart_version="$SPIRE_CRDS_CHART_VERSION"
      [ "$crds_chart_version" = "all" ] && crds_chart_version=""
      write_cpar_chart_pin \
        "cpar.dev/spire/charts/spire" \
        spire \
        "${ROOT_DIR}/spire/cpar.dev/charts/spire" \
        "$spire_chart_version"
      write_cpar_chart_pin \
        "cpar.dev/spire/charts/spire-crds" \
        spire-crds \
        "${ROOT_DIR}/spire/cpar.dev/charts/spire-crds" \
        "$crds_chart_version"
    fi
    ;;

  flux-mcp-enterprise)
    GHCR_ADDON_DIR="${ROOT_DIR}/fluxcd/ghcr.io (deprecated)/addons/flux-mcp-enterprise"
    CPAR_ADDON_DIR="${ROOT_DIR}/fluxcd/cpar.dev/addons/flux-mcp-enterprise"
    ghcr_image_repo="ghcr.io/controlplaneio-fluxcd/flux-mcp-enterprise"
    cpar_image_repo="cpar.dev/fluxcd/distroless-fips/flux-mcp-enterprise"

    mkdir -p "${GHCR_ADDON_DIR}/images/${VERSION}" "${CPAR_ADDON_DIR}/images/${VERSION}"
    for pair in "enterprise-http.yaml:" "enterprise-stdio-readonly.yaml:-stdio-readonly"; do
      file="${pair%%:*}"
      suffix="${pair#*:}"
      tag="${VERSION}${suffix}"
      write_pin_file "${GHCR_ADDON_DIR}/images/${VERSION}/${file}" <<<"${ghcr_image_repo}:${tag}"
      write_pin_file "${CPAR_ADDON_DIR}/images/${VERSION}/${file}" <<<"${cpar_image_repo}:${tag}"
    done

    ghcr_chart_repo="ghcr.io/controlplaneio-fluxcd/charts/flux-mcp-enterprise"
    cpar_chart_repo="cpar.dev/fluxcd/charts/flux-mcp-enterprise"
    if [ "$CHART_VERSION" != "skip" ]; then
      write_chart_pin "$ghcr_chart_repo" "$cpar_chart_repo" flux-mcp-enterprise \
        "${GHCR_ADDON_DIR}/charts" "${CPAR_ADDON_DIR}/charts" \
        "$CHART_VERSION" "$cpar_chart_repo"
    fi
    ;;

  *)
    echo "unsupported target: $TARGET" >&2
    exit 1
    ;;
esac
