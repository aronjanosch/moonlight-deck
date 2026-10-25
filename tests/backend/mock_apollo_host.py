#!/usr/bin/env python3
"""Loopback-only mock of an Apollo/Vibepollo/Sunshine host for exercising
Moonlight's GUI without a real host or a stream.

It implements the host side of PIN pairing (one-time PIN only), serverinfo,
applist with Vibepollo's synthetic control apps, box art, launch/resume
(recorded, then refused so no stream starts) and the text clipboard.

    uv run --with cryptography python tests/backend/mock_apollo_host.py \
        --flavor vibepollo --otp-pin 1234 --otp-passphrase secret

Add the host in Moonlight as 127.0.0.1:<http-port>. Requests are printed
with argument names only; values (hashes, certificates) are not logged.
"""

import argparse
import datetime
import hashlib
import http.server
import os
import ssl
import struct
import sys
import tempfile
import threading
import urllib.parse
import zlib

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.x509.oid import NameOID

CONTROL_UUID = "9a1c5a25-58fe-40e0-b9aa-7d3f0000000%d"
# Vibepollo src/remote_session.h: (id, uuid suffix, title)
VIBEPOLLO_CONTROLS = [
    (2147483501, 1, "Resume"),
    (2147483502, 2, "Disconnect Monitor"),
    (2147483503, 3, "Disconnect Input"),
    (2147483504, 4, "Terminate"),
    (2147483505, 5, "Remote Monitor"),
    (2147483506, 6, "Remote Input"),
]
GAMES = [(1001, "Desktop"), (1002, "Steam Big Picture"), (1003, "Racing Game")]

# Apollo src/crypto.h PERM: all inputs, clipboard set/read, list, view, launch
VIBEPOLLO_PERMISSIONS = (0x1F << 8) | (0x3 << 16) | (0x7 << 24)
APOLLO_PERMISSIONS = (0x1F << 8) | (0x1F << 16) | (0x7 << 24)


def make_cert(common_name):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=30))
            .sign(key, hashes.SHA256()))
    return key, cert


def aes_ecb(key, data, encrypt):
    cipher = Cipher(algorithms.AES(key), modes.ECB())
    op = cipher.encryptor() if encrypt else cipher.decryptor()
    return op.update(data) + op.finalize()


def png(rgb):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    width, height = 60, 80
    rows = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


class Host:
    def __init__(self, args):
        self.args = args
        self.key, self.cert = make_cert("MockHost")
        self.cert_pem = self.cert.public_bytes(serialization.Encoding.PEM)
        self.paired = False
        self.session = {}
        self.current_game = 0
        self.clipboard = "text from the mock host"
        self.launches = []
        self.lock = threading.Lock()

    def serverinfo(self, https):
        a = self.args
        paired = https and self.paired
        x = ['<?xml version="1.0" encoding="utf-8"?>', '<root status_code="200">',
             "<hostname>MockHost</hostname>", "<appversion>7.1.431.-1</appversion>",
             "<GfeVersion>3.23.0.74</GfeVersion>",
             "<uniqueid>00000000-0000-0000-0000-00000000%04d</uniqueid>" % a.http_port,
             "<HttpsPort>%d</HttpsPort>" % a.https_port, "<ExternalPort>%d</ExternalPort>" % a.http_port,
             "<MaxLumaPixelsHEVC>1869449984</MaxLumaPixelsHEVC>", "<LocalIP>127.0.0.1</LocalIP>",
             "<ServerCodecModeSupport>3843</ServerCodecModeSupport>",
             "<SupportedDisplayMode><DisplayMode><Width>1280</Width><Height>800</Height>"
             "<RefreshRate>60</RefreshRate></DisplayMode></SupportedDisplayMode>",
             "<PairStatus>%d</PairStatus>" % (1 if paired else 0),
             "<currentgame>%d</currentgame>" % (self.current_game if paired else 0),
             "<state>%s</state>" % ("SUNSHINE_SERVER_BUSY" if self.current_game else "SUNSHINE_SERVER_FREE")]
        if a.flavor != "sunshine":
            x += ["<VirtualDisplayCapable>true</VirtualDisplayCapable>",
                  "<VirtualDisplayDriverReady>true</VirtualDisplayDriverReady>"]
            if a.flavor == "vibepollo":
                x.append("<VirtualDisplayHDRCapable>true</VirtualDisplayHDRCapable>")
            if paired:
                perm = VIBEPOLLO_PERMISSIONS if a.flavor == "vibepollo" else APOLLO_PERMISSIONS
                x.append("<mac>02:00:00:00:00:01</mac>")
                if a.flavor == "apollo":
                    x.append("<ServerCommand>Lock Screen</ServerCommand>")
                x.append("<Permission>%d</Permission>" % perm)
            else:
                x += ["<mac>00:00:00:00:00:00</mac>", "<Permission>0</Permission>"]
        else:
            x.append("<mac>00:00:00:00:00:00</mac>")
        x.append("</root>")
        return "\n".join(x)

    def applist(self):
        x = ['<?xml version="1.0" encoding="utf-8"?>', '<root status_code="200">']
        apps = [(i, "", t) for i, t in GAMES]
        if self.args.flavor == "vibepollo":
            apps += [(i, CONTROL_UUID % n, t) for i, n, t in VIBEPOLLO_CONTROLS]
        for i, uuid, title in apps:
            x.append("<App><IsHdrSupported>0</IsHdrSupported><AppTitle>%s</AppTitle>"
                     "%s<ID>%d</ID></App>" % (title, "<UUID>%s</UUID>" % uuid if uuid else "", i))
        x.append("</root>")
        return "\n".join(x)

    def pair(self, q, https):
        def xml(body, status=200, message=None):
            attr = ' status_code="%d"' % status + (' status_message="%s"' % message if message else "")
            return "<root%s>%s</root>" % (attr, body)

        s = self.session
        if q.get("phrase") == "getservercert":
            if "otpauth" not in q:
                # A stock host would wait for the PIN to be typed in its web UI
                return xml("", 503, "Mock host only supports one-time PIN pairing")
            if self.args.flavor == "sunshine":
                return xml("", 503, "Mock Sunshine host ignores otpauth")
            s.clear()
            s["salt"] = q["salt"]
            s["clientcert"] = x509.load_pem_x509_certificate(bytes.fromhex(q["clientcert"]))
            expected = hashlib.sha256((self.args.otp_pin + q["salt"] + self.args.otp_passphrase).encode()).hexdigest().upper()
            # Like Apollo: answer a wrong hash, and a missing or expired PIN
            # (whose 503 is overwritten), as if it were right, with a random PIN
            ok = bool(self.args.otp_pin) and q["otpauth"] == expected
            pin = self.args.otp_pin if ok else os.urandom(8).hex()
            print("  otpauth", "matches" if ok else "does not match or no PIN is active", flush=True)
            s["key"] = hashlib.sha256(bytes.fromhex(s["salt"]) + pin.encode()).digest()[:16]
            return xml("<paired>1</paired><plaincert>%s</plaincert>" % self.cert_pem.hex())
        if q.get("phrase") == "pairchallenge":
            return xml("<paired>%d</paired>" % (1 if https and self.paired else 0))
        if "key" not in s:
            return xml("", 400, "Invalid uniqueid")
        if "clientchallenge" in q:
            challenge = aes_ecb(s["key"], bytes.fromhex(q["clientchallenge"]), False)
            s["serversecret"] = os.urandom(16)
            s["serverchallenge"] = os.urandom(16)
            digest = hashlib.sha256(challenge + self.cert.signature + s["serversecret"]).digest()
            response = aes_ecb(s["key"], digest + s["serverchallenge"], True)
            return xml("<paired>1</paired><challengeresponse>%s</challengeresponse>" % response.hex())
        if "serverchallengeresp" in q:
            s["clienthash"] = aes_ecb(s["key"], bytes.fromhex(q["serverchallengeresp"]), False)[:32]
            signature = self.key.sign(s["serversecret"], padding.PKCS1v15(), hashes.SHA256())
            return xml("<paired>1</paired><pairingsecret>%s</pairingsecret>" % (s["serversecret"] + signature).hex())
        if "clientpairingsecret" in q:
            secret = bytes.fromhex(q["clientpairingsecret"])
            clientsecret, signature = secret[:16], secret[16:]
            ok = hashlib.sha256(s["serverchallenge"] + s["clientcert"].signature + clientsecret).digest() == s["clienthash"]
            try:
                s["clientcert"].public_key().verify(signature, clientsecret, padding.PKCS1v15(), hashes.SHA256())
            except Exception:
                ok = False
            self.paired = ok
            return xml("<paired>%d</paired>" % (1 if ok else 0))
        return xml("", 404, "Invalid pairing request")


def handler_for(host, https):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
            pass

        def reply(self, body, content_type="application/xml", status=200):
            data = body if isinstance(body, bytes) else body.encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(data)
            self.close_connection = True

        def handle_any(self, method):
            url = urllib.parse.urlsplit(self.path)
            q = dict(urllib.parse.parse_qsl(url.query, keep_blank_values=True))
            print("%s %s %s %s" % ("https" if https else "http", method, url.path, sorted(q)), flush=True)
            with host.lock:
                if url.path == "/serverinfo":
                    return self.reply(host.serverinfo(https))
                if url.path == "/pair":
                    return self.reply(host.pair(q, https))
                if url.path == "/unpair":
                    host.paired = False
                    return self.reply('<root status_code="200"></root>')
                if not https or not host.paired:
                    return self.reply('<root status_code="401" status_message="The client is not authorized"></root>')
                if url.path == "/applist":
                    return self.reply(host.applist())
                if url.path == "/appasset":
                    appid = int(q.get("appid", "0"))
                    return self.reply(png((40 + appid % 7 * 30, 90, 160)), "image/png")
                if url.path in ("/launch", "/resume"):
                    extras = {k: q[k] for k in ("appid", "virtualDisplay") if k in q}
                    host.launches.append((url.path, extras))
                    print("  launch arguments of interest:", extras, flush=True)
                    if host.args.launch_log:
                        with open(host.args.launch_log, "a") as f:
                            f.write("%s %s\n" % (url.path, extras))
                    return self.reply('<root status_code="503" status_message="Mock host recorded the launch and does not stream"></root>')
                if url.path == "/cancel":
                    host.current_game = 0
                    return self.reply('<root status_code="200"><cancel>1</cancel></root>')
                if url.path == "/actions/clipboard":
                    if q.get("type") != "text":
                        return self.reply("Unsupported clipboard type", "text/plain", 400)
                    if method == "GET":
                        return self.reply(host.clipboard, "text/plain")
                    length = int(self.headers.get("Content-Length", "0"))
                    host.clipboard = self.rfile.read(length).decode("utf-8")
                    return self.reply("", "text/plain")
            return self.reply('<root status_code="404"></root>', status=404)

        def do_GET(self):
            self.handle_any("GET")

        def do_POST(self):
            self.handle_any("POST")

    return Handler


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--flavor", choices=["sunshine", "apollo", "vibepollo"], default="vibepollo")
    p.add_argument("--http-port", type=int, default=48989)
    p.add_argument("--https-port", type=int, default=48984)
    p.add_argument("--otp-pin", default="", help="active one-time PIN (4 digits); empty = none created")
    p.add_argument("--otp-passphrase", default="")
    p.add_argument("--running-game", type=int, default=0)
    p.add_argument("--launch-log", default="")
    args = p.parse_args()

    host = Host(args)
    host.current_game = args.running_game

    http_server = http.server.ThreadingHTTPServer(("127.0.0.1", args.http_port), handler_for(host, False))
    https_server = http.server.ThreadingHTTPServer(("127.0.0.1", args.https_port), handler_for(host, True))
    with tempfile.TemporaryDirectory() as tmp:
        cert_path, key_path = os.path.join(tmp, "cert.pem"), os.path.join(tmp, "key.pem")
        with open(cert_path, "wb") as f:
            f.write(host.cert_pem)
        with open(key_path, "wb") as f:
            f.write(host.key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                           serialization.NoEncryption()))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert_path, key_path)
        # Client certificates are self-signed; this mock trusts whoever paired
        context.verify_mode = ssl.CERT_NONE
        https_server.socket = context.wrap_socket(https_server.socket, server_side=True)

    for server in (http_server, https_server):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print("mock %s host on http://127.0.0.1:%d and https port %d" % (args.flavor, args.http_port, args.https_port), flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
