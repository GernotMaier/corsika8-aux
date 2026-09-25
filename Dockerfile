# syntax=docker/dockerfile:1.7
# CORSIKA8 build stage - source code compiled on a reusable toolchain image.
# Build Dockerfile.toolchain locally first, or use the published image.
ARG CORSIKA_TOOLCHAIN_IMAGE=ghcr.io/gernotmaier/corsika8-aux-toolchain:latest
FROM ${CORSIKA_TOOLCHAIN_IMAGE} AS builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG FLUKA=OFF
ARG FLUKA_BINARY_PACKAGE="fluka2025.1-linux-gfor64bit-9.4-glibc2.17-AA.tar.gz"
ARG FLUKA_DATA_PACKAGE="fluka2025.1-data.tar.gz"
ARG FLUKA_PACKAGE_BASE="https://www.fluka.eu/Fluka/www/htmls/packages"
ARG CORSIKA_REF="main"
ARG BUILD_JOBS=4
WORKDIR /workdir/

<<<<<<< HEAD
# FLUKA is available only to registered users. The secret is expected to be a
# curl Basic-auth value (normally `fuid-XXXX:password`). It is mounted only for
# this command and is never copied into an image layer or build argument.
RUN --mount=type=secret,id=fluka-id,required=false \
    set -euo pipefail; \
    mkdir -p /opt/fluka; \
    if [[ "${FLUKA^^}" == "ON" ]]; then \
      test -s /run/secrets/fluka-id; \
      fluka_auth="$(cat /run/secrets/fluka-id)"; \
      test -n "$fluka_auth"; \
      for package in "${FLUKA_BINARY_PACKAGE}" "${FLUKA_DATA_PACKAGE}"; do \
        curl --fail --location --retry 5 --silent --show-error \
          --user "$fluka_auth" \
          "${FLUKA_PACKAGE_BASE}/${package}" \
          --output "/tmp/${package}"; \
        test "$(wc -c < "/tmp/${package}")" -gt 1024; \
        mkdir -p "/tmp/extract-${package}"; \
        tar -xzf "/tmp/${package}" -C "/tmp/extract-${package}"; \
        if [[ -d "/tmp/extract-${package}/fluka2025.1" ]]; then \
          cp -a "/tmp/extract-${package}/fluka2025.1/." /opt/fluka/; \
        else \
          cp -a "/tmp/extract-${package}/." /opt/fluka/; \
        fi; \
        rm -rf "/tmp/${package}" "/tmp/extract-${package}"; \
      done; \
      test -s /opt/fluka/libflukahp.a; \
    fi

ENV FLUPRO=/opt/fluka \
    FLUFOR=gfortran

# Pythia's historic archives are served as .tgz files under /releases.  Conan
# was already installed from this exact ref's recipe in the toolchain image.
# Fetch the immutable revision directly instead of cloning a moving branch
# tip.  This keeps the source checkout shallow and guarantees it matches the
# Conan recipe selected for the toolchain image.
RUN git init /workdir/corsika && \
    cd /workdir/corsika && \
    git remote add origin https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git && \
    git fetch --depth 1 origin "${CORSIKA_REF}" && \
    git checkout --detach FETCH_HEAD && \
    git submodule update --init --recursive --depth 1 && \
    sed -i \
=======
# The workflow downloads CORSIKA once, including its submodules, and shares
# that source archive with the Linux and macOS jobs.  Conan was already
# installed from this exact ref's recipe in the toolchain image.
COPY corsika /workdir/corsika
RUN test "$(git -C /workdir/corsika rev-parse HEAD)" = \
      "$(git -C /workdir/corsika rev-parse "${CORSIKA_REF}^{commit}")"
RUN sed -i \
>>>>>>> origin/main
      -e 's#https://pythia.org/download/pythia83#https://pythia.org/releases/pythia83#g' \
      -e 's#\.tar\.bz2#.tgz#g' \
      -e 's#faf2730a959369e4d25e1285ab70d915#6fbe60db1514778e94a671e9a75c654e#g' \
      /workdir/corsika/modules/pythia8/CMakeLists.txt

ENV CONAN_CPU_COUNT=4
WORKDIR /workdir/corsika-build
RUN cp -a /workdir/corsika-conan /workdir/corsika/conan_cmake

RUN cmake -S ../corsika \
      -D CONAN_CMAKE_DIR=../corsika/conan_cmake \
      -D CMAKE_TOOLCHAIN_FILE=../corsika/conan_cmake/conan_toolchain.cmake \
      -D CMAKE_POLICY_DEFAULT_CMP0091=NEW \
      -D CMAKE_BUILD_TYPE=Release \
      -D WITH_FLUKA=${FLUKA} \
      -D C8_FLUKALIB=/opt/fluka/libflukahp.a \
      -D CMAKE_INSTALL_PREFIX=../corsika-install && \
    sed -i \
      's#/workdir/corsika-build/modules/pythia8/pythia8/install/share/Pythia8/xmldoc/#/workdir/corsika-install/share/Pythia8/xmldoc/#' \
      /workdir/corsika-build/corsika/modules/pythia8/Pythia8ConfigurationDirectory.hpp

RUN build_log=/tmp/corsika-build.log && \
    run_and_report() { \
      local description="$1"; shift; \
      "$@" > "$build_log" 2>&1 & \
      local build_pid=$!; \
      while kill -0 "$build_pid" 2>/dev/null; do \
        sleep 30; \
        kill -0 "$build_pid" 2>/dev/null && echo "$description is still running..."; \
      done; \
      wait "$build_pid"; \
      local status=$?; \
      if [ "$status" -ne 0 ]; then \
        echo "$description failed; relevant diagnostics follow:"; \
        grep -nEi 'error:|fatal error:|undefined reference|collect2:|ld:|No rule to make target|killed|failed|cannot|not found|no such file' "$build_log" | tail -n 20 | cut -c1-240 || true; \
        echo "End of build log:"; \
        tail -n 20 "$build_log" | cut -c1-240; \
      fi; \
      return "$status"; \
    }; \
    run_and_report "CORSIKA compilation" make -j"${BUILD_JOBS}" && \
    run_and_report "CORSIKA installation" make install && \
    rm -rf /workdir/corsika-build/_deps && \
    rm -rf /workdir/corsika-build/CMakeFiles && \
    find /workdir/corsika-build -name "*.o" -delete && \
    find /workdir/corsika-build -name "*.obj" -delete

# CORSIKA8 examples (development container only)
WORKDIR /workdir
RUN export CONAN_DEPENDENCIES="$PWD/corsika-install/lib/cmake/dependencies" && \
    cmake -DCMAKE_TOOLCHAIN_FILE="${CONAN_DEPENDENCIES}/conan_toolchain.cmake" \
          -DCMAKE_PREFIX_PATH="${CONAN_DEPENDENCIES}" \
          -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
          -DCMAKE_BUILD_TYPE=Release \
          -Dcorsika_DIR="$PWD/corsika-build" \
          -DWITH_FLUKA=${FLUKA} \
          -DC8_FLUKALIB=/opt/fluka/libflukahp.a \
          -S "$PWD/corsika/examples" \
          -B "$PWD/corsika-build-examples"

WORKDIR /workdir/corsika-build-examples
RUN make -j"${BUILD_JOBS}" && \
    rm -rf CMakeFiles && \
    find . -name "*.o" -delete && \
    find . -name "*.obj" -delete
ENV PATH="/workdir/corsika-build-examples/bin:$PATH"

# Install CORSIKA Python libraries (development mode with examples and tests)
WORKDIR /workdir/corsika/python
RUN python -m pip install -e '.[test,examples]'

# Ensure the virtual environment is complete for runtime use
RUN pip list > /workdir/virtual/environment/corsika-8/installed_packages.txt

WORKDIR /workdir/

# CORSIKA8 runtime - lightweight image binaries only
FROM almalinux:9.5-minimal AS runtime
ARG PYTHON_VERSION="3.12"

RUN microdnf update -y && \
    microdnf install -y \
    findutils \
    libgfortran libstdc++ libgomp \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-pip \
    rsync tar vim \
    && microdnf clean all \
    && ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python \
    && ln -sf /usr/bin/pip${PYTHON_VERSION} /usr/bin/pip

COPY --from=builder /workdir/corsika-install /workdir/corsika-install
# Empty for the ordinary public build; populated only by the private FLUKA
# build.
COPY --from=builder /opt/fluka /opt/fluka
# The editable Python package installed below requires its source tree at runtime.
COPY --from=builder /workdir/corsika/python /workdir/corsika/python

RUN python -m venv /workdir/virtual/environment/corsika-8 && \
    /workdir/virtual/environment/corsika-8/bin/pip install --upgrade pip

ENV PATH="/opt/fluka:/opt/fluka/bin:/workdir/corsika-install/bin:/workdir/virtual/environment/corsika-8/bin:$PATH"
ENV LD_LIBRARY_PATH="/opt/fluka/lib:/workdir/corsika-install/lib:/workdir/corsika-install/lib64"
ENV CORSIKA_DATA="/workdir/corsika-install/share/corsika/data"
ENV VIRTUAL_ENV="/workdir/virtual/environment/corsika-8"
ENV FLUPRO="/opt/fluka" \
    FLUFOR="gfortran"

WORKDIR /workdir/corsika/python
RUN /workdir/virtual/environment/corsika-8/bin/python -m pip install -e '.[examples]' && \
    /workdir/virtual/environment/corsika-8/bin/python -c "import corsika8.io; print('CORSIKA Python library successfully installed')"

WORKDIR /workdir

FROM runtime
