#!/bin/bash
# Interoperability of mqttd, redisd and syslogd with independent programs (Linux; needs python3; uses redis-cli and logger when they are installed).
# Not part of `make test`: it needs tools that not every machine has. Usage: tests/net2.sh
cd "$(dirname "$0")/.."
AC=./build/ac
mkdir -p build/net2
pass=0; fail=0
ok()  { echo "ok   $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
for e in mqttd_demo redisd_demo syslogd_demo; do $AC examples/$e.a -o build/net2/$e || { echo "cannot build $e"; exit 1; }; done
pids=""
trap 'kill $pids 2>/dev/null' EXIT

# ---- MQTT: a raw socket client written from the specification
P=$(port); build/net2/mqttd_demo $P > build/net2/mqttd.out 2>&1 & pids="$pids $!"; sleep 0.5
if python3 tests/net2_mqtt.py $P > build/net2/mqtt.out 2>&1; then ok "MQTT: raw client (connect, subscribe, QoS 0 / 1 / 2, retained, will, ping, \$SYS, malformed, MQTT 3.1)"; else bad "MQTT raw client"; cat build/net2/mqtt.out; fi

# ---- Redis: redis-cli
if command -v redis-cli > /dev/null; then
  P=$(port); build/net2/redisd_demo $P > build/net2/redisd.out 2>&1 & pids="$pids $!"; sleep 0.5
  rc() { redis-cli -p $P "$@"; }
  [ "$(rc PING)" = "PONG" ] && ok "redis-cli PING" || bad "redis-cli PING"
  [ "$(rc SET greeting 'hello there')" = "OK" ] && [ "$(rc GET greeting)" = "hello there" ] && ok "redis-cli SET / GET" || bad "redis-cli SET / GET"
  rc RPUSH l a b c > /dev/null; [ "$(rc LRANGE l 0 -1 | tr '\n' ' ')" = "a b c " ] && ok "redis-cli lists" || bad "redis-cli lists"
  rc HSET h f v > /dev/null; [ "$(rc HGETALL h | tr '\n' ' ')" = "f v " ] && ok "redis-cli hashes" || bad "redis-cli hashes"
  rc ZADD z 1 a 2.5 b > /dev/null; [ "$(rc ZRANGE z 0 -1 WITHSCORES | tr '\n' ' ')" = "a 1 b 2.5 " ] && ok "redis-cli sorted sets" || bad "redis-cli sorted sets"
  [ "$(rc EXPIRE greeting 100)" = "1" ] && [ "$(rc TTL greeting)" = "100" ] && ok "redis-cli EXPIRE / TTL" || bad "redis-cli EXPIRE / TTL"
  rc FOOBAR 2>&1 | grep -q "unknown command" && ok "redis-cli error reply" || bad "redis-cli error reply"
  printf 'SET a 1\r\nSET b 2\r\nINCR a\r\nGET b\r\n' | redis-cli -p $P --pipe 2>&1 | grep -q "errors: 0, replies: 4" && ok "redis-cli --pipe" || bad "redis-cli --pipe"
  (timeout 2 redis-cli -p $P SUBSCRIBE news > build/net2/sub.out 2>&1 &) ; sleep 0.4; rc PUBLISH news "hello subscribers" > /dev/null; sleep 0.3
  grep -q "hello subscribers" build/net2/sub.out && ok "redis-cli SUBSCRIBE / PUBLISH" || bad "redis-cli SUBSCRIBE / PUBLISH"
else
  echo "skip redis-cli is not installed"
fi

# ---- syslog: util-linux logger
if command -v logger > /dev/null; then
  P=$(port); rm -f build/net2/sd.log*; build/net2/syslogd_demo $P build/net2/sd.log > build/net2/syslogd.out 2>&1 & pids="$pids $!"; sleep 0.5
  logger -n 127.0.0.1 -P $P -d -t mytag -p local3.warning "hello over UDP rfc3164"
  logger -n 127.0.0.1 -P $P -d --rfc5424 -t mytag --id=4711 "hello over UDP rfc5424"
  logger -n 127.0.0.1 -P $P -T --rfc5424 -t tcptag --sd-id "origin@32473" --sd-param 'ip="10.0.0.1"' "hello over TCP rfc5424"
  logger -n 127.0.0.1 -P $P -T -t tcptag "hello over TCP rfc3164"
  sleep 0.5
  for want in "mytag: hello over UDP rfc3164" "mytag\[4711\]: hello over UDP rfc5424" "tcptag: hello over TCP rfc5424" "tcptag: hello over TCP rfc3164"; do
    grep -q "$want" build/net2/sd.log && ok "logger: $want" || bad "logger: $want"
  done
else
  echo "skip logger is not installed"
fi
echo "passed: $pass, failed: $fail"
[ $fail -eq 0 ]
