#!/usr/bin/env bash
# Upgrade Nexus Repository Manager 3 HA to the latest version using Helm chart.
set -euo pipefail

_current_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
VALUES_YAML="${VALUES_YAML:-"${_current_dir%/}/helm-nxrm3ha-values.yml"}"
SECRET_KEYFILE="${SECRET_KEYFILE:-"${_current_dir%/}/nexus-secrets.json"}"


# Defaults (override by exporting before running)
HELM_REPO="${HELM_REPO:-sonatype-helm}"
NAME_SPACE="${NAME_SPACE:-nexusrepo}"
RELEASE_NAME="${RELEASE_NAME:-nxrm3ha}"
ADMIN_PWD="${ADMIN_PWD:-admin123}"
DB_SERVER="${DB_SERVER:-192.168.4.31}"
NFS_SERVER="${NFS_SERVER:-192.168.4.31}"
SHARE_DIR="${SHARE_DIR:-/var/tmp/share/sonatype/${RELEASE_NAME}-nfs}"

# License base64 (override with LICENSE_B64 if already set)
LICENSE_FILE="${LICENSE_FILE:-$HOME/share/sonatype/sonatype-license.lic}"
if [[ -z "${LICENSE_B64:-}" ]]; then
  LICENSE_B64="$(base64 < "${LICENSE_FILE}" | tr -d '\n')"
fi

#helm repo add ${HELM_REPO} https://sonatype.github.io/helm3-charts/
helm repo update ${HELM_REPO}
helm search repo ${HELM_REPO}/nxrm-ha --versions | head
sleep 3

# currently somehow almost always fail if not uninstalled
helm uninstall ${RELEASE_NAME} -n ${NAME_SPACE}
sleep 10
eval "echo \"$(cat ${VALUES_YAML} | grep -v '^\s*#')\"" > /tmp/${RELEASE_NAME}_values.yaml
helm upgrade -i ${RELEASE_NAME} ${HELM_REPO}/nxrm-ha -f /tmp/${RELEASE_NAME}_values.yaml -n ${NAME_SPACE} \
    --set-file secret.nexusSecret.secretKeyfile=${SECRET_KEYFILE} \
    ${DRY_RUN:+--dry-run --debug}

