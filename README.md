# CORSIKA8 Auxiliaries

This repository contains auxiliary files for CORSIKA8, such as Docker files and scripts to install dependencies.

Please refer to the main [CORSIKA gitlab](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika) for any relevant information.

## Installation steps

### Base image

```console
podman build --platform=linux/arm64 --build-arg CORSIKA_BRANCH=master -t corsika8 .
podman build --platform=linux/amd64 --build-arg CORSIKA_BRANCH=master -t corsika8 .
```

```console
podman run --platform=linux/arm64 -it --rm corsika8 bash
```

The default image is the runtime image. Build the `builder` target when you need
the CORSIKA source tree, build directories, and test executables:

```console
podman build --target builder -t corsika8-dev .
```

The runtime image is built in `Release` mode. It contains the installed CORSIKA
data at `/workdir/corsika-install/share/corsika/data`; set `CORSIKA_DATA` only
when intentionally overriding that location.
