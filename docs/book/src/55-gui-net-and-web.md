# Networking, web pages and terminals in windows

A window program must stay responsive while it waits for a web server, so it cannot sit in a blocking `recv`. This chapter shows three libraries that live **inside the event loop** of a
GUI program: `gnet` (HTTP requests, TCP connections, UDP, a port scanner and a peer-to-peer chat), `ghtml` (a widget that shows HTML and Markdown) and `gterm` (a terminal emulator widget).
Together they are the parts of a web browser, a network tool and a terminal program.

In this chapter:

* how `gnet` works inside the event loop, and how the samples run without a display;
* HTTP fetches with redirects and cookies, TCP, UDP, a port scan and a chat;
* parsing and showing HTML and Markdown: links, images, forms, anchors and scrolling;
* a terminal widget you can write to, with colours, and one that runs a real program.

You should know the basics of windows and widgets ([GUI basics](#chap-gui-basics)); the networking functions underneath are in [Networking](#chap-networking) and [HTTP, WebSocket and TLS](#chap-http-websocket-tls).

## Network code in the event loop

A `gui.Display` has a loop that waits for events from the display server. `d->watch(fd, function, argument)` adds a file descriptor to that wait: the function is called whenever the descriptor is readable (and
`d->unwatch(fd)` removes it). Everything in `gnet` is built on it (and on the timers of the same loop, `d->after`), so a download, a chat and a port scan run between two mouse events, and the window never freezes. (Up to 64 descriptors can be watched per display connection.)

All samples of this chapter that use `gnet` need a `gui.Display`. They get one the way [the display server chapter](#chap-display-server) describes: a `wsrv.Server` on a headless screen in the same program, found by a free port, and
`gui.idleHook` that gives the server turns. A real program calls `gui.connect(null)` and `d->run()` instead; the `gnet` code is the same. The little web server of the HTTP samples also lives in the process,
so the samples need nothing but loopback.

## Fetching pages

`gnet.Fetch` is an HTTP/1.1 request that does not block. `start(display, address, extraHeaders)` returns at once; the answer is read as it arrives, and `onDone` runs at the end. `extraHeaders` is `null`, or raw header lines that are added to the request, each one ending in `\r\n`.

{{sample guinet/fetch}}

**What to notice**

* After the fetch: `status`, `headers`, `body`, `bodyLen`, `error`, `url` (the address that was finally fetched), `contentLength` (or -1), `received` and `elapsed`. `onProgress` runs while data arrives.
* A `302` was followed. Redirects (`301`, `302`, `303`, `307`, `308`) are followed up to 5 times, and `url` is the last address. Chunked bodies and `Content-Length` are handled; a body that is shorter than the `Content-Length` promised (the server hung up early) is an error, not a silent short result. A response that grows past `maxBytes` (8 MB unless you change it; the headers get another 64 KB of room) fails with "the response is too large".
* `start` returns `false` for an address it cannot use (here `ftp://`), with the reason in `error` ("not a valid http:// address"); a server that is not there gives `false` and the error "cannot connect". `cancel()` stops a running fetch.
* Connecting still waits (4 seconds at most), and so does the name lookup of a host name that is not an address or in `/etc/hosts`: it is an ordinary DNS query, which waits 2 seconds per try (two tries) for every name server, so on a dead network it can take longer than the 4 seconds. Only the transfer and the TLS handshake are event driven.

### https

`https://` addresses work with the same calls. The connection uses TLS 1.3 (the `tls` module; TLS 1.2 and older are not implemented, so a server that only speaks them cannot be fetched from), and the server's certificate is checked against the system's root certificates unless you set `f->verifyCerts = false`. Afterwards `secure` tells whether the answer came over TLS, `cipher` names the cipher suite, and `certError` holds the reason when a certificate was refused (the fetch then fails with the same text in `error`). More about certificates is in [the TLS notes](#chap-tls-notes) and [HTTP, WebSocket and TLS](#chap-http-websocket-tls).

The sample uses the loopback technique of that chapter: a child process is a small HTTPS server with a throw-away test certificate, so nothing leaves the machine. The test certificate is not in anybody's list of roots, so the first fetch is refused; `x509.addRootPem` adds it as a root, and then the same fetch works.

{{sample guinet/fetch_https}}

**What to notice**

* The untrusted certificate is refused before any request is sent: `status` is 0, `secure` is 0 and `error` and `certError` say why.
* After `x509.addRootPem(...)` the fetch works: status 200, `secure` 1 and the cipher `TLS_AES_128_GCM_SHA256`. With `verifyCerts = false` it also works, but nothing proves who is at the other end: use that only for tests.
* This was run against the loopback server only. Fetching from real sites uses the system roots and the same code, but it was not tried for this book.

### POST and cookies

`f->post(data, null)` makes the request a POST with a form body. `Set-Cookie` headers go into a jar, `gnet.cookies()`, by host name, and are sent back to the same host, so logins work.

{{sample guinet/cookies}}

**What to notice**

* Before the login the site does not know the client; after `/login` the jar holds one cookie (`session`), and the next request carries it: `welcome back`.
* The jar knows hosts and names only. **Path, Domain, the port and the expiry are not used**: a cookie lives until the program ends or the server deletes it (`Max-Age=0`, or an empty value). The jar holds at most 128 cookies. `f->useCookies = false` skips the jar, and `gnet.cookies()->clear()` empties it.
* A POST that is answered with `301`, `302` or `303` is followed with a GET, like a browser does; `307` and `308` repeat the POST.
* `gnet.Fetch` is what `abrowse`, the browser example, uses for every page and picture.

## TCP and UDP

`gnet.Conn` is a TCP connection in the event loop. With `onLine` it delivers text lines (split at newlines, also when they arrive together or in pieces; a line longer than 64 KB closes the connection); with `onData` it delivers raw bytes
(`data` and `dataLen`). `gnet.Listener` accepts connections.

{{sample guinet/tcp}}

**What to notice**

* `Listener.start(display, host, port)`: port 0 means any free port, and `l->port` says which. `onAccept` gets the new connection in `l->accepted`; set its callbacks there.
* `sendLine` sends the text and a newline. When one side closes, the other side's `onClose` is called once and `open` is false.
* `connect(display, host, port, timeoutMs)` waits for the connection (the time limit is the last argument) and returns `false` when nothing is listening. Sending also waits, for one second at most.
* None of this blocks the window: while the sample "waits", the server of the display keeps getting turns.

`gnet.Beacon` does the same for UDP datagrams, including broadcasts to the local network:

{{sample guinet/beacon}}

**What to notice**

* An address is an `int`: `0x7F000001` is `127.0.0.1`. `broadcast(port, text)` goes to `255.255.255.255`.
* In `onPacket` you get `text`, `fromIp` and `fromPort`. `start(display, 0)` takes any free UDP port, and `port` says which. A datagram of more than 1499 bytes is cut.

### A port scanner

`gnet.Scan` tests the ports of a host, one port per turn of the event loop.

{{sample guinet/scan}}

**What to notice**

* `start(display, host, first, last, timeoutMs)` returns `false` for a range that is empty or not between 1 and 65535 (and while the scanner is still running). `onFound`, `onProgress` and `onDone` report; `stop()` ends a scan early, and a scanner can be started again.
* A scan is polite by construction: one connection attempt per turn of the loop, so it cannot flood anything. But the attempt itself **waits**: a closed port on the same machine answers at once, while a host that silently drops the packets costs the whole `timeoutMs` for every port, and the window is stuck for that time. A host name is looked up again for every port, so give an address. Keep the timeout short (a few hundred milliseconds) and the range small.
* Scan only machines you may scan. The sample only looks at the loopback address.

### A chat

`gnet.Chat` is a peer-to-peer chat made from the parts above: every program listens, announces its name by UDP every 3 seconds, and connects to the others it hears. Of two peers the one whose `name@port` sorts higher connects,
so there is one connection per pair; duplicate names are refused. A chat holds up to 32 connections.

{{sample guinet/chat}}

**What to notice**

* `Chat(name, tcpPort, udpPort)`: port 0 takes a free one. On a local network the announcements are broadcasts; the sample points them at each other with `addTarget(ip, udpPort)` and calls `announce()` at once.
* `onEvent` reports with `eventKind`: 1 a peer joined, 2 left, 3 a message (with `eventName` and `eventText`). `say(text)` reaches everybody, `peerCount()` and `peerName(i)` list the peers. `connectTo(host, port)` connects to a peer by hand (for example over a VPN, where there are no broadcasts).
* `stop()` says goodbye to every peer first: `ada` was told that `bob` left.
* There is **no encryption and no login**: use it on a network you trust. `examples/gui/achat.a` is a chat program with a peer list, a log, and notifications for messages that arrive while the window is in the background.

## Showing HTML and Markdown

`ghtml` has two halves. The functions parse and convert text without any window: `parseHtml`, `markdownToHtml`, `plainText`, `decodeEntities`, `resolveUrl` and `urlEncode`. The widget `HtmlView` lays a page out and draws it.

`ghtml` is a small viewer, not a full browser. The list of what it can and cannot do is in the section "Limits" at the end of the chapter.

{{sample guinet/html_text}}

**What to notice**

* `parseHtml(page, baseUrl)` builds a `Doc` with the blocks, the `title` and the links (already **absolute**: `guide.html` became `http://example.org/docs/guide.html`). `<style>` and `<script>` are skipped.
* `plainText` is the page as text: headings and list items on their own lines, tags gone, entities decoded.
* `decodeEntities` knows the usual names and numbers (`&amp;`, `&#65;`, `&#x42;`, `&copy;`) and leaves an unknown name (`&unknown;`) or a lone `&` alone.
* `markdownToHtml` handles a small, common part of Markdown: `#` headings, paragraphs, lists (`-`, `*`, `+` and `1.`, nested by indentation), code blocks fenced with three backticks, `>` quotes, tables with `|`, rules (`---`, `***`), and inside a line `[links](url)`, `![images](src)`, `**bold**`, `*emphasis*` and `` `code` ``. It does not know setext headings, indented code blocks, `~~~` fences, `_emphasis_`, strike-through or link titles, and HTML inside the Markdown is shown as text. The Markdown view is built on it.

Links in a page are written relative to the page. `resolveUrl(base, ref)` does what a browser does:

{{sample guinet/html_urls}}

**What to notice**

* `..` goes up (but not above the root), `/x` starts at the root, `//host/x` keeps the scheme and changes the host, and `#section` keeps everything and adds the fragment. `./` and `a/../b` are cleaned.
* It works for `file://` addresses too, which is how a local Markdown file finds its neighbours.

### The view

`HtmlView` draws headings (the big ones scaled), paragraphs, nested lists, preformatted text, block quotes, rules, tables with cells side by side (`<th>` cells are bold), links, bold, code, underline and images with their alt text until they load.
It scrolls (wheel, keys and a scroll bar), shows the hand cursor over links, and lays out again when its width changes.

{{sample guinet/html_view}}

{{shot guinet/html_view}}

**What to notice**

* `setHtml(html, baseAddress)` shows a page; `onLink` gets `linkHref` already resolved against the address, `onHover` gets `hoverHref` (null when the pointer leaves a link).
* The hover events came when the pointer entered the link, left it and entered it again, and the click came after the third. The pointer was put on a word of the link: the gaps between the words of a link are not part of it.
* Pictures are loaded by you: `imageCount()` and `imageSource(i)` list the wanted ones (the addresses are already absolute), `setImage(address, surface)` supplies one (at most 64 pictures per view). `abrowse` fetches four at a time in the background with `gnet.Fetch` and `gimg`. A picture that is also a link gets a thin frame in the link colour.
* It does **not** do CSS, frames or scripts (they are skipped), and `<i>` and `<em>` are shown upright. Colours do not come from the page: text, links, code and the background have fixed colours, which you can change for all views with the module variables `ghtml.colorText`, `ghtml.colorLink`, `ghtml.colorCode` and `ghtml.colorBack`.

### Forms

Forms work, although the header comment of `ghtml.a` and the GUI reference still say they do not. `<form>` with `input` (text, password, search, email, number ..., checkbox, radio, submit, button, reset, image, hidden; an `image` input is just an ordinary submit button), `textarea`, `select` with `option`, and `button` become real widgets inside the view. They scroll with the page and
Tab moves between them (and scrolls the focused one into view). A click on a submit button, or Enter in a text field, calls `onSubmit`.

{{sample guinet/html_form}}

{{shot guinet/html_form}}

**What to notice**

* `controlCount()` and `controlWidget(i)` give the controls in the order of the page; a text field is a `gui.TextBox`, a radio button a `guix.RadioButton`, a menu a `guix.ComboBox`.
* `submitMethod`, `submitUrl` (resolved, and for GET the query is added) and `submitBody` are what `abrowse` hands to `gnet.Fetch`.
* The body is URL encoded: `+` for spaces, `%26` for `&`, `%0D%0A` for the line break of a text area. The unchecked check box was left out, only the chosen radio button is sent, and only the submit button
  that was used.
* `ghtml.urlEncode(text)` makes the same encoding for your own use.
* A GET form appends the fields to the action address, after `?` (or after `&` when the address already has a query); a `#fragment` of the action is dropped, and `submitBody` is empty then. With Enter in a text field no submit button is sent, because none was used. Fields without a `name` are not sent, and an empty field is sent as `name=`.
* The limits of forms: the body is always URL encoded (`enctype="multipart/form-data"` is ignored, so there is no file upload and `type=file` is just a text field); `<select multiple>`, `maxlength`, `readonly`, `<label>` clicks and form validation are not supported; a `reset` button is only a button that does nothing. A page can have at most 16 forms and 128 controls, and a `select` at most 64 options.
* `ghtml` does not store cookies and does not send anything by itself. Cookies belong to `gnet.Fetch`, which is why a browser built from the parts sends the form with `gnet.Fetch` and gets the cookies of the login for free.

### Markdown

{{sample guinet/markdown_view}}

{{shot guinet/markdown_view}}

**What to notice**

* `setMarkdown(text, baseAddress)` converts and shows; `setPlain(text, base)` shows text in a `<pre>` block.
* The wheel scrolled the view by 48 pixels a step: three steps moved it to 144 of the 155 pixels that were hidden. `scrollToAnchor("name")` and `anchorY("name")` work with `<h2 id=name>` and `<a name=name>`.
* Headings, nested lists, numbered lists, a quote, a table and a code block are all there; the table header is not bold, and the page has no colours of its own: code is purple, links are blue, the rest is dark text on white. The picture was taken after the three wheel steps, so the top of the page is scrolled out of view.

### A browser from the parts

`examples/gui/abrowse.a` is a browser made of exactly these pieces: `HtmlView`, `gnet.Fetch` (pages load without freezing the window), `gimg` (pictures load in the background), and the toolbar widgets of
`guix` (address bar, back, forward, reload, history that remembers the scroll position). It shows files and Markdown (`abrowse docs/GUI.md`), plain text and the source of a page. For `https://` the status
bar says `Secure:` and the cipher suite that was negotiated (`Not verified:` when the check was switched off), and a refused certificate gives a "Your connection is not private" page with a "Back to safety" link and a "Proceed to HOST anyway (unsafe)" link. That program was compiled for this chapter, but it was not run against real sites.

## A terminal in a window

`gterm.Terminal` is a widget that understands the usual ANSI and xterm escape sequences. It runs a program on a pseudo terminal (a pair of devices that make a program believe it talks to a real terminal; `start(display, command)`), or it can be used as a plain screen you write to with `feed(text)`,
which is what the first sample does. Without a program, what the user types (and what you pass to `send(text)`) is collected for `takeSent()` (at most 4000 bytes are kept); with a program it goes to the program.

{{sample guinet/term_feed}}

**What to notice**

* The widget has the size of its window: 30 columns by 5 rows here (`cellW()` and `cellH()` are the size of a cell in pixels, so you can size a window for a number of columns).
* `feed` interprets escape sequences (`\e[1;8H` moves the cursor, `\e[K` erases to the end of the line, `\e[2J` clears) and wraps long lines. `lineText(row)`, `cursorRow`, `cursorCol` and `selectedText()` read the screen back.
* `historyCount()` and `historyText(i)` (0 is the oldest) give the scrollback: at most 2000 lines, and the mouse wheel (3 lines a step) or Shift+PageUp scroll it. When the history is full, the oldest line is used again as the new bottom line: in a test, feeding 6000 lines
  created only 2058 line objects, so a long output does not make the program grow.

What the widget draws:

{{sample guinet/term_colors}}

{{shot guinet/term_colors}}

**What to notice**

* Bold, dim, underline and reverse work; **italics** (`\e[3m`) are understood but drawn upright. 16, 256 and 24 bit colours work (the gray ramp and a cube slice come from `48;5;n`, the red to blue ramp from `48;2;r;g;b`).
* Box drawing characters are drawn as one pixel lines (light, heavy and double lines look the same) and the full, half and shade blocks as rectangles, so they join without gaps; arrows and triangles are small solid shapes. A few punctuation and symbol characters get plain ASCII stand-ins (the ellipsis is `.`, a check mark `*`);
  other characters outside Latin-1 are drawn as `?` (`lineText` still returns the real character). Wide (CJK) characters take **one** cell here.
* Mouse reporting for programs (1000, 1002, 1003 with the SGR form), bracketed paste, focus reports, window titles (`OSC 0` and `2`) and the size report `CSI 18 t` work, which is what [the terminal toolkit](#chap-terminal-ui) needs. Hold Shift to select text instead of sending the mouse to the program.

Running a real program:

{{sample guinet/term_command}}

**What to notice**

* `start(display, command)` runs the command through `/bin/sh -c` on a pseudo terminal and returns `false` when that fails. With `null` or an empty command it runs your shell (`$SHELL`, or `/bin/sh`). The program sees a terminal of the widget's size (`stty size` printed `6 40`: rows, then columns), `TERM=xterm-256color` and `COLORTERM=truecolor`.
* `onExit` is called when the program has ended; `exitStatus` holds its exit code (3 here), but 0 when the program was killed by a signal. The widget collects the process, so there are no zombies. `stop()` ends a running program: it gets `SIGHUP`, and `SIGKILL` if it is still there after 300 ms; `onExit` is not called for a program that was stopped.
* The size of the pseudo terminal follows the widget: the program gets `SIGWINCH` when the window is resized.
* `start` needs a pseudo terminal, so it is for Linux and Android: on Windows it returns false, while `feed` still works. `aterm` (`examples/gui/aterm.a`) is a terminal program made of this widget:
  `ADISPLAY=0 ./aterm` opens your shell, Ctrl+Shift+N opens another window, Ctrl+Shift+C and V copy and paste.

## Limits

* `HtmlView` has no CSS, no scripts, no frames, no italics and no colours from the page; tables are cells side by side, not a full table layout. Forms work, but with URL encoded bodies only (no file upload, no `multiple` selects). `markdownToHtml` knows a small part of Markdown.
* `gnet.Fetch` is HTTP/1.1 GET and POST, with `Connection: close`; connecting waits for up to 4 seconds and a DNS lookup can wait longer; cookies know hosts and names only; a response is limited to `maxBytes` (8 MB by default).
* `gnet.Chat` and `gnet.Conn` are unencrypted. `gnet.Scan` tests one port per turn of the loop, and each attempt waits for its timeout.
* `gterm` has one font size, no wide characters, no italics, no `OSC 52` clipboard sequence, and needs a pseudo terminal (Linux and Android).

## Summary

* `gnet`, `ghtml` and `gterm` live inside the event loop of `gui`: `d->watch(fd, ...)` calls a function when a descriptor is readable, so a window stays responsive.
* `gnet.Fetch` makes non blocking HTTP requests (redirects, chunked bodies, POST, cookies, https with a checked certificate); `Conn`, `Listener`, `Beacon`, `Scan` and `Chat` cover TCP, UDP, port scanning and a peer-to-peer chat.
* `ghtml` parses and converts HTML and Markdown without a window, resolves links, and `HtmlView` shows a page with links, images, tables and working forms (no CSS, scripts or frames).
* `gterm.Terminal` is a terminal emulator widget: feed it escape sequences from a string, or run a program on a pseudo terminal.
* None of the network code encrypts anything except `https://` in `gnet.Fetch`: use a tunnel or a trusted network for the rest.

## Where next

* [The code editor widgets](#chap-code-editor-widgets) use `gterm` for their terminal panel and `ghtml` for the documentation viewer.
* [Networking](#chap-networking) and [HTTP, WebSocket and TLS](#chap-http-websocket-tls) for the blocking versions of these calls; [the TLS notes](#chap-tls-notes) for certificates.
* [The GUI reference](#chap-gui-reference) for the complete lists of widgets and options.
* API references: [gnet](#api-gnet), [ghtml](#api-ghtml), [gterm](#api-gterm).
