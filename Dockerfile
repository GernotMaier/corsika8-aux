# CORSIKA8 build stage - contains all development tools and source code
FROM almalinux:9.5-minimal AS builder
ARG FLUKA=OFF
ARG PYTHON_VERSION="3.12"
ARG CORSIKA_BRANCH="master"
WORKDIR /workdir/

RUN microdnf update -y && \
    microdnf install -y \
    binutils cmake findutils \
    gcc-c++ gcc-gfortran git make \
    perl perl-core \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-pip \
    python${PYTHON_VERSION}-devel rsync tar vim && \
    microdnf clean all && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python && \
    ln -sf /usr/bin/pip${PYTHON_VERSION} /usr/bin/pip && \
    python -m venv /workdir/virtual/environment/corsika-8 && \
    source /workdir/virtual/environment/corsika-8/bin/activate && \
    python -m pip install --upgrade pip --root-user-action=ignore && \
    pip install "conan>=2.20.0" numpy==2.3 particle==0.25.1

ENV VIRTUAL_ENV=/workdir/virtual/environment/corsika-8
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN git clone --recursive --branch ${CORSIKA_BRANCH} https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git

ENV CONAN_CPU_COUNT=4
WORKDIR /workdir/corsika-build
RUN ../corsika/conan-install.sh \
     --source-directory ../corsika --release-with-debug && \
    conan cache clean "*" --source --build --download

RUN ../corsika/corsika-cmake.sh \
     -c "-DCMAKE_BUILD_TYPE=RelWithDebInfo \
     -DWITH_FLUKA=${FLUKA} \
     -DCMAKE_INSTALL_PREFIX=../corsika-install"

RUN make -j4 && \
    make install && \
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
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -Dcorsika_DIR="$PWD/corsika-build" \
          -DWITH_FLUKA=${FLUKA} \
          -S "$PWD/corsika/examples" \
          -B "$PWD/corsika-build-examples"

WORKDIR /workdir/corsika-build-examples
RUN make -j4 && \
    rm -rf CMakeFiles && \
    find . -name "*.o" -delete && \
    find . -name "*.obj" -delete
ENV PATH="/workdir/corsika-build-examples/bin:$PATH"

# Install CORSIKA Python libraries (development mode with examples and tests)
WORKDIR /workdir/corsika/python
RUN pip install -e .[tests,examples] && \
    pip install argparse matplotlib pandas

# Ensure the virtual environment is complete for runtime use
RUN pip list > /workdir/virtual/environment/corsika-8/installed_packages.txt

WORKDIR /workdir/

# CORSIKA8 runtime - lightweight image binaries only
FROM almalinux:9.5-minimal AS runtime
ARG PYTHON_VERSION="3.12"

RUN microdnf update -y && \
    microdnf install -y \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-pip \
    && microdnf clean all \
    && ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python \
    && ln -sf /usr/bin/pip${PYTHON_VERSION} /usr/bin/pip

# Copy the complete, working environment from builder
COPY --from=builder /workdir/corsika-install /opt/corsika
COPY --from=builder /workdir/virtual/environment/corsika-8 /opt/corsika-python
COPY --from=builder /workdir/corsika/python /opt/corsika-src/python

ENV PATH="/opt/corsika/bin:/opt/corsika-python/bin:$PATH"
ENV LD_LIBRARY_PATH="/opt/corsika/lib:/opt/corsika/lib64:$LD_LIBRARY_PATH"
ENV VIRTUAL_ENV="/opt/corsika-python"

# CORSIKA8 Python library installation for runtime
WORKDIR /opt/corsika-src/python
RUN /opt/corsika-python/bin/pip install --no-deps -e . && \
    /opt/corsika-python/bin/python -c "import corsika; print('CORSIKA Python library successfully installed')"

WORKDIR /workspace

FROM runtime
