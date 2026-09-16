# syntax=docker/dockerfile:1.7
# CORSIKA8 build stage - source code compiled on a reusable toolchain image.
# Build Dockerfile.toolchain locally first, or use the published image.
ARG CORSIKA_TOOLCHAIN_IMAGE=ghcr.io/gernotmaier/corsika8-aux-toolchain:latest
FROM ${CORSIKA_TOOLCHAIN_IMAGE} AS builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG FLUKA=OFF
ARG CORSIKA_BRANCH="master"
ARG BUILD_JOBS=4
ARG TARGETARCH
WORKDIR /workdir/

RUN git clone --recursive --branch "${CORSIKA_BRANCH}" https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git

ENV CONAN_CPU_COUNT=4
WORKDIR /workdir/corsika-build
RUN --mount=type=cache,id=corsika-conan-${TARGETARCH},target=/root/.conan2,sharing=locked \
    ../corsika/conan-install.sh \
     --source-directory ../corsika --release && \
    conan cache clean "*" --source --build --download

RUN ../corsika/corsika-cmake.sh \
     -c "-DWITH_FLUKA=${FLUKA} \
     -DCMAKE_INSTALL_PREFIX=../corsika-install"

RUN build_log=/tmp/corsika-build.log && \
    make -j"${BUILD_JOBS}" 2>&1 | tee "$build_log"; \
    build_status=${PIPESTATUS[0]}; \
    if [ "$build_status" -ne 0 ]; then \
      echo "CORSIKA compilation failed; relevant diagnostics follow:"; \
      grep -nEi 'error:|fatal error:|undefined reference|collect2:|ld:|No rule to make target|killed' "$build_log" || true; \
      tail -n 200 "$build_log"; \
      exit "$build_status"; \
    fi; \
    make install 2>&1 | tee -a "$build_log"; \
    install_status=${PIPESTATUS[0]}; \
    if [ "$install_status" -ne 0 ]; then \
      echo "CORSIKA installation failed; relevant diagnostics follow:"; \
      grep -nEi 'error:|fatal error:|undefined reference|collect2:|ld:|No rule to make target|killed' "$build_log" || true; \
      tail -n 200 "$build_log"; \
      exit "$install_status"; \
    fi; \
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
ENV LD_LIBRARY_PATH="/workdir/corsika-install/lib:/workdir/corsika-install/lib64:$LD_LIBRARY_PATH"
ENV VIRTUAL_ENV="/workdir/virtual/environment/corsika-8"

WORKDIR /workdir/corsika/python
RUN /workdir/virtual/environment/corsika-8/bin/python -m pip install -e '.[examples]' && \
    /workdir/virtual/environment/corsika-8/bin/python -c "import corsika; print('CORSIKA Python library successfully installed')"

WORKDIR /workdir

FROM runtime
