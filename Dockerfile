ARG REPO=https://github.com/ElementsProject/lightning.git
ARG VERSION=master
ARG USER=lightning
ARG DATA=/data

FROM debian:bullseye-slim as downloader

ARG REPO
ARG VERSION

RUN set -ex \
	&& apt-get update \
	&& apt-get install -qq --no-install-recommends ca-certificates dirmngr wget

WORKDIR /opt

# Fetch and verify bitcoin (As per arch)
COPY ./fetch-scripts/fetch-bitcoin.sh .
RUN chmod 755 fetch-bitcoin.sh
RUN ./fetch-bitcoin.sh

FROM debian:bullseye-slim as builder

ARG VERSION
ARG REPO

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates autoconf \
    automake build-essential git libtool python python3 python3-mako \
    wget gnupg dirmngr git gettext libgmp-dev libsqlite3-dev net-tools \
    zlib1g-dev unzip tclsh git libsodium-dev libpq-dev valgrind python3-pip \
    valgrind libpq-dev shellcheck cppcheck \
    libsecp256k1-dev jq \
    python3-setuptools \
    python3-dev

ARG DEVELOPER=0

WORKDIR /opt
RUN git clone --recurse-submodules $REPO lightning

WORKDIR /opt/lightning

RUN curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python3 -
RUN /root/.poetry/bin/poetry install

RUN mkdir -p /tmp/lightning_install && \
    ls -la /tmp && \
    git checkout $VERSION && \
    echo "Configuring" && \
    ./configure --prefix=/tmp/lightning_install \
        --enable-static && \
    echo "Building" && \
    make -j$(nproc) DEVELOPER=${DEVELOPER} && \
    echo "installing" && \
    make install && \
    ls -la  /tmp/lightning_install

FROM node:17-bullseye as node-builder

WORKDIR /rest-plugin

RUN git clone https://github.com/runcitadel/c-lightning-REST.git -b master . && \
    yarn

WORKDIR /sparko-plugin
RUN git clone --recursive https://github.com/fiatjaf/sparko.git . && \
    make spark-wallet/client/dist/app.js

FROM golang:1.17 as go-builder

RUN go get github.com/mitchellh/gox


RUN groupadd -r app && useradd -r -m -g app app

USER app

WORKDIR /graphql-plugin
RUN git clone https://github.com/nettijoe96/c-lightning-graphql.git . && \
    go build -o c-lightning-graphql

COPY --from=node-builder /sparko-plugin /sparko-plugin
WORKDIR /sparko-plugin
RUN PATH=${HOME}/go/bin:$PATH make dist


FROM node:17-bullseye-slim as final

RUN apt-get update && apt-get install -y --no-install-recommends inotify-tools libpq5 libsodium23 openssl \
    && rm -rf /var/lib/apt/lists/*

ARG USER
ARG DATA


COPY --from=builder /lib /lib
COPY --from=builder /tmp/lightning_install/ /usr/local/
COPY --from=node-builder /rest-plugin /rest-plugin
COPY --from=go-builder /graphql-plugin/c-lightning-graphql /opt/lightningd/plugins/graphql-plugin
COPY --from=go-builder /sparko-plugin/dist /opt/lightningd/plugins/sparko-plugin
COPY --from=downloader /opt/bin /usr/bin
COPY ./scripts/docker-entrypoint.sh entrypoint.sh

RUN userdel -r node

RUN adduser --disabled-password \
    --home "$DATA" \
    --gecos "" \
    "$USER"
USER $USER 

ENV LIGHTNINGD_DATA=$DATA/.lightning
ENV LIGHTNINGD_RPC_PORT=9835
ENV LIGHTNINGD_PORT=9735
ENV LIGHTNINGD_NETWORK=bitcoin

EXPOSE 9735 9736 9835 9836 19735 19736 19835 19836

ENTRYPOINT  [ "./entrypoint.sh" ]
