ARG GO_IMAGE=golang:1.24
ARG BASE_IMAGE=ubuntu:24.04
FROM ${GO_IMAGE} AS nvkind-builder

ARG NVKIND_GO_INSTALL_TARGET=github.com/NVIDIA/nvkind/cmd/nvkind@8bce71ec58cf12b4003758eb4e49adac53cc40f2

RUN GOBIN=/go/bin go install ${NVKIND_GO_INSTALL_TARGET}

FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG RUNTIME_MODE=linux-cpu
ARG DEMO_UI=true
ARG GHC_VERSION=9.14.1
ARG FORMATTER_GHC_VERSION=9.12.4
ARG CABAL_VERSION=3.16.1.0
ARG KIND_VERSION=v0.29.0
ARG KUBECTL_VERSION=v1.34.0
ARG HELM_VERSION=v3.18.6
ARG UBUNTU_APT_MIRROR=http://mirrors.edge.kernel.org/ubuntu/
ARG TARGETARCH

# Phase 1 Sprint 1.11 — the build-root env override was removed. The Haskell binary
# discovers its build root through 'discoverPaths' (cwd-walk + optional
# host-manifest lookup) instead of consuming a process-inherited env
# var. The supported in-image build root is the convention default
# @/workspace/.build@.
ENV DEBIAN_FRONTEND=noninteractive \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1 \
    BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} \
    BOOTSTRAP_HASKELL_CABAL_VERSION=${CABAL_VERSION} \
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    POETRY_HOME=/opt/poetry \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    GHC_VERSION=${GHC_VERSION} \
    FORMATTER_GHC_VERSION=${FORMATTER_GHC_VERSION} \
    CABAL_VERSION=${CABAL_VERSION} \
    PATH=/opt/poetry/bin:/root/.local/bin:/root/.ghcup/bin:/root/.cabal/bin:${PATH}

RUN sed -i \
      -e "s#http://archive.ubuntu.com/ubuntu/#${UBUNTU_APT_MIRROR}#g" \
      -e "s#http://security.ubuntu.com/ubuntu/#${UBUNTU_APT_MIRROR}#g" \
      /etc/apt/sources.list.d/ubuntu.sources \
    && printf 'Acquire::ForceIPv4 "true";\nAcquire::Retries "5";\n' >/etc/apt/apt.conf.d/99infernix-network

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        docker-buildx \
        docker.io \
        docker-compose-v2 \
        git \
        gnupg \
        libatomic1 \
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
        skopeo \
        tini \
        xz-utils \
        zlib1g-dev \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv ${POETRY_HOME} \
    && ${POETRY_HOME}/bin/python -m pip install --upgrade pip \
    && ${POETRY_HOME}/bin/pip install poetry \
    && ln -sfn ${POETRY_HOME}/bin/poetry /usr/local/bin/poetry

RUN curl https://get-ghcup.haskell.org -sSf | sh \
    && ghcup install ghc ${FORMATTER_GHC_VERSION} \
    && ghcup set ghc ${GHC_VERSION} \
    && ghcup set cabal ${CABAL_VERSION} \
    && mkdir -p /opt/ghc \
    && ln -sfn /root/.ghcup/ghc/${FORMATTER_GHC_VERSION} /opt/ghc/${FORMATTER_GHC_VERSION} \
    && ln -sfn /root/.ghcup/ghc/${GHC_VERSION} /opt/ghc/${GHC_VERSION}

RUN set -eu; \
    tool_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${tool_arch}" in \
      amd64|arm64) ;; \
      *) echo "unsupported linux substrate tool architecture: ${tool_arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${tool_arch}"; \
    chmod +x /usr/local/bin/kind; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${tool_arch}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${tool_arch}.tar.gz"; \
    tar -C /tmp -xzf /tmp/helm.tar.gz; \
    install "/tmp/linux-${tool_arch}/helm" /usr/local/bin/helm; \
    rm -rf /tmp/helm.tar.gz "/tmp/linux-${tool_arch}"

COPY --from=nvkind-builder /go/bin/nvkind /usr/local/bin/nvkind

# Phase 3 Sprint 3.11 (2026-05-29): the bitnami minio sub-chart is
# retired in favor of the hand-authored MinIO StatefulSet under
# `chart/templates/minio/`, so this pre-fetch stops pulling
# `minio-17.0.21.tgz` from charts.bitnami.com. The supported MinIO
# image inventory uses upstream multi-arch `minio/minio` + `minio/mc`
# + `busybox` (see chart/values.yaml.infernixMinio).
RUN set -eu; \
    mkdir -p /opt/infernix/chart/charts; \
    helm pull harbor --repo https://helm.goharbor.io --version 1.18.3 --destination /opt/infernix/chart/charts; \
    helm pull pg-operator --repo https://percona.github.io/percona-helm-charts --version 2.9.0 --destination /opt/infernix/chart/charts; \
    helm pull pg-db --repo https://percona.github.io/percona-helm-charts --version 2.9.0 --destination /opt/infernix/chart/charts; \
    helm pull pulsar --repo https://pulsar.apache.org/charts --version 4.5.0 --destination /opt/infernix/chart/charts; \
    helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.7.2 --destination /opt/infernix/chart/charts

WORKDIR /workspace

COPY . /workspace

RUN mkdir -p /workspace/.build /opt/infernix /opt/infernix/dhall \
    && rm -rf /workspace/chart/charts \
    && ln -s /opt/infernix/chart/charts /workspace/chart/charts \
    && cd /workspace \
    && find . -type f | sed 's#^\\./##' | LC_ALL=C sort > /opt/infernix/source-snapshot-files.txt

# Phase 1 Sprint 1.11 — bake the supported Linux outer-container host
# manifest into the image at the canonical mount path. The Haskell
# binary's `discoverPaths` reads this file via `tryLoadHostManifest`
# at startup so it can resolve `buildRoot = /workspace/.build/outer-container/build`
# (the supported outer-container path) instead of falling back to
# `/workspace/.build` (the host-native fallback default that
# mis-classifies the container as `HostNative`). Operators override
# per-host by editing this file before the binary needs it.
RUN printf '%s\n' \
    '{ hostExecutionContext = < AppleHostNative | LinuxOuterContainer >.LinuxOuterContainer' \
    ", hostArchitecture = \"${TARGETARCH:-$(dpkg --print-architecture)}\"" \
    ', toolPaths =' \
    '    { docker = "/usr/bin/docker"' \
    '    , kubectl = "/usr/local/bin/kubectl"' \
    '    , helm = "/usr/local/bin/helm"' \
    '    , kind = "/usr/local/bin/kind"' \
    '    , cabal = "/usr/local/bin/cabal"' \
    '    , ghc = "/usr/local/bin/ghc"' \
    '    , ghcup = ""' \
    '    , ormolu = "/workspace/.build/haskell-style-tools/bin/ormolu"' \
    '    , hlint = "/workspace/.build/haskell-style-tools/bin/hlint"' \
    '    , npm = "/usr/local/bin/npm"' \
    '    , node = "/usr/local/bin/node"' \
    '    , python3 = "/usr/bin/python3"' \
    '    , poetry = "/opt/poetry/bin/poetry"' \
    '    , protoc = "/usr/bin/protoc"' \
    '    , git = "/usr/bin/git"' \
    '    , tar = "/usr/bin/tar"' \
    '    , curl = "/usr/bin/curl"' \
    '    , aptGet = "/usr/bin/apt-get"' \
    '    , brew = ""' \
    '    , sudo = "/usr/bin/sudo"' \
    '    , systemctl = "/usr/bin/systemctl"' \
    '    , mkdir = "/usr/bin/mkdir"' \
    '    , chmod = "/usr/bin/chmod"' \
    '    , ln = "/usr/bin/ln"' \
    '    , install = "/usr/bin/install"' \
    '    , id = "/usr/bin/id"' \
    '    , getent = "/usr/bin/getent"' \
    '    , cut = "/usr/bin/cut"' \
    '    , dirname = "/usr/bin/dirname"' \
    '    , bash = "/usr/bin/bash"' \
    '    , crictl = "/usr/local/bin/crictl"' \
    '    , chown = "/usr/bin/chown"' \
    '    , nvidiaSmi = "/usr/bin/nvidia-smi"' \
    '    , nvkind = "/usr/local/bin/nvkind"' \
    '    , skopeo = "/usr/bin/skopeo"' \
    '    , hostname = "/usr/bin/hostname"' \
    '    }' \
    ', filesystem =' \
    '    { repoRoot = "/workspace"' \
    '    , buildRoot = "/workspace/.build/outer-container/build"' \
    '    , dataRoot = "/workspace/.data"' \
    '    , runtimeRoot = "/workspace/.data/runtime"' \
    '    , kubeconfigPath = "/workspace/.data/runtime/infernix.kubeconfig"' \
    '    , secretsRoot = "/workspace/.data/runtime/secrets"' \
    '    , homeDirectory = "/root"' \
    '    , kindRoot = "/workspace/.data/runtime/kind"' \
    '    }' \
    ', playwrightHost = "127.0.0.1"' \
    ', controlPlaneContext = "outer-container"' \
    '}' \
    > /opt/infernix/dhall/InfernixHost.dhall

RUN mkdir -p /workspace/tools/generated_proto \
    && cabal update \
    && npm --prefix web install --no-audit --no-fund \
    && poetry install --directory python \
    && poetry --directory python run python -m grpc_tools.protoc \
         -I /workspace/proto \
         --python_out /workspace/tools/generated_proto \
         /workspace/proto/infernix/manifest/runtime_manifest.proto \
         /workspace/proto/infernix/runtime/inference.proto \
    && cabal build all \
    && cabal install \
         --installdir=/usr/local/bin \
         --install-method=copy \
         --overwrite-policy=always \
         exe:infernix \
         exe:infernix-demo \
    && infernix internal materialize-substrate ${RUNTIME_MODE} --demo-ui ${DEMO_UI} \
    && npm --prefix web run build \
    && poetry --directory python run check-code

# Phase 3 Sprint 3.10 — Playwright system dependencies + browser
# install live in the launcher image. The previous dedicated
# @infernix-playwright:local@ container is retired; @infernix test e2e@
# now invokes @npm --prefix web exec -- playwright test ...@ inside
# this launcher container, on the same private Docker @kind@ network as
# the running cluster.
RUN apt-get update \
    && npm --prefix web exec -- playwright install --with-deps chromium firefox webkit \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["infernix", "--help"]
