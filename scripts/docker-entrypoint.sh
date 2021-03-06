#!/usr/bin/env bash

: "${EXPOSE_TCP:=false}"

networkdatadir="${LIGHTNINGD_DATA}/${LIGHTNINGD_NETWORK}"

cd "${LIGHTNINGD_DATA}"

if [ "$EXPOSE_TCP" == "true" ]; then
    set -m
    lightningd "$@" &

    echo "C-Lightning starting"
    while read -r i; do if [ "$i" = "lightning-rpc" ]; then break; fi; done \
    < <(inotifywait -e create,open --format '%f' --quiet "${networkdatadir}" --monitor)
    echo "C-Lightning started"
    echo "C-Lightning started, RPC available on port $LIGHTNINGD_RPC_PORT"

    socat "TCP4-listen:$LIGHTNINGD_RPC_PORT,fork,reuseaddr" "UNIX-CONNECT:${networkdatadir}/lightning-rpc" &
    fg %-
else
    exec lightningd --plugin=/rest-plugin/plugin.js --plugin=/sparko-plugin/sparko_linux_$(dpkg --print-architecture) --network="${LIGHTNINGD_NETWORK}" "$@"
fi
