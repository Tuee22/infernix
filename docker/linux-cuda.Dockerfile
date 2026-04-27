FROM nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04

ARG GHC_VERSION=9.14.1
ARG CABAL_VERSION=3.16.1.0
ARG KIND_VERSION=v0.29.0
ARG KUBECTL_VERSION=v1.34.0
ARG HELM_VERSION=v3.18.6

ENV DEBIAN_FRONTEND=noninteractive \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_ADJUST_BASHRC=0 \
    BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    INFERNIX_BUILD_ROOT=/opt/build/infernix \
    INFERNIX_CABAL_BUILDDIR=/opt/build/infernix/cabal \
    INFERNIX_RUNTIME_MODE=linux-cuda \
    PATH=/opt/build/infernix:/workspace/.build:/root/.local/bin:/root/.ghcup/bin:/root/.cabal/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        docker.io \
        git \
        libffi-dev \
        libgmp-dev \
        libncurses-dev \
        libssl-dev \
        libtinfo-dev \
        pkg-config \
        protobuf-compiler \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        nodejs \
        npm \
        xz-utils \
        zlib1g-dev \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --break-system-packages poetry

RUN curl https://get-ghcup.haskell.org -sSf | sh \
    && ghcup install ghc ${GHC_VERSION} \
    && ghcup set ghc ${GHC_VERSION} \
    && ghcup install cabal ${CABAL_VERSION} \
    && ghcup set cabal ${CABAL_VERSION}

RUN curl -fsSL -o /usr/local/bin/kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64 \
    && chmod +x /usr/local/bin/kind

RUN curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x /usr/local/bin/kubectl

RUN curl -fsSL -o /tmp/helm.tar.gz https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
    && tar -C /tmp -xzf /tmp/helm.tar.gz \
    && install /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

WORKDIR /workspace

COPY . /workspace

RUN mkdir -p /opt/build/infernix /workspace/tools/generated_proto \
    && cabal update \
    && npm --prefix web ci \
    && npx --prefix web playwright install --with-deps chromium firefox webkit \
    && poetry install --directory python/linux-cuda \
    && poetry --directory python/linux-cuda run python -m grpc_tools.protoc \
         -I /workspace/proto \
         --python_out /workspace/tools/generated_proto \
         /workspace/proto/infernix/api/inference_service.proto \
         /workspace/proto/infernix/manifest/runtime_manifest.proto \
         /workspace/proto/infernix/runtime/inference.proto \
    && cabal --builddir=/opt/build/infernix/cabal install \
         --installdir=/usr/local/bin \
         --install-method=copy \
         --overwrite-policy=always \
         exe:infernix \
         exe:infernix-demo \
    && npm --prefix web run build \
    && poetry --directory python/linux-cuda run check-code

CMD ["infernix", "--help"]
