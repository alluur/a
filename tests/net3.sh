#!/bin/bash
# Interoperability of smtpd, ftpd and pop3d with independent clients (Linux; needs python3 for smtplib, ftplib, poplib, email; curl is used when it is installed).
# And of the mail module with Python's email package (parse and build, both ways).
# Not part of `make test`. Usage: tests/net3.sh, from the root of the repository (the paths are relative to it).
cd "$(dirname "$0")/.."
AC=./build/ac
W=build/net3
rm -rf $W; mkdir -p $W
pass=0; fail=0
ok()  { echo "ok   $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
for e in smtpd_demo ftpd_demo pop3d_demo; do $AC examples/$e.a -o $W/$e || { echo "cannot build $e"; exit 1; }; done
pids=""
trap 'kill $pids 2>/dev/null' EXIT

# ---- SMTP: Python's smtplib against smtpd
MAILDIR=$W/mail; mkdir -p $MAILDIR
P=$(port); $W/smtpd_demo $P example.org $MAILDIR > $W/smtpd.out 2>&1 & pids="$pids $!"; sleep 0.5
python3 - $P $MAILDIR <<'PY' && ok "smtplib: EHLO, a UTF-8 message to a local recipient, a recipient that is refused (relay denied), the message is in the Maildir" || bad "smtplib against smtpd"
import smtplib, sys, os, glob, email, email.policy
from email.message import EmailMessage
port, md = int(sys.argv[1]), sys.argv[2]
s = smtplib.SMTP("127.0.0.1", port, timeout=10)
code, text = s.ehlo("client.test")
assert code == 250 and s.has_extn("size") and s.has_extn("8bitmime") and s.has_extn("pipelining"), (code, text)
m = EmailMessage(); m["From"] = "Jürgen <jm@example.net>"; m["To"] = "bob@example.org"; m["Subject"] = "Grüße"
m.set_content("Zeile 1\n.Punkt am Anfang\nZeile 3 ü\n")
refused = s.send_message(m, from_addr="jm@example.net", to_addrs=["bob@example.org", "eve@elsewhere.test"])
assert "eve@elsewhere.test" in refused and refused["eve@elsewhere.test"][0] == 554, refused
s.quit()
files = glob.glob(md + "/bob/new/*")
assert len(files) == 1, files
got = email.message_from_bytes(open(files[0], "rb").read(), policy=email.policy.default)
assert got["Subject"] == "Grüße" and got["Return-Path"] == "<jm@example.net>" and got["Received"], got.items()
assert got.get_content().replace("\r\n", "\n") == "Zeile 1\n.Punkt am Anfang\nZeile 3 ü\n", repr(got.get_content())
PY
if command -v curl >/dev/null; then
  printf 'From: a@x.test\r\nTo: carol@example.org\r\nSubject: curl\r\n\r\nvia curl\r\n.dot\r\n' > $W/curl.eml
  curl -s --mail-from a@x.test --mail-rcpt carol@example.org -T $W/curl.eml smtp://127.0.0.1:$P && ls $MAILDIR/carol/new/* >/dev/null 2>&1 && grep -q "via curl" $MAILDIR/carol/new/* && ok "curl sends a message by SMTP" || bad "curl SMTP"
  curl -s --mail-from a@x.test --mail-rcpt nobody@elsewhere.test -T $W/curl.eml smtp://127.0.0.1:$P > /dev/null 2>&1 && bad "curl: a foreign recipient must be refused" || ok "curl: a foreign recipient is refused (open relay closed)"
fi

# ---- POP3: poplib and curl against pop3d (the Maildir of smtpd)
P=$(port); $W/pop3d_demo $P $MAILDIR/bob secret > $W/pop3d.out 2>&1 & pids="$pids $!"; sleep 0.5
python3 - $P <<'PY' && ok "poplib: USER / PASS, STAT, LIST, UIDL, RETR (dot-stuffed lines), TOP, DELE, QUIT" || bad "poplib against pop3d"
import poplib, sys
p = poplib.POP3("127.0.0.1", int(sys.argv[1]), timeout=10)
p.user("ann"); p.pass_("secret")
n, size = p.stat(); assert n == 1, (n, size)
assert len(p.list()[1]) == 1 and len(p.uidl()[1]) == 1
resp, lines, octets = p.retr(1)
text = b"\n".join(lines).decode()
assert "Zeile 1" in text and ".Punkt am Anfang" in text, text
resp, lines, octets = p.top(1, 0)
assert any(l.startswith(b"Subject:") for l in lines)
p.dele(1); p.quit()
PY
if command -v curl >/dev/null; then
  P=$(port); $W/pop3d_demo $P $MAILDIR/carol secret > $W/pop3d2.out 2>&1 & pids="$pids $!"; sleep 0.5
  curl -s -u ann:secret pop3://127.0.0.1:$P/ | grep -q "^1 " && ok "curl lists a mailbox by POP3" || bad "curl POP3 list"
  curl -s -u ann:secret pop3://127.0.0.1:$P/1 | grep -q "via curl" && ok "curl retrieves a message by POP3" || bad "curl POP3 retr"
fi

# ---- FTP: ftplib and curl against ftpd
FTPDIR=$W/ftp; mkdir -p $FTPDIR/sub; echo "hello ftp" > $FTPDIR/hello.txt; head -c 200000 /dev/urandom > $FTPDIR/big.bin; echo secret-outside > $W/outside.txt
P=$(port); $W/ftpd_demo $P $FTPDIR pw > $W/ftpd.out 2>&1 & pids="$pids $!"; sleep 0.5
python3 - $P $FTPDIR <<'PY' && ok "ftplib: login, passive and active transfers, MLSD, NLST, SIZE, MDTM, MKD, RNFR/RNTO, DELE, REST, the jail" || bad "ftplib against ftpd"
import ftplib, sys, io, os
port, d = int(sys.argv[1]), sys.argv[2]
for passive in (True, False):
    f = ftplib.FTP(); f.connect("127.0.0.1", port, timeout=10); f.login("ann", "pw"); f.set_pasv(passive)
    assert f.pwd() == "/"
    assert sorted(f.nlst()) == ["big.bin", "hello.txt", "sub"], f.nlst()
    names = {n: facts for n, facts in f.mlsd()}
    assert names["hello.txt"]["type"] == "file" and names["hello.txt"]["size"] == "10" and names["sub"]["type"] == "dir", names
    buf = io.BytesIO(); f.retrbinary("RETR hello.txt", buf.write); assert buf.getvalue() == b"hello ftp\n"
    big = io.BytesIO(); f.retrbinary("RETR big.bin", big.write); assert big.getvalue() == open(d + "/big.bin", "rb").read()
    f.storbinary("STOR up.bin", io.BytesIO(os.urandom(100000) + b"x")); assert f.size("up.bin") == 100001
    rest = io.BytesIO(); f.retrbinary("RETR big.bin", rest.write, rest=150000); assert rest.getvalue() == open(d + "/big.bin", "rb").read()[150000:]
    lines = []; f.retrlines("LIST", lines.append); assert any("hello.txt" in l and l.startswith("-") for l in lines), lines
    f.mkd("newdir"); f.rename("newdir", "renamed"); f.rmd("renamed"); f.delete("up.bin")
    assert f.sendcmd("MDTM hello.txt").startswith("213 20")
    f.cwd("../../.."); assert f.pwd() == "/"
    try:
        f.retrbinary("RETR ../outside.txt", io.BytesIO().write); raise SystemExit("jail: a file outside was read")
    except ftplib.error_perm as e:
        assert str(e).startswith("550")
    f.quit()
try:
    ftplib.FTP().connect("127.0.0.1", port); a = ftplib.FTP(); a.connect("127.0.0.1", port); a.login("ann", "wrong")
    raise SystemExit("a wrong password was accepted")
except ftplib.error_perm as e:
    assert str(e).startswith("530")
a = ftplib.FTP(); a.connect("127.0.0.1", port); a.login()                # anonymous
assert "hello.txt" in a.nlst()
try:
    a.storbinary("STOR evil.txt", io.BytesIO(b"x")); raise SystemExit("anonymous could write")
except ftplib.error_perm as e:
    assert str(e).startswith("550")
PY
if command -v curl >/dev/null; then
  curl -s -u ann:pw -T $W/curl.eml ftp://127.0.0.1:$P/curl.eml && cmp -s $W/curl.eml $FTPDIR/curl.eml && ok "curl uploads a file by FTP" || bad "curl FTP upload"
  curl -s -u ann:pw ftp://127.0.0.1:$P/hello.txt | grep -q "hello ftp" && ok "curl downloads a file by FTP" || bad "curl FTP download"
  curl -s -u ann:pw -P - ftp://127.0.0.1:$P/hello.txt | grep -q "hello ftp" && ok "curl downloads in active mode (PORT / EPRT)" || bad "curl FTP active"
  curl -s -u ann:pw --ftp-skip-pasv-ip ftp://127.0.0.1:$P/ | grep -q "big.bin" && ok "curl lists a directory by FTP" || bad "curl FTP list"
  curl -s -u ann:pw "ftp://127.0.0.1:$P/../../outside.txt" | grep -q "secret-outside" && bad "curl: the jail leaked a file" || ok "curl cannot leave the jail"
fi

# ---- the mail module against Python's email package, both ways (see also the tests t397 to t399)
cat > $W/mailtest.a <<'AEOF'
import mail;
int main(int argc, char** argv) {
    mail.Message* m = mail.newMessage();
    m->from("Jürgen Müller <jm@example.org>");  m->to("Åsa Öberg <asa@example.org>, \"Smith, John\" <js@example.org>");
    m->subject("Ein sehr langer Betreff mit Ümläuten und vielen Wörtern, der auf mehrere Zeilen verteilt werden muss, weil er so lang ist");
    m->text("Grüße\nZeile 2\n.Punkt\n");  m->html("<p>Grüße</p>");
    m->attach("Übersicht für 2026 \"final\".bin", "application/octet-stream", "\x00\x01\x02 binary \xFF\xFE", 14);
    m->attachInline("logo.png", "image/png", "PNGDATA", 7, "logo1");
    m->setDate(1794580200, 60);
    int n = 0;
    char* w = m->build(&n);
    writeFile(argv[1], w);
    return 0;
}
AEOF
$AC $W/mailtest.a -o $W/mailtest && $W/mailtest $W/built.eml
python3 - $W/built.eml <<'PY' && ok "Python's email package reads a message that the mail module built (subject, names, alternative, related, attachment with a UTF-8 name)" || bad "email reads mail.build"
import sys, email, email.policy
m = email.message_from_bytes(open(sys.argv[1], "rb").read(), policy=email.policy.default)
assert m["subject"].startswith("Ein sehr langer Betreff mit Ümläuten"), m["subject"]
assert [a.display_name for a in m["to"].addresses] == ["Åsa Öberg", "Smith, John"] and m["from"].addresses[0].display_name == "Jürgen Müller"
assert m.get_body(("plain",)).get_content().replace("\r\n", "\n") == "Grüße\nZeile 2\n.Punkt\n" and "Grüße" in m.get_body(("html",)).get_content()
names = [a.get_filename() for a in m.iter_attachments()]
assert "Übersicht für 2026 \"final\".bin" in names, names
assert m["date"].datetime.utcoffset().total_seconds() == 3600
PY
python3 - $W <<'PY'
from email.message import EmailMessage
import sys
m = EmailMessage(); m["From"] = "a@b.org"; m["To"] = "Åsa <c@d.org>"; m["Subject"] = "=?iso-8859-1?q?Gr=FC=DFe?= und ä"
m.set_content("Grüße\n"); m.add_alternative("<p>Grüße</p>", subtype="html")
m.add_attachment(b"\x00\x01binary" * 30, maintype="application", subtype="octet-stream", filename="Übersicht für das sehr lange Dokument mit einem unglaublich langen Namen 2026.bin")
open(sys.argv[1] + "/py.eml", "wb").write(m.as_bytes())
PY
cat > $W/mailread.a <<'AEOF'
import mail;
int main(int argc, char** argv) {
    char* data = readFile(argv[1]);
    mail.Part* p = mail.parse(data, strlen(data), null);
    char* s = p->decodedHeader("Subject");
    mail.AddressList* to = p->addresses("To");
    mail.Part* t = p->firstText("plain");
    printf("%s|%s|%s|%d|%s|%d\n", s, to->get(0)->name, t->body, p->attachmentCount(), p->attachment(0)->filename, p->attachment(0)->bodyLen);
    return 0;
}
AEOF
$AC $W/mailread.a -o $W/mailread && [ "$($W/mailread $W/py.eml)" = "$(printf 'Grüße und ä|Åsa|Grüße\n|1|Übersicht für das sehr lange Dokument mit einem unglaublich langen Namen 2026.bin|240')" ] && ok "the mail module reads a message that Python's email package built (encoded words, RFC 2231 name of 70 characters, 240 bytes of binary)" || bad "mail.parse reads email's message"

echo "passed: $pass, failed: $fail"
[ $fail -eq 0 ]
