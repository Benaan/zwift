#!/usr/bin/env bash
# Builds localhost/zwift-patched:latest on top of docker.io/netbrain/zwift:latest, see docs/advanced/patched-wine.md.
#
#   WINE_BLE=1                Also build native bluetooth support (full Wine build, takes a while)
#   BASE_IMAGE=...            Image to patch (default: docker.io/netbrain/zwift:latest)
#   PATCHED_IMAGE=...         Name of the resulting image (default: localhost/zwift-patched:latest)
#   CONTAINER_TOOL=docker     Force docker or podman
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
readonly WINE_BLE="${WINE_BLE:-0}"
readonly BASE_IMAGE="${BASE_IMAGE:-docker.io/netbrain/zwift:latest}"
readonly PATCHED_IMAGE="${PATCHED_IMAGE:-localhost/zwift-patched:latest}"

if [[ -n ${CONTAINER_TOOL:-} ]]; then
    container_tool="${CONTAINER_TOOL}"
elif command -v podman > /dev/null 2>&1; then
    container_tool="podman"
else
    container_tool="docker"
fi
readonly container_tool

echo "[*] Pulling ${BASE_IMAGE}"
"${container_tool}" pull "${BASE_IMAGE}"

echo "[*] Building ${PATCHED_IMAGE} (WINE_BLE=${WINE_BLE})"
"${container_tool}" build \
    --file "${SCRIPT_DIR}/Dockerfile.patched-wine" \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    --build-arg "WINE_BLE=${WINE_BLE}" \
    --tag "${PATCHED_IMAGE}" \
    "${SCRIPT_DIR}"

echo
echo "[✓] ${PATCHED_IMAGE} is ready. Add this to ~/.config/zwift/config to use it:"
echo "    IMAGE=${PATCHED_IMAGE%:*}"
echo "    VERSION=${PATCHED_IMAGE##*:}"
echo "    DONT_UPDATE=1"
if [[ ${WINE_BLE} -eq 1 ]]; then
    echo "    DISABLE_BLUETOOTH=0"
fi
