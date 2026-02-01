#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$1"
CATEGORIES_FILE="$2"
PASSWORD_FILE="$3"
PYTHON="${4:-python3}"

# Wait for qBittorrent to start and create initial config
for _ in {1..30}; do
  if [ -f "$CONFIG_FILE" ]; then
    break
  fi
  sleep 2
done

if [ ! -f "$CONFIG_FILE" ]; then
  echo "qBittorrent config file not found, waiting for service to initialize..."
  exit 0
fi

# Check if already configured
if grep -q 'WebUI\Username=i' "$CONFIG_FILE" 2>/dev/null; then
  echo "qBittorrent already configured, skipping..."
  exit 0
fi

echo "Configuring qBittorrent..."

# Stop qBittorrent to modify config
systemctl stop qbittorrent.service || true
sleep 2

# Read password from sops and export for Python
if [ -f "$PASSWORD_FILE" ]; then
  PASSWORD=$(cat "$PASSWORD_FILE")
  export PASSWORD
else
  echo "Password file not found, using default"
  PASSWORD="changeme"
  export PASSWORD
fi

# Generate PBKDF2 password hash for qBittorrent 4.2+
HASH=$(
  $PYTHON <<'PYTHON_EOF'
import hashlib
import base64
import secrets
import os
password = os.environ.get('PASSWORD', 'changeme')
salt = secrets.token_bytes(16)
iterations = 100000
dk = hashlib.pbkdf2_hmac('sha512', password.encode(), salt, iterations, dklen=64)
result = base64.b64encode(salt + dk).decode()
print(f'@ByteArray({result})')
PYTHON_EOF
)

# Update configuration
cat >>"$CONFIG_FILE" <<EOF

[BitTorrent]
Session\DefaultSavePath=/srv/torrents/completed
Session\TempPath=/srv/torrents/downloading
Session\TempPathEnabled=true
Session\Port=6881
Session\MaxConnections=500
Session\MaxUploads=20

[Preferences]
WebUI\Username=i
WebUI\Password_PBKDF2=$HASH
WebUI\LocalHostAuth=false
WebUI\AuthSubnetWhitelist=127.0.0.1/32, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
WebUI\AuthSubnetWhitelistEnabled=true
Downloads\SavePath=/srv/torrents/completed
Downloads\TempPath=/srv/torrents/downloading
Downloads\TempPathEnabled=true
EOF

# Create categories file
mkdir -p "$(dirname "$CATEGORIES_FILE")"
echo "$5" >"$CATEGORIES_FILE"

echo "qBittorrent configuration complete!"

# Restart qBittorrent
systemctl start qbittorrent.service
