ARG REPO=https://github.com/ElementsProject/lightning.git
ARG VERSION=v22.11.1
ARG USER=lightning
ARG DATA=/data

FROM debian:bullseye as downloader

ARG REPO
ARG VERSION

RUN set -ex \
	&& apt update \
	&& apt install -y -qq --no-install-recommends ca-certificates dirmngr wget

WORKDIR /opt

# Fetch and verify bitcoin (As per arch)
COPY ./fetch-scripts/fetch-bitcoin.sh .
RUN chmod 755 fetch-bitcoin.sh
RUN ./fetch-bitcoin.sh

FROM rust:1.66-slim-bullseye as builder

ARG VERSION
ARG REPO
RUN apt update && \
    apt install -qq -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        curl \
        dirmngr \
        gettext \
        git \
        gnupg \
        libpq-dev \
        zlib1g-dev \
        libsodium-dev \
        libsqlite3-dev \
        libgmp-dev \
        libtool \
        libffi-dev \
        python3 \
        python3-dev \
        python3-mako \
        python3-pip \
        protobuf-compiler \
        wget


WORKDIR /opt/lightningd
COPY . /tmp/lightning
RUN git clone --recursive $REPO . && \
    git checkout $VERSION

ARG DEVELOPER=0


RUN python3 -m pip install mako mrkd mistune==0.8.4

RUN rustup component add rustfmt

RUN ./configure --prefix=/tmp/lightning_install --enable-static --enable-rust 
RUN make -j$(nproc) DEVELOPER=${DEVELOPER}
RUN make install

WORKDIR /cln-init

RUN git clone --recursive https://github.com/runcitadel/cln-init .
RUN cargo build --release

FROM node:18-bullseye as node-builder

WORKDIR /rest-plugin

RUN git clone https://github.com/Ride-the-Lightning/c-lightning-REST.git . && \
    yarn

WORKDIR /sparko-plugin
RUN git clone --recursive https://github.com/fiatjaf/sparko.git . && \
    make spark-wallet/client/dist/app.js

FROM golang:1.17 as go-builder

RUN go get github.com/mitchellh/gox

WORKDIR /graphql-plugin
RUN git clone https://github.com/nettijoe96/c-lightning-graphql.git . && \
    go build -o c-lightning-graphql

COPY --from=node-builder /sparko-plugin /sparko-plugin
WORKDIR /sparko-plugin
RUN PATH=${HOME}/go/bin:$PATH make dist


FROM node:18-bullseye-slim as final

RUN apt update && apt install -y --no-install-recommends inotify-tools libpq5 libsodium23 openssl \
    && rm -rf /var/lib/apt/lists/*

ARG USER
ARG DATA


COPY --from=builder /lib /lib
COPY --from=builder /tmp/lightning_install/ /usr/local/
COPY --from=builder /cln-init/target/release/cln-initd /usr/bin/
COPY --from=builder /cln-init/target/release/cln-init-cli /usr/bin/
COPY --from=node-builder /rest-plugin /rest-plugin
COPY --from=go-builder /graphql-plugin/c-lightning-graphql /graphql-plugin
COPY --from=go-builder /sparko-plugin/dist /sparko-plugin
COPY --from=downloader /opt/bin /usr/bin
COPY ./scripts/docker-entrypoint.sh entrypoint.sh

RUN userdel -r node

RUN adduser --disabled-password \
    --home "$DATA" \
    --gecos "" \
    "$USER"


RUN chown -R $USER /sparko-plugin

USER $USER

ENV LIGHTNINGD_DATA=$DATA/.lightning
ENV LIGHTNINGD_RPC_PORT=9835
ENV LIGHTNINGD_PORT=9735
ENV LIGHTNINGD_NETWORK=bitcoin

EXPOSE 9735 9736 9835 9836 19735 19736 19835 19836

ENTRYPOINT  [ "./entrypoint.sh" ]
