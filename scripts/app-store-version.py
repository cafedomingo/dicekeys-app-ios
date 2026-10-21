#!/usr/bin/env python3
"""Points the app's pending App Store version at a build just uploaded to App Store Connect.

testflight.sh gives every upload that day's date as its version, so the App Store version
waiting for submission would fall behind with each upload. This renames that version to the
build's version and, once Apple has processed the build, attaches the build to it. When no
version is open for editing, it creates one.

Run:  python3 scripts/app-store-version.py BUNDLE_ID VERSION BUILD_NUMBER
      (standard library and openssl only)

Needs the App Store Connect API key that testflight.sh uses: ASC_KEY_PATH, ASC_KEY_ID and
ASC_ISSUER_ID in the environment.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
# App Store version states in which its version string and build can still be changed.
EDITABLE_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
# Apple usually processes a build within a few minutes, sometimes within half an hour.
PROCESSING_TIMEOUT_SECONDS = 45 * 60
POLL_SECONDS = 30
TOKEN_LIFETIME_SECONDS = 10 * 60


def base64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def raw_signature(der):
    """The 64-byte r || s an ES256 JWT carries, from the DER signature openssl writes."""
    position = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        length = der[position + 1]
        parts.append(der[position + 2 : position + 2 + length].lstrip(b"\0").rjust(32, b"\0"))
        position += 2 + length
    return b"".join(parts)


def token():
    header = base64url(json.dumps({"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}).encode())
    now = int(time.time())
    claims = {
        "iss": os.environ["ASC_ISSUER_ID"],
        "iat": now,
        "exp": now + TOKEN_LIFETIME_SECONDS,
        "aud": "appstoreconnect-v1",
    }
    payload = base64url(json.dumps(claims).encode())
    signed = f"{header}.{payload}".encode()
    key = os.path.expanduser(os.environ["ASC_KEY_PATH"])
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=signed, capture_output=True, check=True)
    return f"{header}.{payload}.{base64url(raw_signature(der.stdout))}"


def request(method, path, query=None, body=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode() if body else None
    headers = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data, headers, method=method)) as response:
            content = response.read()
    except urllib.error.HTTPError as error:
        sys.exit(f"App Store Connect refused {method} {path}: {error.code} {error.read().decode()}")
    return json.loads(content) if content else {}


def app_id(bundle_id):
    apps = request("GET", "/apps", {"filter[bundleId]": bundle_id})["data"]
    if not apps:
        sys.exit(f"No app with bundle id {bundle_id} in App Store Connect.")
    return apps[0]["id"]


def editable_version(app):
    versions = request("GET", f"/apps/{app}/appStoreVersions", {"filter[platform]": "IOS"})["data"]
    return next((v for v in versions if v["attributes"]["appVersionState"] in EDITABLE_STATES), None)


def set_version(app, version_string):
    version = editable_version(app)
    if version is None:
        body = {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version_string},
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        }
        print(f"No App Store version is open for editing; creating {version_string}.")
        return request("POST", "/appStoreVersions", body=body)["data"]["id"]
    if version["attributes"]["versionString"] != version_string:
        print(f"Renaming App Store version {version['attributes']['versionString']} to {version_string}.")
        attributes = {"versionString": version_string}
        body = {"data": {"type": "appStoreVersions", "id": version["id"], "attributes": attributes}}
        request("PATCH", f"/appStoreVersions/{version['id']}", body=body)
    return version["id"]


def processed_build(app, version_string, build_number):
    query = {"filter[app]": app, "filter[version]": build_number, "filter[preReleaseVersion.version]": version_string}
    deadline = time.time() + PROCESSING_TIMEOUT_SECONDS
    while time.time() < deadline:
        builds = request("GET", "/builds", query)["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT YET LISTED"
        if state == "VALID":
            return builds[0]["id"]
        if state in {"FAILED", "INVALID"}:
            sys.exit(f"Build {build_number} failed processing ({state}); the App Store version keeps its build.")
        print(f"Build {build_number}: {state}; checking again in {POLL_SECONDS} s.")
        time.sleep(POLL_SECONDS)
    minutes = PROCESSING_TIMEOUT_SECONDS // 60
    sys.exit(f"Build {build_number} was not processed within {minutes} minutes; run this again later.")


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    bundle_id, version_string, build_number = sys.argv[1:]
    app = app_id(bundle_id)
    version = set_version(app, version_string)
    build = processed_build(app, version_string, build_number)
    request("PATCH", f"/appStoreVersions/{version}/relationships/build", body={"data": {"type": "builds", "id": build}})
    print(f"App Store version {version_string} now uses build {build_number}.")


if __name__ == "__main__":
    main()
