#!/usr/bin/env bash
# Builds Wine with the patches in /usr/src/wine-patches and installs the result to /wine-install.
# Runs inside the wine-build stage of Dockerfile.patched-wine.
#
# The Wine source tag is taken from /tmp/wine-version, the output of "wine --version" in the base
# image, so the patched modules always match the Wine build they are installed over.
#
#   WINE_BLE=0  Only build the patched video capture modules (a few minutes) and install them over
#               the WineHQ build of the base image.
#   WINE_BLE=1  Also apply the Bluetooth LE patches and build all of Wine (much longer), installed
#               in place of the WineHQ build.
set -euo pipefail

readonly WINE_BLE="${WINE_BLE:-0}"
readonly WINE_GIT_URL="${WINE_GIT_URL:-https://gitlab.winehq.org/wine/wine.git}"
readonly WINE_INSTALL_PREFIX="/opt/wine-devel"
readonly PATCH_DIR="/usr/src/wine-patches"
readonly SOURCE_DIR="/usr/src/wine"
readonly BUILD_DIR="/usr/src/wine-build"
readonly DESTDIR="/wine-install"

wine_tag="$(tr -d '[:space:]' < /tmp/wine-version)"
if [[ ! ${wine_tag} =~ ^wine-[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Unexpected wine version in base image: '${wine_tag}'" >&2
    exit 1
fi
readonly wine_tag

echo "Fetching ${wine_tag} from ${WINE_GIT_URL}"
git clone --quiet --depth 1 --branch "${wine_tag}" "${WINE_GIT_URL}" "${SOURCE_DIR}"

patch_sets=(video)
if [[ ${WINE_BLE} -eq 1 ]]; then
    patch_sets+=(ble)
fi

cd "${SOURCE_DIR}"
for patch_set in "${patch_sets[@]}"; do
    for patch_file in "${PATCH_DIR}/${patch_set}"/*.patch; do
        echo "Applying ${patch_set}/$(basename "${patch_file}")"
        git apply --whitespace=nowarn "${patch_file}"
    done
done

# Note: the Bluetooth LE patch also adds dlls/winebth.sys/tests to configure.ac. Tests are not built
# here, so configure does not need to be regenerated.

jobs="$(nproc)"
readonly jobs

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [[ ${WINE_BLE} -eq 1 ]]; then
    # Full WoW64 build, laid out like the WineHQ package so it simply replaces it.
    "${SOURCE_DIR}/configure" --prefix="${WINE_INSTALL_PREFIX}" --enable-archs=i386,x86_64 --disable-tests
    make -j"${jobs}"
    make install DESTDIR="${DESTDIR}"
else
    # Only the modules touched by the video patches. They are PE modules, so most features can be left out.
    "${SOURCE_DIR}/configure" --prefix="${WINE_INSTALL_PREFIX}" --enable-archs=x86_64 --disable-tests \
        --without-x --without-freetype --without-wayland --without-vulkan --without-opengl \
        --without-alsa --without-pulse --without-dbus --without-cups --without-sane --without-krb5 \
        --without-gphoto --without-usb --without-pcap --without-netapi --without-oss --without-v4l2 \
        --without-xcomposite --without-sdl --without-capi --without-udev --without-unwind \
        --without-gssapi --with-gstreamer
    modules=(mfplat mfreadwrite msvproc winegstreamer)
    targets=()
    for module in "${modules[@]}"; do
        targets+=("dlls/${module}/x86_64-windows/${module}.dll")
    done
    make -j"${jobs}" "${targets[@]}"
    install -d "${DESTDIR}${WINE_INSTALL_PREFIX}/lib/wine/x86_64-windows"
    install -m 644 "${targets[@]}" "${DESTDIR}${WINE_INSTALL_PREFIX}/lib/wine/x86_64-windows/"
fi

echo "${wine_tag} patch sets: ${patch_sets[*]}" > "${DESTDIR}${WINE_INSTALL_PREFIX}/PATCHED"
file_count="$(find "${DESTDIR}" -type f | wc -l)"
echo "Installed ${file_count} patched Wine files to ${DESTDIR}"
