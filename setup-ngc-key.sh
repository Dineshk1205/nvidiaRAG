# Generate your NGC API key first (one-time, manual, done in a browser -- not part of this script):
#   1. Join the NVIDIA Developer Program (free) at https://developer.nvidia.com
#   2. Go to https://org.ngc.nvidia.com/setup/api-keys
#   3. Create a key with "NGC Catalog" and "Public API Endpoints" scopes selected
#   4. Copy the key somewhere safe -- NGC will not show it again
#
# This script exports that key into your current shell session (never written to disk, never
# printed back). It's needed from Step 5 (NIM Operator secrets) onward, so run it once per SSH
# session before continuing.
#
# IMPORTANT: this must be SOURCED, not executed, so the export reaches your shell:
#   source setup-ngc-key.sh
#   (or:  . setup-ngc-key.sh)

read -rs -p "Paste your NGC API key: " NGC_API_KEY
export NGC_API_KEY
echo
echo "NGC_API_KEY exported for this shell session."
