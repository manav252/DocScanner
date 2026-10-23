"""Create a local demo account and upload a sample 2-page PDF.

    python scripts/seed_demo.py [http://localhost:8000]

Demo credentials (local development only): demo@example.com / demo-password
"""

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

import img2pdf

API = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
EMAIL, PASSWORD = "demo@example.com", "demo-password"
FIXTURES = Path(__file__).resolve().parents[2] / "shared" / "test_fixtures"


def call(method, path, body=None, token=None, ctype="application/json"):
    headers = {"Content-Type": ctype, **({"Authorization": f"Bearer {token}"} if token else {})}
    req = urllib.request.Request(API + path, data=body, method=method, headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}")


cred = json.dumps({"email": EMAIL, "password": PASSWORD}).encode()
try:
    token = call("POST", "/auth/register", cred)["access_token"]
    print(f"created {EMAIL}")
except urllib.error.HTTPError:
    token = call("POST", "/auth/login", cred)["access_token"]
    print(f"{EMAIL} already exists")

pdf = img2pdf.convert(
    [(FIXTURES / "strong_perspective.jpg").read_bytes(), (FIXTURES / "narrow_receipt.jpg").read_bytes()]
)
boundary = "----docscanner-seed"
body = (
    (
        f'--{boundary}\r\nContent-Disposition: form-data; name="files"; filename="Sample contract.pdf"\r\n'
        f"Content-Type: application/pdf\r\n\r\n"
    ).encode()
    + pdf
    + f"\r\n--{boundary}--\r\n".encode()
)
doc = call("POST", "/documents/upload", body, token, f"multipart/form-data; boundary={boundary}")
print(f"uploaded '{doc['title']}' ({len(doc['pages'])} pages)")
