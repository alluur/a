# Networking

A has a small networking stack written in A itself: sockets (`net`), addresses (`netaddr`), name lookup (`dns`), buffered connections
(`conn`), what the system knows about the network (`netif`), everyday tools (`netutil`) and packet building (`packet`, `rawnet`). The same
code runs on Linux, Android and Windows, and there is nothing to install: the modules are built into the compiler. This chapter is the
plumbing; [the next chapter](#chap-http-websocket-tls) builds HTTP, WebSocket and TLS on top of it.

In this chapter:

* which module to use for which job;
* IPv4, IPv6, MAC addresses and subnets (`netaddr`);
* TCP and UDP sockets, waiting for many sockets at once, and the buffered `conn` connections;
* errors and time limits;
* DNS, the system's network tables, ping and friends;
* building and reading Ethernet, ARP, IP, ICMP, UDP and TCP packets.

## Which module do I use?

| I want to ... | Use |
|---|---|
| parse, print or classify an IP, MAC or subnet; look up a port name | `netaddr` |
| open a TCP connection, listen for clients, send UDP datagrams | `net` |
| wait for several sockets at once | `net.poll`, or `conn.Poller` |
| read lines or exact byte counts from a socket, and write in big pieces | `conn` |
| turn a host name into an IPv4 address | `net.resolve` |
| ask for MX, TXT, SRV ... records, or run a DNS server of my own | `dns` |
| list interfaces, routes, the ARP cache, open sockets | `netif` |
| ping, test a port, send Wake-on-LAN, ask an NTP server | `netutil` |
| build or take apart Ethernet, ARP, IP, ICMP, UDP, TCP packets; write `.pcap` files | `packet` |
| send or capture raw Ethernet frames | `rawnet` (needs root) |
| fetch a web page, call a REST API, serve HTTP | `http` (next chapter) |
| exchange messages with a browser in both directions | `websocket` (next chapter) |
| encrypt a connection | `tls`, usually through `http` (next chapter) |

The modules form layers. Everything is built on `net`; `packet` and `netaddr` are pure computation and need no operating system at all.

```text
http  websocket          protocols
conn  tls                connections (buffering, encryption)
net   dns   netutil      sockets, names, tools
netif rawnet packet      the system's tables, raw frames, packets
netaddr                  numbers and text
```

## How the samples in this chapter work

A program that talks to a network needs a partner, and a book sample has to run alone and print the same thing every time. So the
samples talk to themselves over the loopback address `127.0.0.1`, which never leaves the computer, and follow three rules:

* **No fixed ports.** A server asks for port `0`, which means "any free port", and reads the answer with `net.localPort`. Two samples
  can then run at the same time and a port that is already in use never gets in the way.
* **One process when possible.** A TCP server that is listening already accepts connections: the system completes the handshake while
  the connection waits in the *backlog*. So a program can `listen`, `connect` and only then `accept`, and play both sides in one
  thread, as long as each step does not wait for a reply that only a later step produces.
* **Two processes when a call blocks.** When one side has to sit in a blocking call (a server in `accept`, a client waiting for a
  response), the samples start the server with `fork` from the `cunistd` module. The server process inherits the listening socket,
  so the port exists before the client starts. These samples are marked `linux-only`: Windows has no `fork`.

::: note

A thread (module `thread`) would also work as the "other side", but A's allocator is not thread safe, so a server thread that allocates
(an HTTP handler always does) can damage the heap while the main thread allocates as well. A second process has no such problem, and a
real server is usually a separate program anyway: see `examples/net_server.a` and `examples/net_client.a`.

:::

## Addresses: `netaddr`

`netaddr` is the module for numbers and text: it needs no network. An IPv4 address is one `int` in host order, so `192.168.1.77` is
`0xC0A8014D`. Functions that make text return a new heap string.

### IPv4 addresses

`ipParse` turns text into a number (`-1` if it is not an address), `ipToText` does the reverse and `ipFromBytes` builds one from four
numbers. The `is...` functions classify an address.

{{sample net/addr_ipv4}}

**What to notice.**

* `ipParse` is strict: three parts, a trailing space or a number above 255 give `-1`. (It is the same function as `net.parseIp`, so it
  also accepts the word `localhost`.)
* The class letter is the old classful scheme (A to E). It is rarely useful today but cheap to print.
* The wire uses network byte order, which is big endian. `htonl` / `htons` swap the bytes on this little-endian machine; `ntohl` /
  `ntohs` are the same swap in the other direction.

### Subnets

A subnet is written `address/prefix`: the prefix is the number of leading one bits of the netmask. `parseCidr` splits the text,
and the other functions answer the questions an administrator asks.

{{sample net/addr_subnet}}

**What to notice.** `hostCount(26)` is 62, which is 2^6 minus the network and the broadcast address. `/31` gives 2 (point-to-point
links) and `/32` gives 1. `prefixFromMask` returns `-1` for a mask that is not a run of ones, and `parseCidr` returns `false` for a
prefix above 32.

### MAC and IPv6 addresses

A MAC address is six bytes in a `char[6]`; an IPv6 address is sixteen bytes in network order in a `char[16]`. Neither fits in an `int`,
so the functions work on buffers you provide.

{{sample net/addr_mac_ipv6}}

**What to notice.**

* `ip6ToText` shortens the longest run of zero groups to `::` and writes the groups without leading zeros, like every modern tool.
  An IPv4 address inside IPv6 (`::ffff:10.1.2.3`) is printed in hexadecimal groups, not with dots.
* IPv6 addresses can be parsed and printed, but **sockets are IPv4 only**: `net` cannot connect to or listen on an IPv6 address.

### Ports, host names and the Internet checksum

{{sample net/addr_misc}}

**What to notice.** `serviceName` knows about 40 well-known ports and returns `null` for any other port, so check before you print it.
The Internet checksum (RFC 1071) is what IP, ICMP, UDP and TCP use: add up all 16-bit words, fold the carries, invert. Data that carries
its correct checksum adds up to zero, which is how a receiver checks it. You will meet it again in the packet section.

## TCP sockets: `net`

A TCP connection is a reliable stream of bytes between two programs. In `net` a socket is an `int` handle. Every function returns a
**negative number on failure** (`net.listen`, `net.connect`, `net.accept`) or tells you in its own way (`net.recv` returns `0` at the
end of the data). All calls **block** until they are done; the section on errors and time limits shows how to bound the waiting.

| Function | What it does |
|---|---|
| `net.listenOn(host, port, backlog)` | start a server on an address (`"127.0.0.1"`, `"0.0.0.0"`); `net.listen(port, backlog)` uses every interface |
| `net.accept(server)` | wait for the next client; returns its handle |
| `net.connect(host, port)` | connect to a server; `host` may be a name |
| `net.send(h, buf, n)` | send all `n` bytes, returns `n` or a negative number; `net.sendText(h, text)` for a string |
| `net.recv(h, buf, max)` | at least one and at most `max` bytes; `0` when the peer closed; negative on error or time out |
| `net.recvLine(h, buf, max)` | one line without its `\n` or `\r\n`; `-1` when the connection ended before any byte |
| `net.close(h)` | close a socket |
| `net.localPort(h)`, `net.peer(h, &ip, &port)`, `net.localIp(h)` | the addresses of a socket |

### A server and a client in one program

{{sample net/tcp_echo}}

**What to notice.**

* `listenOn("127.0.0.1", 0, 4)` binds only the loopback interface, so nobody else can connect. `net.listen(port, backlog)` binds
  `0.0.0.0`, which is what a public server wants. The last argument is the backlog: how many connections may wait for `accept`.
* `listenOn` needs an address in numbers (or `localhost`); it does not look names up. `connect` does.
* The client's `connect` returns before the server calls `accept`: the system already holds the connection. That is what lets one
  thread play both roles here.
* After the client closed its socket the server's `recv` returns `0`. Zero never means an error: it is the end of the stream.

### TCP is a stream, not a series of messages

TCP does not remember where your `send` calls began and ended. Three writes of 1000 bytes can arrive as one read of 3000 bytes, or as
many small ones. A program must therefore either know how many bytes to expect, or mark the end of a message itself.

{{sample net/tcp_stream}}

**What to notice.** `net.send` loops until every byte is handed to the system, so you do not need a loop for sending, but you do for
receiving: `net.recv` returns whatever is available, which can be fewer bytes than you asked for. The `recvAll` function in the sample
is the usual loop. It stops early only when `recv` returns `0` or a negative number.

### Framing: one line per message

The simplest way to cut a stream into messages is a text protocol with one line per message. `net.recvLine` reads up to the newline and
removes it (and a `\r` before it, so `telnet`-style clients work too).

{{sample net/tcp_protocol}}

**What to notice.**

* The "server" in this sample is the function `serve`, called between the client's send and receive. In a real program it would
  loop over `accept` in its own process; the next sample shows that shape.
* `recvLine` never overruns your buffer, but a line longer than `max - 1` is **split**: the rest comes out as the next "line". Size the
  buffer for the longest line you accept, and treat anything longer as an error.
* Protocols with binary data usually send a length first (`readExact` in `conn`, below, is made for that).

### Closing one direction: `shutdown`

`net.close` ends the conversation in both directions. `net.shutdown(h, 1)` says "I will send no more" while the other direction stays
open. The peer sees the end of the data (`recv` returns `0`) and can still answer. This is how a client marks the end of a request that
has no length in front of it.

{{sample net/tcp_halfclose}}

**What to notice.** The server reads until `recv` returns `0`, then answers, then shuts down its own sending side so that the client's
last `recv` returns `0` too. `net.shutdown(h, 0)` stops reading and `net.shutdown(h, 2)` stops both.

### Who is on the other end?

{{sample net/tcp_peer}}

**What to notice.** `net.peer` gives the address and port of the other side, `net.localIp` the address of your own side (the
interface the connection uses). The socket options (`setNoDelay` to send small packets at once, `setKeepAlive`, `setReuse`) return
`true` when the system accepted them. Servers set `SO_REUSEADDR` automatically on Linux, so restarting a server does not wait for old
connections to time out.

### A server in its own process

A real server loops: accept a client, serve it, accept the next. With one process that loop blocks everything else, so the sample
puts the server in a child process made by `fork`.

{{sample net/tcp_fork_server}}

**What to notice.**

* The program listens **before** `fork`, so the port exists when the child starts and the parent cannot connect too early. The parent
  closes its copy of the listening socket; the child keeps serving.
* `fork` returns `0` in the child and the child's process id in the parent. `waitpid` collects the exit code, which is in bits 8 to 15
  of the status. Use `_exit` in the child so it does not run the parent's cleanup.
* This server handles one client at a time. For many clients in one thread use `net.poll` or a `conn.Poller` (below), or fork a child
  per connection.

### Sending a lot of data

{{sample net/tcp_bulk}}

**What to notice.** The system keeps only a limited amount of unread data for a socket. When that is full, `net.send` **blocks** until
the reader makes room, which is why the sender here is a separate process: with both sides in one thread, a large send to a socket
that nobody reads yet would wait forever. A slow reader slows the writer down (flow control); nothing is lost.

### Talking to the real Internet

The loopback samples run anywhere. A program for the Internet differs in three ways: it uses names instead of numbers, it must expect
failure, and it should bound every wait. This sample only compiles (it needs a network), but it is the template for a client:

{{sample net/internet_client}}

**What to notice.** `net.httpGet` is the smallest possible HTTP client (HTTP/1.0, no redirects, no TLS); the `http` module of the next
chapter does the real job. `net.resolve` asks `/etc/hosts` first and then the DNS servers of the system (and, as a last resort,
`8.8.8.8` and `1.1.1.1`). With no network that can take several seconds, because every server is tried twice with a two-second time limit.

## UDP datagrams

UDP is the opposite of TCP: no connection, no stream, no promise. Each `sendTo` sends one datagram to an address and port; each
`recvFrom` receives one, together with the address of the sender. Datagrams can be lost, duplicated or arrive in another order (on the
loopback interface they do not, but real networks do).

### Two sockets exchanging datagrams

{{sample net/udp_pair}}

**What to notice.**

* `udpBind(0)` makes a socket that receives on any free port. `udpSocket()` makes one without a port; the system assigns one at the
  first `sendTo`.
* There is no `connect` and no `accept`. The sender's address comes back from `recvFrom`, so a server can answer anyone with the
  address it just learned.
* `ip` and `port` may be `null` if you do not care who sent the datagram.

### Datagrams keep their boundaries

{{sample net/udp_boundaries}}

**What to notice.** Three sends are three receives, even a datagram of zero bytes. A buffer that is smaller than the datagram
**truncates** it silently: the rest is thrown away. Give `recvFrom` a buffer for the largest datagram your protocol allows (a datagram
on Ethernet is at most about 1472 bytes of data without fragmentation).

### Lost datagrams: time out and ask again

A program that waits for a UDP answer must not wait forever, because the request or the answer may be gone. `net.setTimeout` gives the
socket a time limit, and `recvFrom` then returns `-1` when it expires. Retrying is then the program's job: DNS clients, NTP clients and
many other UDP protocols do exactly this.

{{sample net/udp_retry}}

### Broadcast and multicast

A broadcast reaches every host on the local network; a multicast reaches those that joined a group. Both are UDP only. The sample
compiles but does not run, because it depends on the network the computer is connected to.

{{sample net/udp_broadcast}}

**What to notice.** Sending to `255.255.255.255` needs `setBroadcast(h, true)`. A receiver joins a group (an address from
`224.0.0.0` to `239.255.255.255`) with `joinMulticast` after binding the port. `udpBind` binds at once, so only one program on a
computer can receive on a given port.

## Waiting for many sockets: `poll`

A server with many clients cannot sit in `recv` on one of them. `net.poll` waits for several sockets at once and says which are ready.
It takes arrays of handles and events and fills an array of results.

| Event | Meaning |
|---|---|
| `net.READABLE` | `recv` will not block: data, a new client (for a listening socket) or the end of the stream |
| `net.WRITABLE` | `send` will not block for a moment |
| `net.FAILED`, `net.HUNGUP` | only in the results: the socket has an error, or the peer is gone |

{{sample net/poll_ready}}

**What to notice.**

* `net.poll(handles, events, ready, n, ms)` returns how many sockets are ready, `0` when `ms` milliseconds passed with nothing to
  report, and a negative number on error. `ms < 0` waits forever and `ms = 0` only looks. At most 256 sockets are watched per call.
* `net.waitReadable(h, ms)` and `net.waitWritable(h, ms)` are the one-socket versions. They are the way to put a time limit on
  `accept`: wait until the listening socket is readable, then call `accept`.
* A socket whose peer has closed is **readable**: the `recv` returns `0`. That is how a server notices a client that left.
* A listening socket is readable when a client waits in the backlog.

::: note

The `net` module has no "non-blocking mode" switch. The two tools for work that must not wait are `poll` with a short time and the
time limits of the next sections. `net.connectTimeout` uses a non-blocking connect inside, so connecting can be bounded as well.

:::

## Buffered connections: `conn`

`net.recv` returns arbitrary pieces, and `net.send` makes one system call per call. The `conn` module wraps a socket in a
`conn.Connection` with a read buffer and a write buffer, so a program can ask for lines or exact byte counts and write many small
pieces that leave as one packet. `conn.Listener` accepts connections, `conn.open` makes one, and `conn.Poller` serves many at once.

| Method of `conn.Connection` | What it does |
|---|---|
| `readLine(buf, max)` | one line without its line end; `-1` at the end of the connection |
| `readExact(buf, n)` | exactly `n` bytes (fewer only when the connection ends) |
| `read(buf, max)`, `readByte()` | whatever is available; one byte or `-1` |
| `writeLine(text)`, `writeText(text)`, `write(buf, n)` | put data in the write buffer |
| `flush()` | send the buffer now (also done by `close()`) |
| `readable(ms)`, `buffered()` | would a read block? how many bytes are already waiting |
| `peer(&ip, &port)`, `localPort()`, `setTimeout(ms)`, `bytesIn`, `bytesOut` | information and limits |

{{sample net/conn_lines}}

**What to notice.**

* Nothing is sent until `flush()` (or until 4096 bytes have collected, or `close()`). Forgetting `flush()` before waiting for the
  answer is the classic bug: both sides wait for each other.
* The two lines and the ten digits came from the read buffer without further system calls: `buffered()` counts what is already there.
* `readLine` returns `-1` at the end of the connection, and `readExact` returns fewer bytes than asked for only when the connection
  ends (or a time limit runs out).

### One thread, many clients: `conn.Poller`

A `Poller` is a set of connections with a tag each. `wait(ms)` returns how many are readable, and `readyTag(i)` tells you which.

{{sample net/conn_poller}}

**What to notice.** The server loop is "wait, serve everything that is ready, repeat". A `Poller` holds up to 128 entries; remove a
connection with `remove` when it is done. `examples/chat_server.a` is the bigger version of this: a chat for many clients in one
thread.

## Errors and time limits

Network code fails more often than anything else, so every function has a way to say so. The conventions are the same everywhere:

| Call | Failure looks like |
|---|---|
| `net.connect`, `net.connectTimeout`, `net.listen`, `net.listenOn`, `net.accept`, `net.udpBind` | a negative handle |
| `net.send`, `net.sendTo` | a negative number (a write to a peer that has gone away returns `-1`; it does **not** kill the program with a signal) |
| `net.recv` | `0` = the peer closed, negative = error or time out |
| `net.recvFrom` | `-1` on error or time out |
| `net.resolve`, `net.parseIp` | `-1` |
| `conn.open`, `Listener.accept` | `null` |
| `Connection.readLine` | `-1` (the end of the connection, and also a time out) |

A program that ignores a failure usually crashes a few lines later, so check the first call that can fail: `connect` before `send`,
`open` before `->readLine`.

### Connection refused

{{sample net/err_refused}}

**What to notice.** Connecting to a port nobody listens on fails at once with a negative handle (the system answers "refused"). A
black-holed address, on the other hand, can take minutes: that is what `connectTimeout` is for. Only one socket can listen on a port;
the second `listenOn` fails.

### Time limits

Nothing in the network promises that the other side ever answers, so every wait that a user would notice should have a limit:

| Where | How |
|---|---|
| a socket | `net.setTimeout(h, ms)`: every `recv` and `send` on it gives up after `ms` (`0` = wait forever) |
| accepting | `net.waitReadable(listener, ms)` first, or `conn.Listener.accept(ms)` |
| connecting | `net.connectTimeout(host, port, ms)` or `conn.open(host, port, ms)` |
| several sockets | the `ms` argument of `net.poll` |
| a UDP exchange | `setTimeout` plus a retry loop |
| a DNS name | `net.resolve` and `dns.query` wait two seconds per try (below) |

The `http` module sets 15 seconds on its connections, `conn.open` sets three times the connect time on reads and writes, and
`tls.connect` gives the handshake 10 seconds. Plain `net.connect` has **no** limit of its own.

{{sample net/err_timeouts}}

**What to notice.** `recv` has three kinds of result: data, `0` and a negative number, and a program that treats them all as "the
connection is over" will mistake a slow server for a closed one. `waitReadable` is also how you test for a waiting client without
blocking.

{{sample net/conn_timeouts}}

**What to notice.** `Listener.accept(100)` returns `null` after 100 ms without a client, and `openRetry` tries several times with a
pause. `Connection.readLine` returns `-1` both at the end of the connection and when its time limit ran out; if you must tell them
apart, use `net.waitReadable` on `handle()` before reading.

## Names: DNS

`net.resolve(name)` is all most programs need: it knows IPv4 addresses, `localhost`, the entries of `/etc/hosts` and, failing those,
asks a DNS server over UDP (the servers in `/etc/resolv.conf`, then `8.8.8.8` and `1.1.1.1`; on Windows the system resolver).
`net.connect` calls it for you. The `dns` module goes further: it asks for any record type (`A`, `NS`, `CNAME`, `SOA`, `PTR`, `MX`,
`TXT`, `AAAA`, `SRV`), and it exposes the packets, so you can write a DNS server, or test a client without a network.

### The messages

A DNS message is a 12-byte header, then the question, then the answer records. Names are written as length-prefixed labels
(`3www7example3org0`), and an answer usually points back to the name in the question with a two-byte pointer starting with `0xC0`.

{{sample net/dns_message}}

**What to notice.**

* `dns.buildQuery(name, type, id, buf)` returns the length, or `-1` for a bad name. A failing call may already have written into `buf`,
  so use a fresh buffer for the next query.
* The first two bytes are the message id. `parseReply` returns `-1` for a reply whose id does not match: that is how a late answer to
  an old question is ignored.
* A reply with the response code 3 ("no such name") is not an error: it is `0` records and `dns.rcode()` is `3`.

### The record types

`parseReply` decodes the records into `dns.Record` objects. The sample builds a reply by hand with five records, so you can see the
byte layout, and reads it back:

{{sample net/dns_records}}

**What to notice.** `recordText` formats every type: `A` as a dotted address, `MX` as "preference host", `SRV` as "priority weight
port host", `TXT` in quotes. A packet that is cut short is refused (`-1`) instead of being read past its end, which matters because
DNS replies come from the network.

### A client against a server of your own

`dns.query` blocks until a server answers, so the sample runs a tiny DNS server in a child process. It reads the name from each query
with `dns.readName` and answers with `dns.buildReply`.

{{sample net/dns_fake_server}}

**What to notice.** `dns.setServer(ip, port)` replaces the servers of the system, and `net.setDns` does the same for `net.resolve`.
`lookupA` does no query at all for a text that is already an address. `dns.query` returns the number of answers, `-1` if nobody answered
and `0` with `rcode()` `3` for a name that does not exist.

### Real lookups

Against the real DNS the sample only compiles, because it needs a network and its answers change:

{{sample net/dns_lookup}}

## What the system knows: `netif`

`netif` reads the tables of the operating system: the interfaces (like `ifconfig` or `ip addr`), the ARP cache, the routes, the open TCP
and UDP sockets (like `netstat`) and the DNS servers. Linux and Android read `/proc` and ask the kernel; Windows uses `iphlpapi.dll`.
The text parsers behind it are public, so they can be tested with fixed text.

{{sample net/netif_parsers}}

**What to notice.**

* `parseRoutes`, `parseArp`, `parseSockets` and `parseNetDev` **replace** the module's table with what the text says; `routeAt(i)`,
  `arpAt(i)` and `connectionAt(i)` read that table. The functions that count or search (`routeCount`, `defaultGateway`, `arpCount`,
  `arpLookup`, `connectionCount`, `interfaceCount`) first **refresh the table from the real system**, which throws your parsed
  table away. Use the counts from the parser's return value in a test.
* The kernel writes addresses in `/proc/net/route` as little-endian hexadecimal: `0101A8C0` is `192.168.1.1`.

Live facts differ from one computer to the next, but the loopback interface is always there and a socket you just opened shows up in
the table:

{{sample net/netif_loopback}}

For everything else (interfaces with their MAC addresses and counters, the gateway, the ARP cache) the sample below only compiles.
`examples/netinfo.a` is a complete version.

{{sample net/netif_live}}

## Everyday tools: `netutil`

| Function | What it does |
|---|---|
| `netutil.ping(host, ms)` | ICMP echo; round trip time in ms, `-1` no answer, `-2` not allowed |
| `netutil.tcpPing(host, port, ms)`, `netutil.portOpen(host, port, ms)` | time to open a TCP connection; is something listening |
| `netutil.wakeOnLan("aa:bb:...")` | the Wake-on-LAN magic packet to `255.255.255.255:9` |
| `netutil.ntpTime(server)` | Unix time from an NTP server, `-1` on failure |

{{sample net/util_tcpping}}

**What to notice.** `portOpen` connects and closes again; it needs no permission, so it works where `ping` is not allowed. The tools
also expose their packets, which makes them testable:

{{sample net/util_wol}}

{{sample net/util_ntp}}

**What to notice.** The magic packet is `FF FF FF FF FF FF` followed by the MAC address sixteen times. The NTP sample uses the split
interface `ntpStart` / `ntpFinish` against a fake server of our own, with a hand-made reply whose time is 2024-01-01 (NTP counts seconds
since 1900, `netutil` converts to the Unix epoch). A reply with stratum 0 ("I do not know the time") is refused.

`ping` and the real `ntpTime` compile but do not run here:

{{sample net/util_ping}}

`ping` uses an unprivileged ICMP socket where the system allows it, and a raw socket otherwise; `-2` means the program may not send
ICMP at all. See `examples/ping.a` for a program that pings several times.

## Packets: `packet` and `rawnet`

The sockets of `net` hide the layers below them. Sometimes you need those layers: a network tool, a test for a protocol, a pcap file
for Wireshark. `packet` builds and reads Ethernet frames, ARP, IPv4, ICMP, UDP and TCP, with all the checksums, and works on plain
byte buffers: no network, no permission, the same results everywhere.

Every build function writes its **own layer plus the payload you give it** and returns the length, so you build from the inside out.
Every parse function fills an object and returns `false` for bytes that are too short or of another kind; `offset` tells where the
next layer starts.

```text
Ethernet frame:  [ dst MAC | src MAC | type ][ IPv4 header | ICMP / UDP / TCP header | data ]
ARP frame:       [ dst MAC | src MAC | 0x0806 ][ ARP packet ]
```

### ARP

{{sample net/packet_arp}}

**What to notice.** An ARP request is a broadcast (`ff:ff:ff:ff:ff:ff`) asking "who has 10.0.0.2?", and the owner answers directly.
`describe(frame, n)` prints one line in the style of `tcpdump`, and `hexdump(data, n)` shows the bytes with their ASCII.

### UDP over IPv4 over Ethernet

{{sample net/packet_udp}}

**What to notice.**

* The UDP checksum covers a *pseudo header* (the two IP addresses, the protocol and the length) as well as the datagram, so
  `udpBuild` and `udpChecksumOk` need the addresses.
* `ipBuild` makes a 20-byte header without options and with the "don't fragment" flag. `ipParse` reports `checksumOk` for the header.
* The parse functions chain: `ethParse` gives the offset of the IP header, `ipParse` the offset of the segment.

### TCP segments

`packet` builds the segments; it does **not** contain a TCP implementation. The sample writes the story of a short HTTP request by
hand, the way `tcpdump` would show it.

{{sample net/packet_tcp}}

**What to notice.** The flags are `S` (SYN), `F` (FIN), `R` (RST), `P` (PSH), `U` (URG) and `.` (ACK). The SYN carries the *maximum
segment size* option, which makes the header 24 bytes instead of 20. A segment of 18 data bytes moves the sequence number from 1001 to
1019, and the other side acknowledges by saying `ack 1019`.

### ICMP

{{sample net/packet_icmp}}

**What to notice.** An echo reply copies the identifier, the sequence number and the data of the request. The checksum covers the
whole ICMP message, so changing a single byte is detected.

### Capture files

`PcapWriter` and `PcapReader` use the classic `.pcap` format, so Wireshark and `tcpdump -r` open the files.

{{sample net/packet_pcap}}

**What to notice.** The first four bytes (`d4 c3 b2 a1`) are the magic number, written little endian. Each record has a time stamp in
seconds and microseconds. `examples/packets.a` builds an ARP request, a UDP datagram and a TCP SYN and saves them in a file.

### Raw frames on a real network

`rawnet` opens a packet socket: you send complete Ethernet frames and receive every frame that crosses an interface. That needs Linux or
Android and permission (root or `CAP_NET_RAW`); without it `rawnet.open` returns `-1`.

{{sample net/rawnet_capture}}

**What to notice.** `capture` writes a `.pcap` file, `arping` is the ARP request of the previous section sent for real, and
`rawnet.send(h, frame, n)` takes any frame built with `packet.ethBuild`. `examples/arping.a` is a command-line tool around the same
calls.

## Summary

* `netaddr` is pure computation: IPv4 as an `int`, MAC and IPv6 as byte buffers, subnets with `parseCidr`, `network`, `broadcast`.
* `net` sockets are `int` handles that block. Check for negative results, read the three results of `recv` (data, `0`, negative) and
  remember that TCP is a stream: frame your messages and loop until you have all the bytes.
* A server asks for port `0` and reads `localPort`; a program can serve itself over loopback because the backlog completes the
  connection before `accept`.
* UDP keeps datagram boundaries but loses packets: set a time limit and retry.
* `net.poll`, `net.waitReadable` and `conn.Poller` wait for many sockets; every wait that can last should have a time limit.
* `dns`, `netif`, `netutil`, `packet` and `rawnet` build on the same layer; their parsers and builders work on plain bytes, which is
  why most of them can be tested without a network.

## Where next

* [HTTP, WebSocket and TLS](#chap-http-websocket-tls), the protocols that run on these sockets.
* API references: [net](#api-net), [netaddr](#api-netaddr), [conn](#api-conn), [dns](#api-dns), [netif](#api-netif),
  [netutil](#api-netutil), [packet](#api-packet), [rawnet](#api-rawnet).
* Bigger programs in `examples/`: `net_server.a` and `net_client.a` (an echo server and its client), `chat_server.a` (many clients in
  one thread), `dnslookup.a`, `ping.a`, `netinfo.a`, `packets.a`, `arping.a`.
