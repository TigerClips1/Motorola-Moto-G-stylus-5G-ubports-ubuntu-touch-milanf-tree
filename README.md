# Motorola moto g stylus 5G (2022) (milanf)

This repository contains the device configuration and overlays for the
Ubuntu Touch / Halium port for the Motorola moto g stylus 5G (2022), codename
`milanf`. The target device is specified in [`deviceinfo`](./deviceinfo).

## Build

Build on a Linux x86_64 host with the packages used by the existing build
pipeline. Ubuntu 20.04 is the pipeline's baseline:

```sh
sudo apt-get update
sudo apt-get install -y \
  android-tools-mkbootimg bc bison build-essential ca-certificates cpio curl \
  fakeroot flex git kmod libelf-dev libssl-dev libtinfo5 lz4 python2 python3 \
  sudo unzip wget xz-utils pahole libbpf-dev
```

From the repository root, run:

```sh
./build.sh
```

The wrapper fetches the UBports generic adaptation build tools and required
kernel/toolchain sources, then writes build products to `out/`. Use
`./build.sh -b <directory>` to place temporary build files somewhere other than
the default `workdir/`.

The full device build is resource-intensive and is not run by GitHub Actions.
The Actions workflow checks shell syntax only; perform device builds locally or
on a suitably provisioned self-hosted runner. The generic adaptation build
tools are currently fetched from UBports GitLab, independently of where this
repository is hosted.

## Build artifacts and OTA inputs

`out/`, `workdir/`, and `build/` are local build directories. The large
`images/` and `ota/` directories are also intentionally excluded from Git to
avoid committing generated images and downloaded OTA payloads. The regular
device build creates its package in `out/`; OTA-based images can be prepared
with the helper scripts fetched into `build/`:

```sh
./build/fetch-and-prepare-latest-ota.sh \
  20.04/arm64/android9plus/devel milanf ota
./build/system-image-from-ota.sh ota/ubuntu_command out
```

Share finished images as GitHub Release assets or through an appropriate
external artifact host rather than committing them to this repository.

## Licensing

No repository-level license file is currently present. Confirm the applicable
licenses for the project and included files, and add an owner-approved license
before public redistribution.
