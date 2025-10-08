FROM almalinux:9.5-minimal
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
RUN ../corsika/conan-install.sh --source-directory ../corsika --release-with-debug

RUN ../corsika/corsika-cmake.sh \
     -c "-DCMAKE_BUILD_TYPE=RelWithDebInfo \
     -DWITH_FLUKA=${FLUKA} \
     -DCMAKE_INSTALL_PREFIX=../corsika-install"

RUN make -j4 && \
    make install
