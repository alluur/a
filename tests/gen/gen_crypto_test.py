#!/usr/bin/env python3
"""Makes tests/t127_crypto.a and tests/t127_crypto.out from reference values of Python's `cryptography` and `hashlib` packages,
so that the A implementations (hash, bn, rsa, ec, x25519, aes, chacha) are checked against independent code.
Run: python3 tests/gen/gen_crypto_test.py"""
import hashlib, hmac, os, random
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding, ec, utils
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM, ChaCha20Poly1305
from cryptography.hazmat.primitives import serialization

random.seed(20260101)
here = os.path.dirname(os.path.abspath(__file__))
body = []
expected = []

def check(name, call, *args):
    """a call of the A helper check(name, got, want) is written by the sections below"""
    pass

def line(code, out=None):
    body.append(code)
    if out is not None:
        expected.append(out)

def H(b): return b.hex()

def case(name, got_expr, want_hex):
    line('    chk("%s", %s, "%s");' % (name, got_expr, want_hex), "%s ok" % name)

def bool_case(name, expr, want):
    line('    chkb("%s", %s, %d);' % (name, expr, 1 if want else 0), "%s ok" % name)

# ---- hashes and HMAC ---------------------------------------------------------------------------------------------------------------
for i, n in enumerate((0, 1, 55, 56, 64, 111, 112, 200, 1000)):
    data = bytes(random.randrange(256) for _ in range(n))
    case("sha256 %d" % n, 'hexOf(sha256(%s, %d), 32)' % ('"%s"' % H(data), n) if False else 'dig(256, "%s", %d)' % (H(data), n), hashlib.sha256(data).hexdigest())
    case("sha384 %d" % n, 'dig(384, "%s", %d)' % (H(data), n), hashlib.sha384(data).hexdigest())
    case("sha512 %d" % n, 'dig(512, "%s", %d)' % (H(data), n), hashlib.sha512(data).hexdigest())
for bits, fn in ((256, hashlib.sha256), (384, hashlib.sha384), (512, hashlib.sha512)):
    for klen in (4, 32, 64, 131, 200):
        key = bytes(random.randrange(256) for _ in range(klen)); msg = bytes(random.randrange(256) for _ in range(77))
        case("hmac%d key%d" % (bits, klen), 'mac(%d, "%s", "%s")' % (bits, H(key), H(msg)), hmac.new(key, msg, fn).hexdigest())

# ---- RSA ---------------------------------------------------------------------------------------------------------------------------
for keybits in (2048, 3072):
    key = rsa.generate_private_key(65537, keybits)
    pub = key.public_key().public_numbers()
    nbytes = keybits // 8
    n_hex = pub.n.to_bytes(nbytes, 'big').hex(); e_hex = pub.e.to_bytes(3, 'big').hex()
    for hname, halg, bits in (("sha256", hashes.SHA256(), 256), ("sha384", hashes.SHA384(), 384), ("sha512", hashes.SHA512(), 512)):
        msg = bytes(random.randrange(256) for _ in range(50))
        digest = hashlib.new(hname, msg).digest()
        sig = key.sign(msg, padding.PKCS1v15(), halg)
        bad = bytearray(sig); bad[40] ^= 1
        bool_case("rsa%d pkcs1 %s" % (keybits, hname), 'rsaPkcs1("%s", "%s", %d, "%s", "%s")' % (n_hex, e_hex, bits, H(digest), H(sig)), True)
        bool_case("rsa%d pkcs1 %s bad signature" % (keybits, hname), 'rsaPkcs1("%s", "%s", %d, "%s", "%s")' % (n_hex, e_hex, bits, H(digest), H(bytes(bad))), False)
        bool_case("rsa%d pkcs1 %s wrong digest" % (keybits, hname), 'rsaPkcs1("%s", "%s", %d, "%s", "%s")' % (n_hex, e_hex, bits, H(digest[::-1]), H(sig)), False)
        psig = key.sign(msg, padding.PSS(mgf=padding.MGF1(halg), salt_length=halg.digest_size), halg)
        pbad = bytearray(psig); pbad[100] ^= 4
        bool_case("rsa%d pss %s" % (keybits, hname), 'rsaPss("%s", "%s", %d, "%s", "%s")' % (n_hex, e_hex, bits, H(digest), H(psig)), True)
        bool_case("rsa%d pss %s bad signature" % (keybits, hname), 'rsaPss("%s", "%s", %d, "%s", "%s")' % (n_hex, e_hex, bits, H(digest), H(bytes(pbad))), False)
        bool_case("rsa%d pss vs pkcs1 %s" % (keybits, hname), 'rsaPkcs1("%s", "%s", %d, "%s", "%s")' % (n_hex, e_hex, bits, H(digest), H(psig)), False)


# ---- ECDSA -------------------------------------------------------------------------------------------------------------------------
for curve, bits, halg, hname in ((ec.SECP256R1(), 256, hashes.SHA256(), "sha256"), (ec.SECP384R1(), 384, hashes.SHA384(), "sha384"), (ec.SECP256R1(), 256, hashes.SHA384(), "sha384"), (ec.SECP384R1(), 384, hashes.SHA256(), "sha256")):
    for k in range(3):
        key = ec.generate_private_key(curve)
        nums = key.public_key().public_numbers(); nb = bits // 8
        pubhex = '04' + nums.x.to_bytes(nb, 'big').hex() + nums.y.to_bytes(nb, 'big').hex()
        msg = bytes(random.randrange(256) for _ in range(40))
        digest = hashlib.new(hname, msg).digest()
        r, s = utils.decode_dss_signature(key.sign(msg, ec.ECDSA(halg)))
        rh = r.to_bytes(nb, 'big').hex(); sh = s.to_bytes(nb, 'big').hex()
        nm = "ecdsa p%d %s #%d" % (bits, hname, k)
        bool_case(nm, 'ecVerify(%d, "%s", "%s", "%s", "%s")' % (bits, pubhex, H(digest), rh, sh), True)
        bool_case(nm + " bad s", 'ecVerify(%d, "%s", "%s", "%s", "%s")' % (bits, pubhex, H(digest), rh, ('%0*x' % (2 * nb, s ^ 8))), False)
        bool_case(nm + " bad digest", 'ecVerify(%d, "%s", "%s", "%s", "%s")' % (bits, pubhex, H(digest[::-1]), rh, sh), False)
        badpub = pubhex[:-2] + '%02x' % (int(pubhex[-2:], 16) ^ 1)
        bool_case(nm + " point off curve", 'ecVerify(%d, "%s", "%s", "%s", "%s")' % (bits, badpub, H(digest), rh, sh), False)


# ---- X25519 ------------------------------------------------------------------------------------------------------------------------
for k in range(6):
    priv = X25519PrivateKey.generate(); peer = X25519PrivateKey.generate()
    privb = priv.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    pubb = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    peerb = peer.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    case("x25519 public key #%d" % k, 'x25519pub("%s")' % H(privb), H(pubb))
    case("x25519 shared #%d" % k, 'x25519dh("%s", "%s")' % (H(privb), H(peerb)), H(priv.exchange(X25519PublicKey.from_public_bytes(peerb))))
# RFC 7748 section 5.2 vector
case("x25519 rfc7748", 'x25519dh("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4", "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")', "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")

# ---- AES-GCM -----------------------------------------------------------------------------------------------------------------------
for klen in (16, 32):
    for n, an in ((0, 0), (1, 0), (15, 5), (16, 16), (17, 3), (64, 13), (100, 0), (1000, 21)):
        key = bytes(random.randrange(256) for _ in range(klen)); iv = bytes(random.randrange(256) for _ in range(12))
        pt = bytes(random.randrange(256) for _ in range(n)); aad = bytes(random.randrange(256) for _ in range(an))
        ct = AESGCM(key).encrypt(iv, pt, aad)
        nm = "aes%d gcm %d/%d" % (klen * 8, n, an)
        case(nm + " seal", 'gcmSeal("%s", "%s", "%s", "%s")' % (H(key), H(iv), H(aad), H(pt)), H(ct))
        case(nm + " open", 'gcmOpen("%s", "%s", "%s", "%s")' % (H(key), H(iv), H(aad), H(ct)), H(pt))
        bad = bytearray(ct); bad[len(bad) // 2] ^= 1
        case(nm + " tampered", 'gcmOpen("%s", "%s", "%s", "%s")' % (H(key), H(iv), H(aad), H(bytes(bad))), "rejected")

# ---- ChaCha20-Poly1305 -------------------------------------------------------------------------------------------------------------
for n, an in ((0, 0), (1, 0), (15, 5), (16, 16), (17, 3), (64, 13), (65, 0), (1000, 21), (4096, 8)):
    key = bytes(random.randrange(256) for _ in range(32)); iv = bytes(random.randrange(256) for _ in range(12))
    pt = bytes(random.randrange(256) for _ in range(n)); aad = bytes(random.randrange(256) for _ in range(an))
    ct = ChaCha20Poly1305(key).encrypt(iv, pt, aad)
    nm = "chacha20-poly1305 %d/%d" % (n, an)
    case(nm + " seal", 'ccSeal("%s", "%s", "%s", "%s")' % (H(key), H(iv), H(aad), H(pt)), H(ct))
    case(nm + " open", 'ccOpen("%s", "%s", "%s", "%s")' % (H(key), H(iv), H(aad), H(ct)), H(pt))
    bad = bytearray(ct); bad[-1] ^= 0x80
    case(nm + " tampered", 'ccOpen("%s", "%s", "%s", "%s")' % (H(key), H(iv), H(aad), H(bytes(bad))), "rejected")


# ---- X.509 chains ------------------------------------------------------------------------------------------------------------------
import datetime
from cryptography import x509 as cx
from cryptography.x509.oid import NameOID
NOW = 1790000000       # the fixed "current time" of the test (2026-09-21)
def dt(year): return datetime.datetime(year, 1, 1, tzinfo=datetime.timezone.utc)
def mkname(cn): return cx.Name([cx.NameAttribute(NameOID.COMMON_NAME, cn)])
def mkcert(subject_cn, key, issuer_cn, issuer_key, ca, sans=None, nb=2026, na=2030, hash_alg=None, pss=False, ski_ca_flag=True, pathlen=None):
    b = cx.CertificateBuilder().subject_name(mkname(subject_cn)).issuer_name(mkname(issuer_cn)).public_key(key.public_key())
    b = b.serial_number(random.getrandbits(63) + 1).not_valid_before(dt(nb)).not_valid_after(dt(na))
    if ca is not None:
        b = b.add_extension(cx.BasicConstraints(ca=ca, path_length=None), critical=True)
    if sans:
        names = []
        for x in sans:
            if x[0].isdigit():
                import ipaddress
                names.append(cx.IPAddress(ipaddress.ip_address(x)))
            else:
                names.append(cx.DNSName(x))
        b = b.add_extension(cx.SubjectAlternativeName(names), critical=False)
    halg = hash_alg or hashes.SHA256()
    if isinstance(issuer_key, rsa.RSAPrivateKey) and pss:
        return b.sign(issuer_key, halg, rsa_padding=padding.PSS(mgf=padding.MGF1(halg), salt_length=halg.digest_size))
    return b.sign(issuer_key, halg)
def pem(*certs): return ''.join(c.public_bytes(serialization.Encoding.PEM).decode() for c in certs)
def lit(text): return '"' + text.replace('\n', '\\n') + '"'

rootkey = rsa.generate_private_key(65537, 2048); root = mkcert("Test Root", rootkey, "Test Root", rootkey, True, hash_alg=hashes.SHA384())
other_key = rsa.generate_private_key(65537, 2048); other = mkcert("Other Root", other_key, "Other Root", other_key, True)
ikey = ec.generate_private_key(ec.SECP256R1()); inter = mkcert("Test Intermediate", ikey, "Test Root", rootkey, True, hash_alg=hashes.SHA256())
ikey384 = ec.generate_private_key(ec.SECP384R1()); inter384 = mkcert("Test Intermediate 384", ikey384, "Test Root", rootkey, True, hash_alg=hashes.SHA384(), pss=True)
lkey = rsa.generate_private_key(65537, 2048)
leaf_a = mkcert("a.example.test", lkey, "Test Intermediate", ikey, False, ["a.example.test", "*.wild.example.test", "10.1.2.3"], hash_alg=hashes.SHA256())
leaf_b = mkcert("b.example.test", ec.generate_private_key(ec.SECP384R1()), "Test Intermediate 384", ikey384, False, ["b.example.test"], hash_alg=hashes.SHA384())
leaf_cn = mkcert("cn-only.example.test", lkey, "Test Intermediate", ikey, False, None)
leaf_old = mkcert("a.example.test", lkey, "Test Intermediate", ikey, False, ["a.example.test"], nb=2018, na=2019)
leaf_future = mkcert("a.example.test", lkey, "Test Intermediate", ikey, False, ["a.example.test"], nb=2029, na=2031)
leaf_direct = mkcert("direct.example.test", lkey, "Test Root", rootkey, False, ["direct.example.test"], hash_alg=hashes.SHA256())
fakeca_key = ec.generate_private_key(ec.SECP256R1()); fakeca = mkcert("Not A CA", fakeca_key, "Test Root", rootkey, False)
leaf_bad = mkcert("evil.example.test", lkey, "Not A CA", fakeca_key, False, ["evil.example.test"])
selfsigned = mkcert("self.example.test", lkey, "self.example.test", lkey, False, ["self.example.test"])
# a certificate whose signature was made by a different key than the one in the issuer certificate
imposter_key = ec.generate_private_key(ec.SECP256R1())
leaf_forged = mkcert("a.example.test", lkey, "Test Intermediate", imposter_key, False, ["a.example.test"])

def vcase(name, chain, roots, host, want):
    line('    chk("%s", chainCheck(%s, %s, "%s"), "%s");' % (name, lit(pem(*chain)), lit(pem(*roots)), host, want), "%s ok" % name)

vcase("chain rsa root, ec intermediate, rsa leaf", [leaf_a, inter], [root], "a.example.test", "trusted")
vcase("chain without the intermediate in the roots", [leaf_a, inter], [root, inter], "a.example.test", "trusted")
vcase("chain rsa-pss intermediate, p384 leaf", [leaf_b, inter384], [root], "b.example.test", "trusted")
vcase("chain leaf signed directly by the root", [leaf_direct], [root], "direct.example.test", "trusted")
vcase("host name case", [leaf_a, inter], [root], "A.Example.TEST", "trusted")
vcase("wildcard one label", [leaf_a, inter], [root], "foo.wild.example.test", "trusted")
vcase("wildcard not two labels", [leaf_a, inter], [root], "x.foo.wild.example.test", "the certificate is for a different host name")
vcase("wildcard not the bare domain", [leaf_a, inter], [root], "wild.example.test", "the certificate is for a different host name")
vcase("ip address san", [leaf_a, inter], [root], "10.1.2.3", "trusted")
vcase("other ip address", [leaf_a, inter], [root], "10.1.2.4", "the certificate is for a different host name")
vcase("common name only", [leaf_cn, inter], [root], "cn-only.example.test", "trusted")
vcase("wrong host", [leaf_a, inter], [root], "evil.example.test", "the certificate is for a different host name")
vcase("expired", [leaf_old, inter], [root], "a.example.test", "a certificate has expired")
vcase("not yet valid", [leaf_future, inter], [root], "a.example.test", "a certificate is not valid yet")
vcase("unknown root", [leaf_a, inter], [other], "a.example.test", "the certificate was issued by an unknown authority")
vcase("missing intermediate", [leaf_a], [root], "a.example.test", "the certificate was issued by an unknown authority")
vcase("self signed", [selfsigned], [root], "self.example.test", "the certificate is self signed (not trusted)")
vcase("self signed but trusted", [selfsigned], [selfsigned], "self.example.test", "trusted")
vcase("intermediate that is not a CA", [leaf_bad, fakeca], [root], "evil.example.test", "the certificate was issued by an unknown authority")
vcase("forged signature", [leaf_forged, inter], [root], "a.example.test", "the certificate was issued by an unknown authority")
vcase("no roots", [leaf_a, inter], [], "a.example.test", "no trusted root certificates are installed")

# SECTIONS-END (more sections are added above this line)

prelude = r'''// generated by tests/gen/gen_crypto_test.py from reference values of Python's `cryptography` and `hashlib`: do not edit
import hash;
import secure;
import bn;
import rsa;
import ec;
import x25519;
import aes;
import chacha;
import x509;
import encoding;
import cstring;

int bad = 0;

void chk(char* name, char* got, char* want) {
    if (streq(got, want)) {
        print(name);
        println(" ok");
    } else {
        print(name);
        print(" FAILED: ");
        println(got);
        bad++;
    }
}

void chkb(char* name, bool got, int want) {
    if ((got ? 1 : 0) == want) {
        print(name);
        println(" ok");
    } else {
        print(name);
        println(" FAILED");
        bad++;
    }
}

// hex text into a new byte buffer
char* unhex(char* h, int* n) {
    char* b = alloc(strlen(h) / 2 + 8);
    *n = secure.fromHex(h, b, strlen(h) / 2 + 4);
    return b;
}

char* dig(int bits, char* hexData, int n) {
    int len = 0;
    char* d = unhex(hexData, &len);
    char out[64];
    int hl = hash.digest(bits, d, len, &out[0]);
    return secure.toHex(&out[0], hl);
}

char* mac(int bits, char* keyHex, char* msgHex) {
    int kl = 0;
    int ml = 0;
    char* k = unhex(keyHex, &kl);
    char* m = unhex(msgHex, &ml);
    char out[64];
    int hl = hash.hmac(bits, k, kl, m, ml, &out[0]);
    return secure.toHex(&out[0], hl);
}

bool rsaPkcs1(char* nHex, char* eHex, int bits, char* digestHex, char* sigHex) {
    int nl = 0; int el = 0; int dl = 0; int sl = 0;
    char* n = unhex(nHex, &nl);
    char* e = unhex(eHex, &el);
    char* d = unhex(digestHex, &dl);
    char* s = unhex(sigHex, &sl);
    return rsa.verifyPkcs1(n, nl, e, el, bits, d, s, sl);
}

bool rsaPss(char* nHex, char* eHex, int bits, char* digestHex, char* sigHex) {
    int nl = 0; int el = 0; int dl = 0; int sl = 0;
    char* n = unhex(nHex, &nl);
    char* e = unhex(eHex, &el);
    char* d = unhex(digestHex, &dl);
    char* s = unhex(sigHex, &sl);
    return rsa.verifyPss(n, nl, e, el, bits, d, s, sl);
}

bool ecVerify(int bits, char* pubHex, char* digestHex, char* rHex, char* sHex) {
    int pl = 0; int dl = 0; int rl = 0; int sl = 0;
    char* p = unhex(pubHex, &pl);
    char* d = unhex(digestHex, &dl);
    char* r = unhex(rHex, &rl);
    char* s = unhex(sHex, &sl);
    return ec.verify(bits, p, pl, d, dl, r, rl, s, sl);
}

char* x25519pub(char* privHex) {
    int l = 0;
    char* k = unhex(privHex, &l);
    char out[32];
    x25519.base(&out[0], k);
    return secure.toHex(&out[0], 32);
}

char* x25519dh(char* privHex, char* pubHex) {
    int l = 0; int l2 = 0;
    char* k = unhex(privHex, &l);
    char* u = unhex(pubHex, &l2);
    char out[32];
    x25519.scalarmult(&out[0], k, u);
    return secure.toHex(&out[0], 32);
}

char* gcmSeal(char* keyHex, char* ivHex, char* aadHex, char* ptHex) {
    int kl = 0; int il = 0; int al = 0; int pl = 0;
    char* k = unhex(keyHex, &kl);
    char* iv = unhex(ivHex, &il);
    char* aad = unhex(aadHex, &al);
    char* pt = unhex(ptHex, &pl);
    char* out = alloc(pl + 32);
    aes.seal(aes.gcm(k, kl), iv, aad, al, pt, pl, out);
    return secure.toHex(out, pl + 16);
}

char* gcmOpen(char* keyHex, char* ivHex, char* aadHex, char* ctHex) {
    int kl = 0; int il = 0; int al = 0; int cl = 0;
    char* k = unhex(keyHex, &kl);
    char* iv = unhex(ivHex, &il);
    char* aad = unhex(aadHex, &al);
    char* ct = unhex(ctHex, &cl);
    char* out = alloc(cl + 16);
    if (!aes.open(aes.gcm(k, kl), iv, aad, al, ct, cl, out)) { return "rejected"; }
    return secure.toHex(out, cl - 16);
}

char* ccSeal(char* keyHex, char* ivHex, char* aadHex, char* ptHex) {
    int kl = 0; int il = 0; int al = 0; int pl = 0;
    char* k = unhex(keyHex, &kl);
    char* iv = unhex(ivHex, &il);
    char* aad = unhex(aadHex, &al);
    char* pt = unhex(ptHex, &pl);
    char* out = alloc(pl + 32);
    chacha.seal(k, iv, aad, al, pt, pl, out);
    return secure.toHex(out, pl + 16);
}

char* ccOpen(char* keyHex, char* ivHex, char* aadHex, char* ctHex) {
    int kl = 0; int il = 0; int al = 0; int cl = 0;
    char* k = unhex(keyHex, &kl);
    char* iv = unhex(ivHex, &il);
    char* aad = unhex(aadHex, &al);
    char* ct = unhex(ctHex, &cl);
    char* out = alloc(cl + 16);
    if (!chacha.open(k, iv, aad, al, ct, cl, out)) { return "rejected"; }
    return secure.toHex(out, cl - 16);
}

char* chainCheck(char* chainPem, char* rootPem, char* host) {
    x509.clearRoots();
    x509.addRootPem(rootPem);
    x509.Cert** chain = (x509.Cert**) alloc(64 * 8);
    int count = 0;
    // read the CERTIFICATE blocks of chainPem
    int at = 0;
    while (true) {
        int b = findText(chainPem + at, "-----BEGIN CERTIFICATE-----");
        if (b < 0) { break; }
        int s = at + b + 27;
        int e = findText(chainPem + s, "-----END CERTIFICATE-----");
        if (e < 0) { break; }
        char* text = alloc(e + 1);
        memcpy(text, chainPem + s, e);
        text[e] = 0;
        char* der = alloc(e);
        int n = encoding.base64Decode(text, der);
        chain[count] = x509.parse(der, n);
        if (chain[count] == null) { return "parse failed"; }
        count++;
        at = s + e + 25;
    }
    char* why = x509.verifyChain(chain, count, host, 1790000000);
    return (why == null) ? "trusted" : why;
}

int findText(char* hay, char* needle) {
    int nl = strlen(needle);
    for (int i = 0; hay[i] != 0; i++) {
        if (hay[i] == needle[0] && strncmp(hay + i, needle, nl) == 0) { return i; }
    }
    return -1;
}

int main() {
'''
src = prelude + '\n'.join(body) + '\n    printlnInt(bad);\n    return bad;\n}\n'
expected.append("0")
open(os.path.join(here, '..', 't127_crypto.a'), 'w').write(src)
open(os.path.join(here, '..', 't127_crypto.out'), 'w').write('\n'.join(expected) + '\n')
print("t127_crypto: %d checks" % (len(expected) - 1))
