# CORSIKA8 Auxiliaries

This repository contains auxiliary files for CORSIKA8, such as Docker files and scripts to install dependencies.

Please refer to the main [CORSIKA gitlab](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika) for any relevant information.

## Installation steps

### Toolchain image

Build the toolchain once per CORSIKA ref. It contains compilers, the Python
environment, and the Conan dependencies generated from that ref's
`conanfile.py`, but no CORSIKA source checkout.

```console
podman build --platform=linux/arm64 -f Dockerfile.toolchain \
  --build-arg CORSIKA_REF=master -t corsika8-toolchain .
```

### Runtime image

```console
podman build --platform=linux/arm64 \
  --build-arg CORSIKA_TOOLCHAIN_IMAGE=localhost/corsika8-toolchain \
  --build-arg BUILD_JOBS=4 \
  --build-arg CORSIKA_REF=master \
  -t corsika8 .
```

```console
podman run --platform=linux/arm64 -it --rm corsika8 bash
```

The default image is the runtime image. Build the `builder` target when you need
the CORSIKA source tree, build directories, and test executables:

```console
podman build --target builder \
  --build-arg CORSIKA_TOOLCHAIN_IMAGE=localhost/corsika8-toolchain \
  -t corsika8-dev .
```

The runtime image is built in `Release` mode. It contains the installed CORSIKA
data at `/workdir/corsika-install/share/corsika/data`; set `CORSIKA_DATA` only
when intentionally overriding that location.
