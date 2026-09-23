# CORSIKA8 Auxiliaries

This repository contains auxiliary files for CORSIKA8, such as Docker files and scripts to install dependencies.

Please refer to the main [CORSIKA gitlab](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika) for any relevant information.

## Installation steps

### Toolchain image

Build the toolchain once. It contains compilers, the Python environment, and
Conan, but no CORSIKA source. Reuse it when building different CORSIKA refs.

```console
podman build --platform=linux/arm64 -f Dockerfile.toolchain -t corsika8-toolchain .
```

### Runtime image

```console
podman build --platform=linux/arm64 \
  --build-arg CORSIKA_TOOLCHAIN_IMAGE=localhost/corsika8-toolchain \
  --build-arg BUILD_JOBS=4 \
  --build-arg CORSIKA_BRANCH=main -t corsika8 .
podman build --platform=linux/arm64 \
  --build-arg CORSIKA_TOOLCHAIN_IMAGE=localhost/corsika8-toolchain \
  --build-arg CORSIKA_BRANCH=radek_cherenkov -t corsika8-radek .
```

```console
podman run --platform=linux/arm64 -it --rm corsika8 bash
```

The default image is the runtime image. Build the `builder` target when you need
the CORSIKA source tree, build directories, and test executables:

```console
podman build --target builder \
  --build-arg CORSIKA_TOOLCHAIN_IMAGE=localhost/corsika8-toolchain \
  --build-arg CORSIKA_BRANCH=radek_cherenkov -t corsika8-dev .
```

The runtime image is built in `Release` mode. It contains the installed CORSIKA
data at `/workdir/corsika-install/share/corsika/data`; set `CORSIKA_DATA` only
when intentionally overriding that location.

The CI workflow pins each code build to the digest of its published toolchain
image. A future dependency image can safely cache Conan packages; a simple
build-cache mount is insufficient because CMake records absolute Conan paths.

`BUILD_JOBS` defaults to `4`. Lower it on constrained hosts; CI uses `2` to
avoid memory pressure while compiling CORSIKA and its external projects.
