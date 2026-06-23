#!/usr/bin/env bash
set -euo pipefail

# Creates a persistent, self-signed code-signing identity in the login keychain.
#
# Why this matters: macOS ties the Accessibility (and Input Monitoring) grant to a
# stable code identity. An ad-hoc signature ("codesign --sign -") has no stable
# designated requirement, so TCC keys the grant to the binary's cdhash — which
# changes on every rebuild, silently revoking the permission you just granted.
#
# A self-signed certificate gives the bundle a stable designated requirement
# (identifier + certificate leaf), so once you grant Accessibility to Vocal.app it
# keeps working across rebuilds. Run this once; build_and_run.sh picks it up
# automatically afterward.

IDENTITY_NAME="Vocal Self-Signed"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# Note: list WITHOUT -v. A self-signed cert is untrusted (CSSMERR_TP_NOT_TRUSTED),
# so it never appears under "-v" (valid only) — but codesign can still sign with it,
# and that is all macOS needs for a stable designated requirement.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  echo "Signing identity '$IDENTITY_NAME' already exists. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = Vocal Self-Signed
[v3]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
CNF

echo "Generating self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 -export -out "$TMP/vocal.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -passout pass:vocal -name "$IDENTITY_NAME" >/dev/null 2>&1

echo "Importing into login keychain (codesign is pre-authorized to use it)..."
security import "$TMP/vocal.p12" -k "$KEYCHAIN" -P vocal -T /usr/bin/codesign -A

# Best-effort: suppress the keychain access prompt on first codesign use. Harmless
# if it fails (you may just get a one-time "Always Allow" dialog instead).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo
echo "Done. Verify with:  security find-identity -p codesigning   (untrusted is expected)"
echo "Then rebuild:       ./script/build_and_run.sh --verify"
echo "Re-grant Accessibility to Vocal.app once; it will persist across future rebuilds."
