FROM haskell:9.14.1-slim-bookworm AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY Setup.hs cabal.project infernix.cabal LICENSE README.md ./
COPY app app
COPY proto proto
COPY src src
COPY test test

RUN cabal update \
    && cabal install --builddir=/tmp/infernix-cabal --installdir=/opt/infernix/bin --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo

FROM haskell:9.14.1-slim-bookworm

ARG KIND_VERSION=v0.31.0
ARG KUBECTL_VERSION=v1.35.3
ARG HELM_VERSION=v4.1.3
ARG DOCKER_VERSION=29.2.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl nodejs npm protobuf-compiler python3 tar gzip unzip \
    && arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
        amd64) bin_arch=amd64; docker_arch=x86_64 ;; \
        arm64) bin_arch=arm64; docker_arch=aarch64 ;; \
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
      esac \
    && curl -fsSL "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz \
    && tar -xzf /tmp/docker.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker.tgz /tmp/docker \
    && curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${bin_arch}" -o /usr/local/bin/kind \
    && chmod +x /usr/local/bin/kind \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${bin_arch}/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${bin_arch}.tar.gz" -o /tmp/helm.tgz \
    && tar -xzf /tmp/helm.tgz -C /tmp \
    && mv "/tmp/linux-${bin_arch}/helm" /usr/local/bin/helm \
    && rm -rf /tmp/helm.tgz "/tmp/linux-${bin_arch}" \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY --from=build /opt/infernix/bin/infernix /usr/local/bin/infernix
COPY --from=build /opt/infernix/bin/infernix-demo /usr/local/bin/infernix-demo

RUN cabal update

ENV INFERNIX_BUILD_ROOT=/opt/build/infernix
ENV INFERNIX_CABAL_BUILDDIR=/opt/build/infernix

CMD ["infernix", "--help"]
