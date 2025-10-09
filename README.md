# CORSIKA8 Auxiliaries

This repository contains auxiliary files for CORSIKA8, such as Dockerfiles and scripts to install dependencies.

Please refer to the main [CORSIKA gitlab](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika) for any relevant information.

## Installation steps

### Base image

```console
podman buildx build --platform=linux/arm64 --no-cache  -f Dockerfile -t corsika8 .
podman buildx build --platform=linux/amd64 --no-cache  -f Dockerfile -t corsika8 .
```

```console
podman run --platform=linux/arm64 -it --rm corsika8 bash
```
