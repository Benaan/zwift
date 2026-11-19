---
title: Patched Wine
parent: Advanced
nav_order: 6
---

# Patched Wine

`src/Dockerfile.patched-wine` builds an image on top of `docker.io/netbrain/zwift:latest` with a patched Wine. It
always matches the Wine version of that image: the build reads `wine --version` from it and patches the same release.

- `src/wine-patches/video`: video screenshots (mid ride video recordings) no longer leak memory and crash Zwift.
  Quick to build, it only replaces 4 dlls.
- `src/wine-patches/ble`: native bluetooth, pair your trainer, heart rate monitor and controllers in Zwift without the
  Companion App. This is a full Wine build, expect 30 minutes or more.

## Build the image

```console
foo@bar:~$ src/build-patched-image.sh                 # video screenshots only
foo@bar:~$ WINE_BLE=1 src/build-patched-image.sh      # video screenshots and bluetooth
```

Then add this to `~/.config/zwift/config`:

```bash
IMAGE=localhost/zwift-patched
VERSION=latest
DONT_UPDATE=1          # the image is local, don't pull it from docker hub
DISABLE_BLUETOOTH=0    # only with WINE_BLE=1, passes the host bluetooth to the container
```

`DONT_UPDATE=1` also stops automatic updates. When a new `netbrain/zwift` image is released, run the build script
again; it pulls the new base image first.

## Video screenshots

Zwift records clips with Media Foundation's sink writer (`MFCreateSinkWriterFromURL`, NV12 frames in, H.264 MP4 out).
In stock Wine:

1. `IMFSinkWriter::WriteSample` never runs the encoder and the MP4 sink never requests samples, so every frame stays queued.
2. `IMFSinkWriter::Finalize` is not implemented, so Zwift reports `IMFSinkWriter::Finalize failed, hr=-2147467263`.
3. The output file stays open, so the next clip fails with `CreateSinkWriter failed, hr=-2147024864` (sharing violation).
4. Zwift keeps retrying and allocating pixel buffers until the system runs out of memory ([#438]).

The patches implement encoding and `Finalize` in `mfreadwrite`, sample requests in the `winegstreamer` MP4 sink,
scaling in the `msvproc` video processor (Zwift encodes at half the capture size) and `IMFByteStream::Close` in
`mfplat`. Encoding uses the OpenH264 encoder that is already in the image.

## Bluetooth

The bluetooth patch is the Bluetooth LE stack by [purm](https://github.com/purm/wine-with-ble), see [#188]. It is a large
patch that is not part of upstream Wine, so treat it as experimental.

- Bluetooth is passed to the container through the host's D-Bus system bus, so `bluetoothd` has to run on the host.
- Wine does not bond devices. If a device needs an encrypted connection, pair it once on the host (for example with
  `bluetoothctl`) before starting Zwift.
- Some built in Realtek adapters have trouble with the Zwift Ride controllers; a USB bluetooth dongle helps.

## Troubleshooting

- Check which patches an image has: `docker run --rm --entrypoint cat localhost/zwift-patched /opt/wine-devel/PATCHED`
- Video capture is logged in Zwift's `Log.txt` with `[VIDEO_CAPTURE]`, see
  [ZWIFT_LOG_DIR](../../configuration/options/#zwift_log_dir).
- Media Foundation details: start Zwift with `CONTAINER_EXTRA_ARGS=(--env WINEDEBUG=warn+mfplat)`.
- Bluetooth details: start Zwift with `CONTAINER_EXTRA_ARGS=(--env WINEDEBUG=+bluetooth,+winebth)`.

[#188]: https://github.com/netbrain/zwift/issues/188
[#438]: https://github.com/netbrain/zwift/issues/438
