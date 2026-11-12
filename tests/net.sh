#!/bin/bash
# Interoperability of the networking modules with independent implementations (Linux x86-64; needs python3, curl and openssl;
# the python packages websockets and requests are used when they are installed, else those checks are skipped):
#   the A hub (wshub: WebSocket, wss, HTTP, SSE, JSON-RPC) is used by python websockets, curl, requests and raw sockets (RFC 6455 violations);
#   the A client (ws_cat) talks to python websocket servers (plain, deflate, subprotocols, Origin, wss with certificate checks);
#   the blocking wss server (websocket.acceptTls) is used by a python wss client.
# Usage: tests/net.sh        (pip install websockets requests   to enable all checks; PYTHONPATH works too)
cd "$(dirname "$0")/.."
for tool in openssl curl python3; do
    command -v $tool >/dev/null || { echo "net tests skipped (no $tool)"; exit 0; }
done
AC=./build/ac
W=build/nettest
rm -rf $W && mkdir -p $W
$AC examples/hub_demo.a -o $W/hub_demo || exit 1
$AC examples/ws_cat.a -o $W/ws_cat || exit 1
$AC examples/wss_echo.a -o $W/wss_echo || exit 1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -keyout $W/key.pem -out $W/cert.pem 2>/dev/null
python3 tests/net_interop.py $W/hub_demo $W/ws_cat $W/wss_echo $W $W/cert.pem $W/key.pem
