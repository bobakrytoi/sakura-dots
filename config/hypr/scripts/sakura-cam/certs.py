# sakura mono - sakura-cam: a tiny local certificate authority, so Safari on the iPhone gets a real HTTPS
# page (getUserMedia needs a secure context). The CA is made once and installed on the phone once
# (profile + "Certificate Trust Settings"); the server certificate is re-issued from it whenever the PC's
# addresses change (Wi-Fi <-> USB tethering), so the phone never has to trust anything again.
import datetime
import ipaddress
import os

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

DIR = os.path.expanduser("~/.local/share/sakura/cam")
CA_CRT = os.path.join(DIR, "sakura-cam-ca.crt")
CA_KEY = os.path.join(DIR, "sakura-cam-ca.key")
SRV_CRT = os.path.join(DIR, "server.crt")
SRV_KEY = os.path.join(DIR, "server.key")
SRV_NAMES = os.path.join(DIR, "server.names")


def _now():
    return datetime.datetime.now(datetime.timezone.utc)


def _write(path, data, private=False):
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600 if private else 0o644)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def ensure_ca():
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    if os.path.exists(CA_CRT) and os.path.exists(CA_KEY):
        with open(CA_KEY, "rb") as f:
            key = serialization.load_pem_private_key(f.read(), None)
        with open(CA_CRT, "rb") as f:
            crt = x509.load_pem_x509_certificate(f.read())
        if crt.not_valid_after_utc > _now() + datetime.timedelta(days=30):
            return key, crt
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Sakura Cam local CA"),
                      x509.NameAttribute(NameOID.ORGANIZATION_NAME, "sakura mono")])
    crt = (x509.CertificateBuilder()
           .subject_name(name).issuer_name(name)
           .public_key(key.public_key())
           .serial_number(x509.random_serial_number())
           .not_valid_before(_now() - datetime.timedelta(days=1))
           .not_valid_after(_now() + datetime.timedelta(days=3650))
           .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
           .add_extension(x509.KeyUsage(digital_signature=True, key_cert_sign=True, crl_sign=True,
                                        content_commitment=False, key_encipherment=False, data_encipherment=False,
                                        key_agreement=False, encipher_only=False, decipher_only=False), critical=True)
           .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
           .sign(key, hashes.SHA256()))
    _write(CA_KEY, key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                     serialization.NoEncryption()), private=True)
    _write(CA_CRT, crt.public_bytes(serialization.Encoding.PEM))
    for p in (SRV_CRT, SRV_KEY, SRV_NAMES):        # a new CA invalidates the old server cert
        try:
            os.remove(p)
        except OSError:
            pass
    return key, crt


def ca_der():
    with open(CA_CRT, "rb") as f:
        return x509.load_pem_x509_certificate(f.read()).public_bytes(serialization.Encoding.DER)


def ensure_server(names, ips):
    """Server cert for these DNS names + IPs. Returns True when it was (re)issued."""
    want = ",".join(sorted(names) + sorted(ips))
    try:
        with open(SRV_NAMES) as f:
            have = f.read().strip()
        with open(SRV_CRT, "rb") as f:
            old = x509.load_pem_x509_certificate(f.read())
        if have == want and os.path.exists(SRV_KEY) and old.not_valid_after_utc > _now() + datetime.timedelta(days=20):
            return False
    except OSError:
        pass
    ca_key, ca_crt = ensure_ca()
    key = ec.generate_private_key(ec.SECP256R1())
    san = [x509.DNSName(n) for n in names] + [x509.IPAddress(ipaddress.ip_address(i)) for i in ips]
    crt = (x509.CertificateBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, names[0] if names else "sakura-cam")]))
           .issuer_name(ca_crt.subject)
           .public_key(key.public_key())
           .serial_number(x509.random_serial_number())
           .not_valid_before(_now() - datetime.timedelta(days=1))
           .not_valid_after(_now() + datetime.timedelta(days=360))      # iOS: <= 825 days for private CAs
           .add_extension(x509.SubjectAlternativeName(san), critical=False)
           .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
           .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
           .add_extension(x509.KeyUsage(digital_signature=True, key_encipherment=False, key_cert_sign=False,
                                        crl_sign=False, content_commitment=False, data_encipherment=False,
                                        key_agreement=True, encipher_only=False, decipher_only=False), critical=True)
           .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False)
           .sign(ca_key, hashes.SHA256()))
    _write(SRV_KEY, key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()), private=True)
    _write(SRV_CRT, crt.public_bytes(serialization.Encoding.PEM) + ca_crt.public_bytes(serialization.Encoding.PEM))
    _write(SRV_NAMES, want.encode())
    return True
