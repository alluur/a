#!/bin/bash
# TLS 1.3 against independent implementations (Linux x86-64; needs openssl, curl and python3):
#   * httpsd (the A server, lib/tls.a) is fetched by curl, openssl s_client (all three cipher suites) and Python's ssl module
#   * http_get (the A client) fetches from openssl s_server with RSA, P-256 and P-384 certificates, and refuses an untrusted one
# Usage: tests/https.sh
cd "$(dirname "$0")/.."
for tool in openssl curl python3; do
    command -v $tool >/dev/null || { echo "https tests skipped (no $tool)"; exit 0; }
done
AC=./build/ac
W=build/httpstest
rm -rf $W && mkdir -p $W/www
$AC examples/httpsd.a -o $W/httpsd || exit 1
$AC examples/http_get.a -o $W/http_get || exit 1
fail=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

echo "<h1>hello from A</h1>" > $W/www/index.html
head -c 700000 /dev/urandom > $W/www/big.bin
big=$(sha256sum < $W/www/big.bin | cut -d' ' -f1)

mkcert() { # name type
    local d=$W/$1
    mkdir -p $d
    if [ "$2" = rsa ]; then
        openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -keyout $d/key.pem -out $d/cert.pem 2>/dev/null
    else
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:$2 -nodes -days 30 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -keyout $d/key.pem -out $d/cert.pem 2>/dev/null
    fi
}
mkcert rsa rsa; mkcert p256 prime256v1; mkcert p384 secp384r1

wait_port() { for i in $(seq 1 50); do (echo > /dev/tcp/127.0.0.1/$1) 2>/dev/null && return 0; sleep 0.1; done; return 1; }

# ---- the A server ------------------------------------------------------------------------------------------------------------------
for k in rsa p256 p384; do
    port=$((18440 + RANDOM % 400))
    $W/httpsd $W/$k/cert.pem $W/$k/key.pem $port $W/www > $W/httpsd.log 2>&1 &
    pid=$!
    if ! wait_port $port; then bad "httpsd ($k) did not start"; kill $pid 2>/dev/null; continue; fi
    got=$(curl -s --cacert $W/$k/cert.pem --tlsv1.3 https://localhost:$port/)
    [ "$got" = "<h1>hello from A</h1>" ] && ok "curl <- httpsd ($k)" || bad "curl <- httpsd ($k): $got"
    got=$(curl -s --cacert $W/$k/cert.pem --tlsv1.3 https://localhost:$port/big.bin | sha256sum | cut -d' ' -f1)
    [ "$got" = "$big" ] && ok "curl 700 KB <- httpsd ($k)" || bad "curl 700 KB <- httpsd ($k)"
    for suite in TLS_AES_128_GCM_SHA256 TLS_AES_256_GCM_SHA384 TLS_CHACHA20_POLY1305_SHA256; do
        out=$(printf 'GET / HTTP/1.0\r\n\r\n' | openssl s_client -connect localhost:$port -tls1_3 -ciphersuites $suite -CAfile $W/$k/cert.pem -verify_return_error -quiet 2>&1)
        echo "$out" | grep -q "hello from A" && ok "openssl s_client $suite <- httpsd ($k)" || bad "openssl s_client $suite <- httpsd ($k): $out"
    done
    got=$(python3 - $port $W/$k/cert.pem <<'PY'
import socket, ssl, sys
ctx = ssl.create_default_context(cafile=sys.argv[2]); ctx.minimum_version = ssl.TLSVersion.TLSv1_3
with socket.create_connection(("localhost", int(sys.argv[1]))) as s:
    with ctx.wrap_socket(s, server_hostname="localhost") as t:
        t.sendall(b"GET /index.html HTTP/1.0\r\n\r\n")
        data = b""
        while True:
            d = t.recv(4096)
            if not d: break
            data += d
        print(t.version(), t.cipher()[0], b"hello from A" in data)
PY
)
    echo "$got" | grep -q "TLSv1.3.*True" && ok "python ssl <- httpsd ($k): $got" || bad "python ssl <- httpsd ($k): $got"
    # a client that does not trust the certificate must be refused by curl, and the server must survive
    curl -s --cacert $W/p256/cert.pem https://localhost:$port/ >/dev/null 2>&1 && [ $k != p256 ] && bad "curl accepted an untrusted certificate ($k)"
    got=$(curl -s --cacert $W/$k/cert.pem https://localhost:$port/ 2>&1)
    [ "$got" = "<h1>hello from A</h1>" ] && ok "httpsd ($k) still serving after a refused client" || bad "httpsd ($k) died after a refused client"
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
done

# ---- the A client ------------------------------------------------------------------------------------------------------------------
for k in rsa p256 p384; do
    for suite in TLS_AES_128_GCM_SHA256 TLS_AES_256_GCM_SHA384 TLS_CHACHA20_POLY1305_SHA256; do
        port=$((18840 + RANDOM % 400))
        (cd $W/www && openssl s_server -accept $port -cert ../$k/cert.pem -key ../$k/key.pem -tls1_3 -ciphersuites $suite -WWW > ../s_server.log 2>&1) &
        pid=$!
        wait_port $port || { bad "s_server ($k) did not start"; kill $pid; continue; }
        got=$(SSL_CERT_FILE=$W/$k/cert.pem $W/http_get https://localhost:$port/index.html 2>&1 | tail -2 | head -1)
        [ "$got" = "<h1>hello from A</h1>" ] && ok "http_get <- openssl s_server ($k, $suite)" || bad "http_get <- openssl s_server ($k, $suite): $got"
        kill $pid 2>/dev/null; wait $pid 2>/dev/null
    done
done
port=$((19300 + RANDOM % 400))
(cd $W/www && openssl s_server -accept $port -cert ../rsa/cert.pem -key ../rsa/key.pem -tls1_3 -WWW > ../s_server.log 2>&1) &
pid=$!
wait_port $port
got=$(SSL_CERT_FILE=$W/p256/cert.pem $W/http_get https://localhost:$port/index.html 2>&1 | head -1)
[ "$got" = "error: the certificate is self signed (not trusted)" ] && ok "http_get refuses an untrusted certificate" || bad "http_get untrusted: $got"
got=$(SSL_CERT_FILE=$W/rsa/cert.pem $W/http_get https://127.0.0.1:$port/index.html 2>&1 | tail -2 | head -1)
[ "$got" = "<h1>hello from A</h1>" ] && ok "http_get with an IP address SAN" || bad "http_get with an IP address SAN: $got"
got=$(SSL_CERT_FILE=$W/p256/cert.pem $W/http_get --insecure https://localhost:$port/index.html 2>&1 | tail -2 | head -1)
[ "$got" = "<h1>hello from A</h1>" ] && ok "http_get --insecure" || bad "http_get --insecure: $got"
kill $pid 2>/dev/null; wait $pid 2>/dev/null
[ $fail = 0 ] && echo "https tests passed" || { echo "https tests FAILED"; exit 1; }
