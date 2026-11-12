#!/usr/bin/env bash
# Imports the Developer ID Application certificate into an ephemeral keychain.
# Needs DEVELOPER_ID_APP_P12_BASE64, DEVELOPER_ID_APP_P12_PASSWORD and RUNNER_TEMP.
set -euo pipefail

keychain_path="$RUNNER_TEMP/slovo-signing.keychain-db"
keychain_password="$(openssl rand -base64 24)"
cert_path="$RUNNER_TEMP/developer_id_app.p12"
trap 'rm -f "$cert_path"' EXIT
printf '%s' "$DEVELOPER_ID_APP_P12_BASE64" | base64 --decode > "$cert_path"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$cert_path" -P "$DEVELOPER_ID_APP_P12_PASSWORD" \
  -A -t cert -f pkcs12 -k "$keychain_path"
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$keychain_password" "$keychain_path" >/dev/null
# The ephemeral keychain is the only one on the user search list for the
# rest of the job, so codesign resolves the Developer ID identity from it.
security list-keychains -d user -s "$keychain_path"
