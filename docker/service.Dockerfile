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
    && cabal build --builddir=/tmp/infernix-cabal exe:infernix \
    && install -D "$(cabal list-bin --builddir=/tmp/infernix-cabal exe:infernix)" /opt/infernix/bin/infernix

FROM haskell:9.14.1-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/infernix

COPY --from=build /opt/infernix/bin/infernix /usr/local/bin/infernix
COPY tools tools
COPY proto proto

RUN python3 -m pip install --break-system-packages --no-cache-dir -r /srv/infernix/tools/requirements.txt

RUN mkdir -p web/dist

CMD ["infernix", "service", "--port", "8080"]
