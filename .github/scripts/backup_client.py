"""Mimics the app's «حفظ نسخة» in CI: send only an ephemeral P-256 public key,
unwrap the backup key locally and re-wrap it with the password (QBK2).
Usage: backup_client.py <url> <token> <password> <out.qbk>"""
import base64, hashlib, json, os, struct, sys, urllib.request

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

url, token, password, out = sys.argv[1:5]
device = ec.generate_private_key(ec.SECP256R1())
public = device.public_key().public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
body = json.dumps({"publicKey": base64.b64encode(public).decode()}).encode()
assert password.encode() not in body
request = urllib.request.Request(url + "/api/v1/admin/backups", data=body, method="POST",
                                 headers={"content-type": "application/json", "authorization": "Bearer " + token})
wire = urllib.request.urlopen(request, timeout=600).read()
assert wire[:4] == b"QBKW", wire[:64]

server = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), wire[4:69])
kek = hashlib.sha256(device.exchange(ec.ECDH(), server) + b"QBK-WRAP-1").digest()
data_key = AESGCM(kek).decrypt(wire[69:81], wire[81:113] + wire[113:129], b"QBKW")

rounds, salt, nonce = 100_000, os.urandom(16), os.urandom(12)
pkey = PBKDF2HMAC(hashes.SHA256(), 32, salt, rounds).derive(password.encode())
sealed = AESGCM(pkey).encrypt(nonce, data_key, b"QBK2")
with open(out, "wb") as f:
    f.write(b"QBK2" + struct.pack(">i", rounds) + salt + nonce + sealed + wire[129:])
print("backup saved:", out, len(wire), "bytes")
