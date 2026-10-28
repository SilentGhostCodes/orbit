#!/usr/bin/env python3
"""
Builds assets/happ/keys.json for HappLink from LeeeeT/happ-decryptor.

    python3 tool/happ_keys.py <happ-decryptor checkout>

Reads the crypt..crypt4 keys from src/decrypt.js and the crypt5 marker keys from
public/data/crypt5-keys.json, and writes each RSA key as hex n, d, p, q, so the app
needs no DER parsing. Run it again when happ-decryptor adds crypt5 markers.
"""

import base64
import json
import re
import sys
from pathlib import Path

from cryptography.hazmat.primitives.serialization import load_der_private_key


def numbers(b64: str) -> dict:
    key = load_der_private_key(base64.b64decode(b64), password=None)
    n = key.private_numbers()
    return {"n": f"{n.public_numbers.n:x}", "d": f"{n.d:x}", "p": f"{n.p:x}", "q": f"{n.q:x}"}


def main() -> None:
    src = Path(sys.argv[1])
    js = (src / "src/decrypt.js").read_text("utf-8")
    block = js[js.index("PKCS1_KEYS_B64 = [") : js.index("];", js.index("PKCS1_KEYS_B64 = ["))]
    legacy = re.findall(r'"([A-Za-z0-9+/=]+)"', block)
    if len(legacy) != 4:
        sys.exit(f"expected 4 legacy keys, found {len(legacy)}")
    crypt5 = json.loads((src / "public/data/crypt5-keys.json").read_text("utf-8"))

    out = {
        "legacy": {name: numbers(b64) for name, b64 in zip(["crypt", "crypt2", "crypt3", "crypt4"], legacy)},
        "crypt5": {marker: numbers(b64) for marker, b64 in sorted(crypt5.items())},
    }
    dest = Path(__file__).resolve().parent.parent / "assets/happ/keys.json"
    dest.write_text(json.dumps(out, separators=(",", ":")), "utf-8")
    print(f"{dest}: 4 legacy, {len(out['crypt5'])} crypt5 keys")


if __name__ == "__main__":
    main()
