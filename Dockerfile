# CORSIKA8 build stage - source code compiled on a reusable toolchain image.
# Build Dockerfile.toolchain locally first, or use the published image.
ARG CORSIKA_TOOLCHAIN_IMAGE=ghcr.io/gernotmaier/corsika8-aux-toolchain:latest
FROM ${CORSIKA_TOOLCHAIN_IMAGE} AS builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG FLUKA=OFF
ARG CORSIKA_REF="main"
ARG BUILD_JOBS=4
WORKDIR /workdir/

# The workflow downloads CORSIKA once, including its submodules, and shares
# that source archive with the Linux and macOS jobs.  Conan was already
# installed from this exact ref's recipe in the toolchain image.
COPY corsika /workdir/corsika
RUN test "$(git -C /workdir/corsika rev-parse HEAD)" = "${CORSIKA_REF}"
RUN sed -i \
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
# The editable Python package installed below requires its source tree at runtime.
COPY --from=builder /workdir/corsika/python /workdir/corsika/python

RUN python -m venv /workdir/virtual/environment/corsika-8 && \
    /workdir/virtual/environment/corsika-8/bin/pip install --upgrade pip

ENV PATH="/workdir/corsika-install/bin:/workdir/virtual/environment/corsika-8/bin:$PATH"
ENV LD_LIBRARY_PATH="/workdir/corsika-install/lib:/workdir/corsika-install/lib64"
ENV CORSIKA_DATA="/workdir/corsika-install/share/corsika/data"
ENV VIRTUAL_ENV="/workdir/virtual/environment/corsika-8"

WORKDIR /workdir/corsika/python
RUN /workdir/virtual/environment/corsika-8/bin/python -m pip install -e '.[examples]' && \
    /workdir/virtual/environment/corsika-8/bin/python -c "import corsika8.io; print('CORSIKA Python library successfully installed')"

WORKDIR /workdir

FROM runtime
