#!/usr/bin/env bash
# Upgrade IQ HA to the latest version using Helm chart.
set -euo pipefail

_current_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# Defaults (override by exporting before running)
HELM_REPO="${HELM_REPO:-sonatype-helm}"
NAME_SPACE="${NAME_SPACE:-sonatype-ha}"
RELEASE_NAME="${RELEASE_NAME:-nxiqha}"
VALUES_YAML="${VALUES_YAML:-"${_current_dir%/}/helm-nxiqha-values.yml"}"

helm repo update ${HELM_REPO} && helm search repo ${HELM_REPO}/nexus-iq-server-ha --versions | head

kubectl scale -n ${NAME_SPACE} deployment/${RELEASE_NAME}-iq-server-deployment --replicas=0
kubectl wait -n ${NAME_SPACE} --for=delete pod -l name=${RELEASE_NAME}-iq-server --timeout=120s

sleep 3

helm upgrade -i ${RELEASE_NAME} ${HELM_REPO}/nexus-iq-server-ha -f ${VALUES_YAML} -n ${NAME_SPACE} ${DRY_RUN:+--dry-run --debug}