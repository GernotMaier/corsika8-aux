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
  --build-arg CORSIKA_REF=main -t corsika8-toolchain .
```

### Runtime image

```console
podman build --platform=linux/arm64 \
  --build-arg CORSIKA_TOOLCHAIN_IMAGE=localhost/corsika8-toolchain \
  --build-arg BUILD_JOBS=4 \
  --build-arg CORSIKA_REF=main \
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

### Private FLUKA images

FLUKA is licensed software. The FLUKA workflow and every image it pushes must
remain private in GHCR. Before the first run, create the `-fluka`,
`-fluka-dev`, and `-fluka-toolchain` GHCR packages as private packages and
restrict package access to the licensed project members. Do not make these
packages public or expose their layers through a public cache.

Add a repository secret named `FLUKA_ID`. Its value must be a curl Basic-auth
credential in the form `fuid-XXXX:password`; it is mounted as a BuildKit secret
only while downloading FLUKA. The workflow is deliberately
`workflow_dispatch`-only and builds `linux/amd64` images.

The recipe selects the Linux x86_64 gfortran package with the compatible glibc
baseline:

```text
fluka2025.1-linux-gfor64bit-9.4-glibc2.17-AA.tar.gz
fluka2025.1-data.tar.gz
```

The macOS, Apple-Silicon, 32-bit G77, and newer glibc packages are not valid
substitutes for this AlmaLinux 9 image. Package names and platform/compiler
details are listed on the [FLUKA download page](https://www.fluka.eu/Fluka/www/htmls/fluka.php?id=download&sub=packages_ok).

Run the private workflow from the Actions tab, selecting the CORSIKA branch and
image tag. For a local build, keep the credential in a file outside the build
context and pass it as a BuildKit secret:

```console
docker buildx build --platform linux/amd64 \
  --secret id=fluka-id,src=/path/to/fluka-basic-auth \
  --build-arg FLUKA=ON \
  --build-arg CORSIKA_REF=compile-osx \
  --tag corsika8-fluka:local .
```

The private image contains `/opt/fluka`, `FLUPRO=/opt/fluka`, and the FLUKA
data package. The FUID, credential file, downloaded archives, and secret mount
are not copied into the image.
