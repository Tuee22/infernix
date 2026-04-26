FROM haskell:9.14.1-slim-bookworm AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY Setup.hs cabal.project infernix.cabal LICENSE README.md ./
COPY app app
COPY proto proto
COPY src src
COPY test test

RUN cabal update \
    && cabal build --builddir=/tmp/infernix-cabal exe:infernix exe:infernix-demo \
    && install -D "$(cabal list-bin --builddir=/tmp/infernix-cabal exe:infernix)" /opt/infernix/bin/infernix \
    && install -D "$(cabal list-bin --builddir=/tmp/infernix-cabal exe:infernix-demo)" /opt/infernix/bin/infernix-demo

FROM haskell:9.14.1-slim-bookworm

WORKDIR /srv/infernix

COPY --from=build /opt/infernix/bin/infernix /usr/local/bin/infernix
COPY --from=build /opt/infernix/bin/infernix-demo /usr/local/bin/infernix-demo
COPY web/dist web/dist

RUN mkdir -p web/dist

CMD ["infernix", "service"]
