#!/usr/bin/env bash
# Home Theater System - Initial Setup Script
# This script generates API keys and updates sops secrets
#
# Usage: ./scripts/media-init.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_ROOT/secrets/common.yaml"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "========================================="
echo "Home Theater System - Initial Setup"
echo "========================================="
echo ""

# Check dependencies
for cmd in sops jq yq terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not installed."
    exit 1
  fi
done

echo "Checking current secrets configuration..."

# Check if password exists in sops
if sops -d "$SECRETS_FILE" 2>/dev/null | yq -e '.password' &>/dev/null; then
  echo "✓ Main password already configured"
else
  echo "! Main password not found in secrets"
  echo "  Please add 'password' key to secrets/common.yaml"
  echo ""
  echo "  Example:"
  echo "    sops secrets/common.yaml"
  echo "    # Add: password: your-secure-password"
fi

# Check smtp password
if sops -d "$SECRETS_FILE" 2>/dev/null | yq -e '.smtp.password' &>/dev/null; then
  echo "✓ SMTP password already configured"
else
  echo "! SMTP password not found"
  echo "  Please add 'smtp.password' key to secrets/common.yaml"
fi

# Check media API keys
echo ""
echo "Checking media API keys..."

for key in "media.sonarr_api_key" "media.radarr_api_key" "media.prowlarr_api_key"; do
  if sops -d "$SECRETS_FILE" 2>/dev/null | yq -e ".$key" &>/dev/null; then
    echo "✓ $key configured"
  else
    echo "! $key not found - will be generated on first run"
  fi
done

echo ""
echo "========================================="
echo "Terraform Configuration"
echo "========================================="
echo ""

cd "$TERRAFORM_DIR"

# Initialize terraform if needed
if [ ! -d ".terraform" ]; then
  echo "Initializing Terraform..."
  terraform init
fi

# Show plan for media resources
echo ""
echo "Terraform media resources status:"
terraform state list 2>/dev/null | grep -E "(sonarr|radarr|prowlarr)" | head -20 || echo "  (no media resources found - run terraform apply)"

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Ensure secrets are configured in secrets/common.yaml:"
echo "   - password: <your-main-password>"
echo "   - smtp.password: <smtp-password-for-noreply@dora.im>"
echo "   - media.sonarr_api_key: <32-char-hex-key>"
echo "   - media.radarr_api_key: <32-char-hex-key>"
echo "   - media.prowlarr_api_key: <32-char-hex-key>"
echo ""
echo "2. Deploy NixOS configuration to media server:"
echo "   colmena apply --on nue0"
echo ""
echo "3. Apply Terraform configuration:"
echo "   cd terraform && terraform apply"
echo ""
echo "4. Access services at:"
echo "   - https://jellyfin.dora.im"
echo "   - https://seerr.dora.im"
echo "   - https://sonarr.dora.im"
echo "   - https://radarr.dora.im"
echo "   - https://prowlarr.dora.im"
echo "   - https://bazarr.dora.im"
echo "   - https://qbit.dora.im"
echo ""
echo "   Username: i"
echo "   Password: (from sops secret 'password')"
echo ""
echo "========================================="
