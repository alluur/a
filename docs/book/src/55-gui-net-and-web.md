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
`d->unwatch(fd)` removes it). Everything in `gnet` is built on it, so a download, a chat and a port scan run between two mouse events, and the window never freezes. (Up to 64 descriptors can be watched per display connection.)

All samples of this chapter that use `gnet` need a `gui.Display`. They get one the way [the display server chapter](#chap-display-server) describes: a `wsrv.Server` on a headless screen in the same program, found by a free port, and
`gui.idleHook` that gives the server turns. A real program calls `gui.connect(null)` and `d->run()` instead; the `gnet` code is the same. The little web server of the HTTP samples also lives in the process,
so the samples need nothing but loopback.

## Fetching pages

`gnet.Fetch` is an HTTP/1.1 request that does not block. `start(display, address, extraHeaders)` returns at once; the answer is read as it arrives, and `onDone` runs at the end.

{{sample guinet/fetch}}

**What to notice**

* After the fetch: `status`, `headers`, `body`, `bodyLen`, `error`, `url` (the address that was finally fetched), `contentLength` (or -1), `received` and `elapsed`. `onProgress` runs while data arrives.
* A `302` was followed (up to 5 redirects). Chunked bodies and `Content-Length` are handled, and a body that is shorter than the header promised is an error, not a silent short result.
* `start` returns `false` for an address it cannot use (here `ftp://`), with the reason in `error` ("not a valid http:// address"); a server that is not there gives `false` and the error "cannot connect". `cancel()` stops a running fetch.
* **`https://`** works too, with TLS 1.3: the certificate is checked against the system's roots unless `f->verifyCerts = false`; afterwards `secure`, `cipher` and, for a refused certificate, `certError`
  tell what happened (see [the TLS notes](#chap-tls-notes)). This chapter does not fetch from the Internet, so the https path was not run here.
* Connecting and the name lookup still wait (4 seconds at most); only the transfer is event driven.

### POST and cookies

`f->post(data, null)` makes the request a POST with a form body. `Set-Cookie` headers go into a jar, `gnet.cookies()`, by host name, and are sent back to the same host, so logins work.

{{sample guinet/cookies}}

**What to notice**

* Before the login the site does not know the client; after `/login` the jar holds one cookie (`session`), and the next request carries it: `welcome back`.
* The jar knows hosts and names only. **Path, Domain and the expiry are not used**: a cookie lives until the program ends or the server deletes it (`Max-Age=0`, or an empty value). `f->useCookies = false` skips the jar.
* A form POST that is answered with a redirect is followed with a GET, like a browser does.
* `gnet.Fetch` is what `abrowse`, the browser example, uses for every page and picture.

## TCP and UDP

`gnet.Conn` is a TCP connection in the event loop. With `onLine` it delivers text lines (split at newlines, also when they arrive together or in pieces); with `onData` it delivers raw bytes.
`gnet.Listener` accepts connections.

{{sample guinet/tcp}}

**What to notice**

* `Listener.start(display, host, port)`: port 0 means any free port, and `l->port` says which. `onAccept` gets the new connection in `l->accepted`; set its callbacks there.
* `sendLine` sends the text and a newline. When one side closes, the other side's `onClose` is called once and `open` is false.
* `connect(display, host, port, timeoutMs)` waits for the connection (the time limit is the last argument) and returns `false` when nothing is listening.
* None of this blocks the window: while the sample "waits", the server of the display keeps getting turns.

`gnet.Beacon` does the same for UDP datagrams, including broadcasts to the local network:

{{sample guinet/beacon}}

**What to notice**

* An address is an `int`: `0x7F000001` is `127.0.0.1`. `broadcast(port, text)` goes to `255.255.255.255`.
* In `onPacket` you get `text`, `fromIp` and `fromPort`. `start(display, 0)` takes any free UDP port.

### A port scanner

`gnet.Scan` tests the ports of a host one per turn of the event loop.

{{sample guinet/scan}}

**What to notice**

* `start(display, host, first, last, timeoutMs)` returns `false` for a range that is empty or not between 1 and 65535. `onFound`, `onProgress` and `onDone` report; `stop()` ends a scan early, and a scanner can be started again.
* A scan is polite by construction: one connection attempt per turn of the loop, so it cannot flood anything, and it needs the timeout you give for every closed port that does not answer.
* Scan only machines you may scan. The sample only looks at the loopback address.

### A chat

`gnet.Chat` is a peer-to-peer chat made from the parts above: every program listens, announces its name by UDP every 3 seconds, and connects to the others it hears. Of two peers the one whose `name@port` sorts higher connects,
so there is one connection per pair; duplicate names are refused.

{{sample guinet/chat}}

**What to notice**

* `Chat(name, tcpPort, udpPort)`: port 0 takes a free one. On a local network the announcements are broadcasts; the sample points them at each other with `addTarget(ip, udpPort)` and calls `announce()` at once.
* `onEvent` reports with `eventKind`: 1 a peer joined, 2 left, 3 a message (with `eventName` and `eventText`). `say(text)` reaches everybody, `peerCount()` and `peerName(i)` list the peers.
* `stop()` says goodbye to every peer first: `ada` was told that `bob` left.
* There is **no encryption and no login**: use it on a network you trust. `examples/gui/achat.a` is a chat program with a peer list, a log, and notifications for messages that arrive while the window is in the background.

## Showing HTML and Markdown

`ghtml` has two halves. The functions parse and convert text without any window: `parseHtml`, `markdownToHtml`, `plainText`, `decodeEntities` and `resolveUrl`. The widget `HtmlView` lays a page out and draws it.

{{sample guinet/html_text}}

**What to notice**

* `parseHtml(page, baseUrl)` builds a `Doc` with the blocks, the `title` and the links (already **absolute**: `guide.html` became `http://example.org/docs/guide.html`). `<style>` and `<script>` are skipped.
* `plainText` is the page as text: headings and list items on their own lines, tags gone, entities decoded.
* `decodeEntities` knows the usual names and numbers (`&amp;`, `&#65;`, `&#x42;`, `&copy;`) and leaves an unknown name (`&unknown;`) or a lone `&` alone.
* `markdownToHtml` handles headings, paragraphs, lists, code blocks, quotes, tables, rules, links, images, bold, emphasis and code. The Markdown view is built on it.

Links in a page are written relative to the page. `resolveUrl(base, ref)` does what a browser does:

{{sample guinet/html_urls}}

**What to notice**

* `..` goes up (but not above the root), `/x` starts at the root, `//host/x` keeps the scheme and changes the host, and `#section` keeps everything and adds the fragment. `./` and `a/../b` are cleaned.
* It works for `file://` addresses too, which is how a local Markdown file finds its neighbours.

### The view

`HtmlView` draws headings (the big ones scaled), paragraphs, nested lists, preformatted text, block quotes, rules, tables with cells side by side, links, bold, code, underline and images with their alt text until they load.
It scrolls (wheel, keys and a scroll bar), shows the hand cursor over links, and lays out again when its width changes.

{{sample guinet/html_view}}

{{shot guinet/html_view}}

**What to notice**

* `setHtml(html, baseAddress)` shows a page; `onLink` gets `linkHref` already resolved against the address, `onHover` gets `hoverHref` (null when the pointer leaves a link).
* The hover events came when the pointer entered the link, left it and entered it again, and the click came after the third. The pointer was put on a word of the link: the gaps between the words of a link are not part of it.
* Pictures are loaded by you: `imageCount()` and `imageSource(i)` list the wanted ones, `setImage(address, surface)` supplies one. `abrowse` fetches four at a time in the background with `gnet.Fetch` and `gimg`.
* It does **not** do CSS, frames or scripts (they are skipped), italics or colours.

### Forms

`<form>` with `input` (text, password, search, email, number ..., checkbox, radio, submit, button, hidden), `textarea`, `select` with `option`, and `button` become real widgets inside the view. They scroll with the page and
Tab moves between them. A click on a submit button, or Enter in a text field, calls `onSubmit`.

{{sample guinet/html_form}}

{{shot guinet/html_form}}

**What to notice**

* `controlCount()` and `controlWidget(i)` give the controls in the order of the page; a text field is a `gui.TextBox`, a radio button a `guix.RadioButton`, a menu a `guix.ComboBox`.
* `submitMethod`, `submitUrl` (resolved, and for GET the query is added) and `submitBody` are what `abrowse` hands to `gnet.Fetch`.
* The body is URL encoded: `+` for spaces, `%26` for `&`, `%0D%0A` for the line break of a text area. The unchecked check box was left out, only the chosen radio button is sent, and only the submit button
  that was used.
* `ghtml.urlEncode(text)` makes the same encoding for your own use.

### Markdown

{{sample guinet/markdown_view}}

{{shot guinet/markdown_view}}

**What to notice**

* `setMarkdown(text, baseAddress)` converts and shows; `setPlain(text, base)` shows text in a `<pre>` block.
* The wheel scrolled the view by 48 pixels a step: three steps moved it to 144 of the 155 pixels that were hidden. `scrollToAnchor("name")` and `anchorY("name")` work with `<h2 id=name>` and `<a name=name>`.
* Headings, nested lists, numbered lists, a quote, a table and a code block are all there; the table header is not bold, and there are no colours.

### A browser from the parts

`examples/gui/abrowse.a` is a browser made of exactly these pieces: `HtmlView`, `gnet.Fetch` (pages load without freezing the window), `gimg` (pictures load in the background), and the toolbar widgets of
`guix` (address bar, back, forward, reload, history that remembers the scroll position). It shows files and Markdown (`abrowse docs/GUI.md`), plain text and the source of a page. For `https://` the status
bar says `Secure: TLS_AES_128_GCM_SHA256`, and a refused certificate gives a "Your connection is not private" page with "Back to safety" and "Proceed anyway (unsafe)". That program was compiled for this chapter but not run against real sites.

## A terminal in a window

`gterm.Terminal` is a widget that understands the usual ANSI and xterm escape sequences. It runs a program on a pseudo terminal (`start(display, command)`), or it can be used as a plain screen you write to with `feed(text)`,
which is what the first sample does. What the user types is collected for `takeSent()`.

{{sample guinet/term_feed}}

**What to notice**

* The widget has the size of its window: 30 columns by 5 rows here (`cellW()` and `cellH()` are the size of a cell in pixels, so you can size a window for a number of columns).
* `feed` interprets escape sequences (`\e[1;8H` moves the cursor, `\e[K` erases to the end of the line, `\e[2J` clears) and wraps long lines. `lineText(row)`, `cursorRow`, `cursorCol` and `selectedText()` read the screen back.
* `historyCount()` and `historyText(i)` give the scrollback (2000 lines, the mouse wheel or Shift+PageUp scroll it). When the history is full, the oldest line object is used again as the new bottom line, so a program that prints
  100 MB needs no more memory than one that prints 2000 lines.

What the widget draws:

{{sample guinet/term_colors}}

{{shot guinet/term_colors}}

**What to notice**

* Bold, dim, underline and reverse work; **italics are not drawn**. 16, 256 and 24 bit colours work (the gray ramp and a cube slice come from `48;5;n`, the red to blue ramp from `48;2;r;g;b`).
* Box drawing and block characters are drawn as lines and rectangles, so they join without gaps; arrows and triangles are small solid shapes. A few punctuation and symbol characters get plain ASCII stand-ins (the ellipsis is `.`, a check mark `*`);
  other characters outside Latin-1 show as `?`. Wide (CJK) characters take **one** cell here.
* Mouse reporting for programs (1000, 1002, 1003 with the SGR form), bracketed paste, focus reports, window titles (`OSC 0` and `2`) and the size report `CSI 18 t` work, which is what [the terminal toolkit](#chap-terminal-ui) needs. Hold Shift to select text instead of sending the mouse to the program.

Running a real program:

{{sample guinet/term_command}}

**What to notice**

* `start(display, command)` runs the command through `/bin/sh -c` on a pseudo terminal and returns `false` when that fails. The program sees a terminal of the widget's size (`stty size` printed `6 40`) and `TERM=xterm-256color`.
* `onExit` is called when the program has ended; `exitStatus` holds its status (3 here). The widget collects the process, so there are no zombies.
* The size of the pseudo terminal follows the widget: the program gets `SIGWINCH` when the window is resized.
* Linux and Android only: on Windows `start` returns false (there are no pseudo terminals), while `feed` still works. `aterm` (`examples/gui/aterm.a`) is a terminal program made of this widget:
  `ADISPLAY=0 ./aterm` opens your shell, Ctrl+Shift+N opens another window, Ctrl+Shift+C and V copy and paste.

## Limits

* `HtmlView` has no CSS, no scripts, no frames, no italics or colours; tables are cells side by side, not a full table layout.
* `gnet.Fetch` is HTTP/1.1 GET and POST; connecting and DNS wait for up to 4 seconds; cookies know hosts and names only.
* `gnet.Chat` and `gnet.Conn` are unencrypted. `gnet.Scan` tests one port per turn of the loop.
* `gterm` has one font size, no wide characters, no italics, no `OSC 52` clipboard sequence, and needs a pseudo terminal (Linux and Android).

## Summary

* `gnet`, `ghtml` and `gterm` live inside the event loop of `gui`: `d->watch(fd, ...)` calls a function when a descriptor is readable, so a window stays responsive.
* `gnet.Fetch` makes non blocking HTTP requests (redirects, chunked bodies, POST, cookies, https); `Conn`, `Listener`, `Beacon`, `Scan` and `Chat` cover TCP, UDP, port scanning and a peer-to-peer chat.
* `ghtml` parses and converts HTML and Markdown without a window, resolves links, and `HtmlView` shows a page with links, images, tables and working forms.
* `gterm.Terminal` is a terminal emulator widget: feed it escape sequences from a string, or run a program on a pseudo terminal.
* None of the network code encrypts anything except `https://`: use a tunnel or a trusted network for the rest.

## Where next

* [The code editor widgets](#chap-code-editor-widgets) use `gterm` for their terminal panel and `ghtml` for the documentation viewer.
* [Networking](#chap-networking) and [HTTP, WebSocket and TLS](#chap-http-websocket-tls) for the blocking versions of these calls; [the TLS notes](#chap-tls-notes) for certificates.
* [The GUI reference](#chap-gui-reference) for the complete lists of widgets and options.
* API references: [gnet](#api-gnet), [ghtml](#api-ghtml), [gterm](#api-gterm).
