#!/usr/bin/env bash
set -euo pipefail
# --- config ---
NEXUS_HOST="${NEXUS_HOST:-"http://localhost:8081"}"
REPO="${REPO:-"docker-hosted"}"
IMAGE="${IMAGE:-"bc"}"
USER="${NEXUS_USER:-"admin"}"
PASS="${NEXUS_PASS:-"admin123"}"
BASE="${NEXUS_HOST%/}/repository/${REPO}"

# NOTE: Pick an existing blob digest to avoid "blob unknown to registry" (not an existing application/vnd.docker.container.image.v1+json digest)
SAMPLE_SHA256="55afa1ecc21d2bb5e5045f32dafee56272ffd89860bac26f6c32123439af26a4"
#SAMPLE_SHA256="$(openssl rand -hex 32)" # This doesn't work and causes "blob unknown to registry"

# --- 1. get a token, mirroring cosign's GET /v2/token ---
echo "== requesting token ==" >&2
TOKEN=$(curl -s -u "${USER}:${PASS}" \
  "${BASE}/v2/token?scope=repository:${REPO}/${IMAGE}:push,pull&service=${NEXUS_HOST}/repository/${REPO}/v2/token" \
  | jq -r '.token // .access_token')
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# --- 2. initiate a blob upload (like cosign does before pushing the manifest) ---
echo "== POST blob upload ==" >&2
UPLOAD_LOC=$(curl -s -D - -o /dev/null -X POST \
  -H "${AUTH_HEADER}" \
  "${BASE}/v2/${IMAGE}/blobs/uploads/" \
  | grep -i '^Location:' | sed 's/Location: //I' | tr -d '\r')
  echo "upload location: ${UPLOAD_LOC}" >&2

# --- 3. build a minimal manifest body and compute its real digest ---

MANIFEST_FILE=$(mktemp)
cat > "${MANIFEST_FILE}" << EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:${SAMPLE_SHA256}",
    "size": 611
  },
  "layers": []
}
EOF

DIGEST_HEX=$(shasum -a 256 "${MANIFEST_FILE}" | awk '{print $1}')
NEW_TAG="sha256-${DIGEST_HEX}"
echo "New tag:   ${NEW_TAG}" >&2

# --- 4a. PUT using the dash form, exactly like the cosign log line ---
echo "== PUT manifest via dash tag (mirrors captured request) ==" >&2
if curl -s -v -X PUT \
  -H "${AUTH_HEADER}" \
  -H "Content-Type: application/json" \
  --data-binary "@${MANIFEST_FILE}" \
  "${BASE}/v2/${IMAGE}/manifests/${NEW_TAG}"; then
  echo ""
  echo "PUT manifest via dash tag succeeded" >&2
  rm -v -f "${MANIFEST_FILE}"
  #cat "${MANIFEST_FILE}"
else
  echo ""
  echo "PUT manifest via dash tag failed" >&2
fi