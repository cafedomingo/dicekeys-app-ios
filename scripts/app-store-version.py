#!/usr/bin/env python3
"""Points the app's pending App Store version at a build just uploaded to App Store Connect.

testflight.sh gives every upload that day's date as its version, so the App Store version
waiting for submission would fall behind with each upload. Once Apple has processed the
build, this renames that version to the build's version and attaches the build. When no
version is open for editing it creates one, unless a version is in review or awaiting release,
which it leaves alone.

Run:  set -a; source .env; set +a
      python3 scripts/app-store-version.py BUNDLE_ID VERSION BUILD_NUMBER
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
# States in which a version is on its way to the store; no new version can be created then.
IN_FLIGHT_STATES = {
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "READY_FOR_REVIEW",
    "WAITING_FOR_EXPORT_COMPLIANCE",
    "PENDING_DEVELOPER_RELEASE",
    "PENDING_APPLE_RELEASE",
    "ACCEPTED",
    "PROCESSING_FOR_DISTRIBUTION",
}
# Apple usually processes a build within a few minutes, sometimes within half an hour.
PROCESSING_TIMEOUT_SECONDS = 45 * 60
POLL_SECONDS = 30
REQUEST_TIMEOUT_SECONDS = 60
TOKEN_LIFETIME_SECONDS = 10 * 60
MAX_PAGE = 200


class TransientError(Exception):
    """A request that failed in a way worth trying again: a timeout, a dropped connection, 429 or 5xx."""


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
    command = ["openssl", "dgst", "-sha256", "-sign", key]
    try:
        der = subprocess.run(command, input=signed, capture_output=True, check=True)
    except subprocess.CalledProcessError as error:
        sys.exit(f"openssl could not sign with {key}: {error.stderr.decode().strip()}")
    return f"{header}.{payload}.{base64url(raw_signature(der.stdout))}"


def request(method, path, query=None, body=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode() if body else None
    headers = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, data, headers, method=method), timeout=REQUEST_TIMEOUT_SECONDS
        ) as response:
            content = response.read()
    except urllib.error.HTTPError as error:
        if error.code == 429 or error.code >= 500:
            raise TransientError(f"{error.code} from {method} {path}") from error
        sys.exit(f"App Store Connect refused {method} {path}: {error.code} {error.read().decode()}")
    except (urllib.error.URLError, TimeoutError) as error:
        raise TransientError(f"{method} {path}: {error}") from error
    return json.loads(content) if content else {}


def app_id(bundle_id):
    apps = request("GET", "/apps", {"filter[bundleId]": bundle_id})["data"]
    app = next((a["id"] for a in apps if a["attributes"]["bundleId"] == bundle_id), None)
    if app is None:
        sys.exit(f"No app with bundle id {bundle_id} in App Store Connect.")
    return app


def processed_build(app, version_string, build_number, rerun):
    query = {"filter[app]": app, "filter[version]": build_number, "filter[preReleaseVersion.version]": version_string}
    deadline = time.time() + PROCESSING_TIMEOUT_SECONDS
    while time.time() < deadline:
        try:
            builds = request("GET", "/builds", query)["data"]
            state = builds[0]["attributes"]["processingState"] if builds else "NOT YET LISTED"
        except TransientError as error:
            state = f"unknown ({error})"
        if state == "VALID":
            return builds[0]["id"]
        if state in {"FAILED", "INVALID"}:
            sys.exit(f"Build {build_number} failed processing ({state}); the App Store version is unchanged.")
        print(f"Build {build_number}: {state}; checking again in {POLL_SECONDS} s.")
        time.sleep(POLL_SECONDS)
    minutes = PROCESSING_TIMEOUT_SECONDS // 60
    sys.exit(f"Build {build_number} was not processed within {minutes} minutes. Once it is, run:\n  {rerun}")


def pending_version(app, version_string):
    """The ID of the App Store version to point at the build, renamed or created, or None to leave alone."""
    versions = request("GET", f"/apps/{app}/appStoreVersions", {"filter[platform]": "IOS", "limit": MAX_PAGE})["data"]
    states = {v["id"]: v["attributes"]["appVersionState"] for v in versions}
    editable = next((v for v in versions if states[v["id"]] in EDITABLE_STATES), None)
    if editable is None:
        in_flight = next((v for v in versions if states[v["id"]] in IN_FLIGHT_STATES), None)
        if in_flight is not None:
            name = in_flight["attributes"]["versionString"]
            print(f"App Store version {name} is {states[in_flight['id']]}; leaving it alone.")
            return None
        print(f"No App Store version is open for editing; creating {version_string}.")
        attributes = {"platform": "IOS", "versionString": version_string}
        relationships = {"app": {"data": {"type": "apps", "id": app}}}
        body = {"data": {"type": "appStoreVersions", "attributes": attributes, "relationships": relationships}}
        return request("POST", "/appStoreVersions", body=body)["data"]["id"]
    current = editable["attributes"]["versionString"]
    if current != version_string:
        print(f"Renaming App Store version {current} to {version_string}.")
        attributes = {"versionString": version_string}
        body = {"data": {"type": "appStoreVersions", "id": editable["id"], "attributes": attributes}}
        request("PATCH", f"/appStoreVersions/{editable['id']}", body=body)
    return editable["id"]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    bundle_id, version_string, build_number = sys.argv[1:]
    arguments = f"{bundle_id} {version_string} {build_number}"
    rerun = f"set -a; source .env; set +a; python3 scripts/app-store-version.py {arguments}"
    try:
        app = app_id(bundle_id)
        build = processed_build(app, version_string, build_number, rerun)
        version = pending_version(app, version_string)
        if version is None:
            return
        build_data = {"data": {"type": "builds", "id": build}}
        request("PATCH", f"/appStoreVersions/{version}/relationships/build", body=build_data)
    except TransientError as error:
        sys.exit(f"App Store Connect did not answer ({error}). Run again:\n  {rerun}")
    print(f"App Store version {version_string} now uses build {build_number}.")


if __name__ == "__main__":
    main()
