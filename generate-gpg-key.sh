#!/usr/bin/env bash
# =============================================================================
# Lilith Linux — GPG Key Generation Script
# =============================================================================
# Generates a passwordless GPG key for signing the package repository.
# Exports keys in binary (.gpg) and armored (.asc) formats.
# =============================================================================
set -euo pipefail

KEY_EMAIL="blancobam@protonmail.com"
KEY_NAME="BlancoBAM"
LIL_BUILD="/home/aegon/lil-build"
REPO_ROOT="${LIL_BUILD}/Lilith-Repo"

echo "[*] Generating GPG key configuration..."
CONF_FILE=$(mktemp)
cat > "$CONF_FILE" << EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${KEY_NAME}
Name-Email: ${KEY_EMAIL}
Expire-Date: 0
%no-ask-passphrase
%no-protection
%commit
EOF

echo "[*] Running gpg --batch --generate-key..."
gpg --batch --generate-key "$CONF_FILE"
rm -f "$CONF_FILE"

echo "[*] Key generated successfully. Verifying:"
gpg --list-keys "$KEY_EMAIL"

echo "[*] Exporting public key..."
# Binary format for APT keyring (Signed-By)
gpg --batch --yes --output "${LIL_BUILD}/lilith-archive-keyring.gpg" --export "$KEY_EMAIL"
cp "${LIL_BUILD}/lilith-archive-keyring.gpg" "${REPO_ROOT}/lilith-archive-keyring.gpg"

# Armored ASCII format for web downloads
gpg --batch --yes --armor --output "${LIL_BUILD}/lilith-archive-keyring.asc" --export "$KEY_EMAIL"
cp "${LIL_BUILD}/lilith-archive-keyring.asc" "${REPO_ROOT}/lilith-archive-keyring.asc"

echo "[✔] Public keys exported:"
echo "    - ${LIL_BUILD}/lilith-archive-keyring.gpg"
echo "    - ${REPO_ROOT}/lilith-archive-keyring.gpg"
echo "    - ${LIL_BUILD}/lilith-archive-keyring.asc"
echo "    - ${REPO_ROOT}/lilith-archive-keyring.asc"
