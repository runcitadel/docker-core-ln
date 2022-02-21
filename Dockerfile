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

FROM node:17-bullseye-slim as builder

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
RUN pip3 install mrkd wheel mistune==0.8.4

ARG DEVELOPER=0

WORKDIR /opt
RUN git clone --recurse-submodules $REPO && \
    cd lightning && \
    ls -la && \
    mkdir -p /tmp/lightning_install && \
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

WORKDIR /rest-plugin

RUN git clone https://github.com/runcitadel/c-lightning-REST.git . && \
    yarn

FROM node:17-bullseye-slim as final

RUN apt-get update && apt-get install -y --no-install-recommends inotify-tools libpq5 libsodium23 openssl \
    && rm -rf /var/lib/apt/lists/*

ARG USER
ARG DATA


COPY --from=builder /lib /lib
COPY --from=builder /tmp/lightning_install/ /usr/local/
COPY --from=builder /rest-plugin /rest-plugin
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
