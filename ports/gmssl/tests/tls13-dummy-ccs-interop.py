#!/usr/bin/env python3
"""Installed GmSSL TLS 1.3 server / independent Python(OpenSSL) mTLS oracle.

Default OpenSSL TLS 1.3 emits an RFC8446 D.4 dummy ChangeCipherSpec after
ServerHello; this must NOT produce unexpected_message. No TLS verification
bypass, plaintext fallback, or changed client-side middlebox policy.
"""
from __future__ import annotations

import pathlib
import socket
import ssl
import subprocess
import sys
import tempfile
import time


def cmd(*argv: str) -> None:
    subprocess.run(argv, check=True, stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, timeout=20)


def fixture(root: pathlib.Path) -> tuple[pathlib.Path, ...]:
    ca, cak = root / "ca.crt", root / "ca.key"
    cmd("openssl", "req", "-x509", "-newkey", "ec",
        "-pkeyopt", "ec_paramgen_curve:prime256v1",
        "-sha256", "-nodes", "-days", "2",
        "-subj", "/CN=CCS Test CA", "-keyout", str(cak),
        "-out", str(ca),
        "-addext", "basicConstraints=critical,CA:TRUE,pathlen:0",
        "-addext", "keyUsage=critical,keyCertSign,cRLSign")

    def leaf(role: str) -> tuple[pathlib.Path, pathlib.Path]:
        cert, key = root / (role+".crt"), root / (role+".key")
        csr, ext = root / (role+".csr"), root / (role+".ext")
        ext.write_text(
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature\n"
            "extendedKeyUsage=" + (
                "serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n"
                if role == "server" else "clientAuth\n"),
            encoding="ascii")
        cmd("openssl", "req", "-newkey", "ec",
            "-pkeyopt", "ec_paramgen_curve:prime256v1",
            "-sha256", "-nodes", "-subj", "/CN="+role,
            "-keyout", str(key), "-out", str(csr))
        cmd("openssl", "x509", "-req", "-in", str(csr),
            "-CA", str(ca), "-CAkey", str(cak), "-CAcreateserial",
            "-sha256", "-days", "2", "-extfile", str(ext),
            "-out", str(cert))
        return cert, key

    server, skey = leaf("server")
    client, ckey = leaf("client")
    cmd("openssl", "verify", "-CAfile", str(ca),
        "-purpose", "sslserver", "-verify_hostname",
        "localhost", str(server))
    cmd("openssl", "verify", "-CAfile", str(ca),
        "-purpose", "sslclient", str(client))
    return ca, server, skey, client, ckey


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def check_one(gmssl: pathlib.Path, root: pathlib.Path,
              fixture_files: tuple[pathlib.Path, ...],
              use_middlebox: bool) -> None:
    ca, server, skey, client, ckey = fixture_files
    port = free_port()
    log = root / ("default-ccs" if use_middlebox else "no-ccs")
    with log.open("w", encoding="utf-8") as output:
        server_args = [
            str(gmssl), "tls13_server",
            "-port", str(port),
            "-cert", str(server), "-key", str(skey),
            "-pass", "",
            "-cacert", str(ca), "-cert_request",
            "-cipher_suite", "TLS_AES_128_GCM_SHA256",
            "-supported_group", "prime256v1",
            "-sig_alg", "ecdsa_secp256r1_sha256",
        ]
        daemon = subprocess.Popen(
            server_args, stdout=output, stderr=subprocess.STDOUT)
        try:
            # The native GmSSL CLI handles one accepted connection per run.
            time.sleep(0.65)
            if daemon.poll() is not None:
                raise RuntimeError("GmSSL server terminated before connection")
            context = ssl.create_default_context(cafile=str(ca))
            context.minimum_version = ssl.TLSVersion.TLSv1_3
            context.maximum_version = ssl.TLSVersion.TLSv1_3
            context.set_ecdh_curve("prime256v1")
            context.load_cert_chain(str(client), str(ckey))
            if not use_middlebox:
                context.options &= ~ssl.OP_ENABLE_MIDDLEBOX_COMPAT
            with socket.create_connection(("127.0.0.1", port), timeout=5) as tcp:
                with context.wrap_socket(tcp, server_hostname="localhost") as tls:
                    if tls.version() != "TLSv1.3":
                        raise AssertionError("TLS version downgrade")
                    if tls.cipher()[0] != "TLS_AES_128_GCM_SHA256":
                        raise AssertionError("TLS cipher mismatch")
                    tls.settimeout(4)
                    tls.sendall(b"gmssl-ccs-test\n")
                    echo = tls.recv(128)
                    if b"gmssl-ccs-test" not in echo:
                        raise AssertionError(
                            "validated client payload did not reach server")
            print("gmssl.tls13_dummy_ccs_interop: PASS "
                  + ("default OpenSSL CCS" if use_middlebox
                     else "no middlebox CCS"), flush=True)
        finally:
            if daemon.poll() is None:
                daemon.terminate()
                try:
                    daemon.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    daemon.kill()
                    daemon.wait(timeout=3)
            if daemon.returncode not in (0, -15, 143):
                log_content = log.read_text(encoding="utf-8", errors="replace")
                print("GmSSL test server diagnostic (tail): "
                      + log_content[-1400:], file=sys.stderr)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: tls13-dummy-ccs-interop.py gmssl-bin output-dir")
    gmssl = pathlib.Path(sys.argv[1]).resolve()
    root = pathlib.Path(sys.argv[2]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="gmssl-tls13-ccs-", dir=str(root)) as work:
        folder = pathlib.Path(work)
        material = fixture(folder)
        # Control on identical CA/leaf/key suite, then default OpenSSL.
        check_one(gmssl, folder, material, use_middlebox=False)
        check_one(gmssl, folder, material, use_middlebox=True)


if __name__ == "__main__":
    main()
