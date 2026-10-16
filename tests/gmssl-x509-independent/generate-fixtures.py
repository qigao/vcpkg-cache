"""Regenerate public-only test fixtures; requires cryptography==46.0.4.
Keys are deterministic TEST-ONLY identities and are never written to disk.
Golden DER is consumed by tests without this dependency or any signing keys.
"""
import base64
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID, ObjectIdentifier

UTC = timezone.utc
D = lambda year: datetime(year, 1, 1, tzinfo=UTC)
certs = {}
keys = {}
cases = []

def key(name, p384=False):
    if name not in keys:
        # Public, reproducible test key material. NEVER use outside tests.
        scalar = int.from_bytes(hashlib.sha256(('gmssl-200-test-only:' + name).encode()).digest(), 'big') >> 1
        keys[name] = ec.derive_private_key(scalar or 1, ec.SECP384R1() if p384 else ec.SECP256R1())
    return keys[name]

def issue(name, issuer=None, *, ca=False, pathlen=None, ku_sign=None,
          eku=None, years=(2025, 2030), p384=False, sha384=False,
          unknown=None, dns='service.example.test', constraints=None):
    k = key(name, p384)
    issuer_name = issuer or name
    ik = key(issuer_name)
    dn = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, name)])
    issuer_dn = certs[issuer].subject if issuer else dn
    b = (x509.CertificateBuilder().subject_name(dn).issuer_name(issuer_dn)
         .public_key(k.public_key())
         .serial_number(int.from_bytes(hashlib.sha256(name.encode()).digest()[:16], 'big') >> 1)
         .not_valid_before(D(years[0])).not_valid_after(D(years[1])))
    b = b.add_extension(x509.BasicConstraints(ca=ca, path_length=pathlen), critical=True)
    b = b.add_extension(x509.KeyUsage(digital_signature=True,
        content_commitment=False, key_encipherment=False, data_encipherment=False,
        key_agreement=False, key_cert_sign=ca if ku_sign is None else ku_sign,
        crl_sign=ca, encipher_only=None, decipher_only=None), critical=True)
    b = b.add_extension(x509.SubjectKeyIdentifier.from_public_key(k.public_key()), critical=False)
    b = b.add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ik.public_key()), critical=False)
    if not ca:
        b = b.add_extension(x509.SubjectAlternativeName([x509.DNSName(dns)]), critical=False)
    if eku is not None or not ca:
        b = b.add_extension(x509.ExtendedKeyUsage([eku or ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
    if unknown is not None:
        b = b.add_extension(x509.UnrecognizedExtension(ObjectIdentifier('1.3.6.1.4.1.55555.200.1'), b'\x05\x00'), critical=unknown)
    if constraints is not None:
        b = b.add_extension(x509.NameConstraints(permitted_subtrees=[x509.DNSName(constraints)], excluded_subtrees=None), critical=True)
    certs[name] = b.sign(ik, hashes.SHA384() if sha384 else hashes.SHA256(), ecdsa_deterministic=True)
    return name

def case(name, chain, root='root', accept=True, error=None):
    cases.append(dict(id=name, chain=chain, root=root, accept=accept, openssl_error=error))

issue('root', ca=True, pathlen=3, years=(2020,2040))
issue('other-root', ca=True, pathlen=3, years=(2020,2040))
issue('issuer', 'root', ca=True, pathlen=1, years=(2025,2035))
issue('leaf', 'issuer')
case('valid-p256-sha256', ['leaf','issuer'])
case('untrusted-root', ['leaf','issuer'], root='other-root', accept=False, error=20)
for name, options, error in [
    ('issuer-not-ca', dict(ca=False), 79),
    ('issuer-no-keycertsign', dict(ca=True, pathlen=1, ku_sign=False), 32),
    ('issuer-client-eku', dict(ca=True, pathlen=1, eku=ExtendedKeyUsageOID.CLIENT_AUTH), 26),
    ('issuer-expired', dict(ca=True, pathlen=1, years=(2020,2021)), 10),
]:
    issue(name,'root',**options)
    leaf = issue(name+'-leaf',name)
    case(name,[leaf,name], accept=False,error=error)
issue('issuer-server-eku','root',ca=True,pathlen=1,eku=ExtendedKeyUsageOID.SERVER_AUTH)
issue('issuer-server-eku-leaf','issuer-server-eku')
case('valid-ca-server-eku',['issuer-server-eku-leaf','issuer-server-eku'])
for name, options, error in [
    ('leaf-client-eku', dict(eku=ExtendedKeyUsageOID.CLIENT_AUTH), 26),
    ('leaf-expired', dict(years=(2020,2021)), 10),
    ('leaf-not-yet-valid', dict(years=(2035,2036)), 9),
    ('leaf-unknown-critical', dict(unknown=True), 34),
]:
    issue(name,'issuer',**options)
    case(name,[name,'issuer'],accept=False,error=error)
issue('leaf-unknown-noncritical','issuer',unknown=False)
case('valid-unknown-noncritical',['leaf-unknown-noncritical','issuer'])
issue('limited-issuer','root',ca=True,pathlen=0)
issue('limited-leaf','limited-issuer')
case('valid-pathlen-zero-leaf',['limited-leaf','limited-issuer'])
issue('subca','limited-issuer',ca=True,pathlen=0)
issue('subca-leaf','subca')
case('pathlen-violation',['subca-leaf','subca','limited-issuer'],accept=False,error=25)
issue('name-issuer','root',ca=True,pathlen=0,constraints='.example.test')
issue('name-permitted','name-issuer')
issue('name-denied','name-issuer',dns='service.other.test')
case('valid-name-constraints',['name-permitted','name-issuer'])
case('name-constraints-violation',['name-denied','name-issuer'],accept=False,error=47)
issue('leaf-p256-sha384','issuer',sha384=True)
case('valid-p256-issuer-sha384',['leaf-p256-sha384','issuer'])
issue('p384-root',ca=True,pathlen=2,years=(2020,2040),p384=True,sha384=True)
issue('p384-issuer','p384-root',ca=True,pathlen=0,p384=True,sha384=True)
issue('p384-issuer-p256-leaf','p384-issuer',sha384=True)
case('valid-p384-issuer-p256-leaf',['p384-issuer-p256-leaf','p384-issuer'],root='p384-root')

encoded = {}
for name,c in certs.items():
    der = c.public_bytes(serialization.Encoding.DER)
    encoded[name] = dict(der=base64.b64encode(der).decode(), sha256=hashlib.sha256(der).hexdigest())
raw = bytearray(certs['leaf'].public_bytes(serialization.Encoding.DER))
raw[-1] ^= 1
encoded['leaf-tampered'] = dict(der=base64.b64encode(raw).decode(),sha256=hashlib.sha256(raw).hexdigest())
case('leaf-bad-signature',['leaf-tampered','issuer'],accept=False,error=7)
fixture = dict(schema=1, clock_window_utc=['2025-01-02T00:00:00+00:00','2029-12-31T00:00:00+00:00'],
               description='Public test certificates only; RFC 5280 path/purpose cases; not a complete TLS or WebPKI suite.',
               certificates=encoded,cases=cases)
Path(__file__).with_name('fixtures.json').write_text(json.dumps(fixture,indent=2)+'\n')
print(len(encoded),'certificates;',len(cases),'cases')
