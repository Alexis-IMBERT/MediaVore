#!/usr/bin/env bash
# Generate the Android upload keystore and the GitHub Actions secrets for release signing.
# See DOCS/android-release-signing.md.
#
# Usage: tool/generate_android_upload_key.sh [--out DIR] [--alias NAME] [--write-key-properties]
#
# Outputs (in DIR, default ~/.mediavore-signing, mode 600):
#   upload-keystore.jks    the upload key: back it up, losing it blocks future updates
#   github-secrets.yaml    the 4 secrets to add to the repository (Settings > Secrets > Actions)
# With --write-key-properties, also writes android/key.properties for local release builds.
set -euo pipefail

out_dir="$HOME/.mediavore-signing"
alias_name="upload"
write_key_properties=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out_dir="$2"; shift 2 ;;
    --alias) alias_name="$2"; shift 2 ;;
    --write-key-properties) write_key_properties=true; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# keytool: PATH, then $JAVA_HOME, then the JDK bundled with Android Studio (macOS).
keytool_bin="$(command -v keytool || true)"
for candidate in \
  "${JAVA_HOME:-}/bin/keytool" \
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"; do
  [[ -z "$keytool_bin" && -x "$candidate" ]] && keytool_bin="$candidate"
done
if [[ -z "$keytool_bin" ]]; then
  echo "keytool not found: install a JDK (17+) or Android Studio, or set JAVA_HOME." >&2
  exit 1
fi
command -v openssl >/dev/null || { echo "openssl not found." >&2; exit 1; }

keystore="$out_dir/upload-keystore.jks"
secrets="$out_dir/github-secrets.yaml"
if [[ -e "$keystore" ]]; then
  echo "Refusing to overwrite $keystore (an existing upload key must be kept)." >&2
  exit 1
fi

umask 077
mkdir -p "$out_dir"

# PKCS12 (keytool's default format) uses a single password for the store and the key.
password="$(openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-40)"

"$keytool_bin" -genkeypair -v \
  -keystore "$keystore" -storetype PKCS12 \
  -alias "$alias_name" -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$password" -keypass "$password" \
  -dname "CN=MediaVore, O=Zimberts, C=FR" >/dev/null

keystore_base64="$(openssl base64 -A -in "$keystore")"

cat > "$secrets" <<EOF
# GitHub Actions secrets for Zimberts/MediaVore (Settings > Secrets and variables > Actions).
# Names match DOCS/android-release-signing.md. Delete this file once the secrets are added.
# With the GitHub CLI (requires admin rights on the repository):
#   gh secret set ANDROID_KEYSTORE_BASE64 -R Zimberts/MediaVore < <(openssl base64 -A -in "$keystore")
#   gh secret set ANDROID_KEYSTORE_PASSWORD -R Zimberts/MediaVore --body '<value below>'
ANDROID_KEYSTORE_BASE64: "$keystore_base64"
ANDROID_KEYSTORE_PASSWORD: "$password"
ANDROID_KEY_ALIAS: "$alias_name"
ANDROID_KEY_PASSWORD: "$password"
EOF

if $write_key_properties; then
  repo_root="$(cd "$(dirname "$0")/.." && pwd)"
  cat > "$repo_root/android/key.properties" <<EOF
storeFile=$keystore
storePassword=$password
keyAlias=$alias_name
keyPassword=$password
EOF
  echo "Wrote $repo_root/android/key.properties (gitignored)."
fi

echo "Keystore:  $keystore"
echo "Secrets:   $secrets"
echo "SHA-256 certificate fingerprint:"
"$keytool_bin" -list -v -keystore "$keystore" -storepass "$password" -alias "$alias_name" \
  | awk '/^[[:space:]]*SHA256:/ { sub(/^[[:space:]]*/, "  "); print }'
echo "Back up $keystore and its password (password manager): they cannot be recovered."
