#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset FA__SCALE__NAMESPACE="${FA__SCALE__NAMESPACE:-ibm-spectrum-scale}"
typeset FA__LOCALDISK_NAME="${FA__LOCALDISK_NAME:-shared-san-disk}"

typeset firstWorker=''
firstWorker=$(oc get nodes -l node-role.kubernetes.io/worker= -o jsonpath-as-json='{.items[*].metadata.name}' | jq -r 'first(.[]) // empty')

if [[ -z "${firstWorker}" ]]; then
  oc get nodes
  exit 1
fi

typeset byIdPath=''
if [[ -f "${SHARED_DIR}/ebs-device-path" ]]; then
  byIdPath=$(cat "${SHARED_DIR}/ebs-device-path")
elif [[ -f "${SHARED_DIR}/multiattach-volume-id" ]]; then
  typeset volumeIdClean=''
  volumeIdClean=$(cat "${SHARED_DIR}/multiattach-volume-id" | tr -d '-')
  byIdPath="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${volumeIdClean}"
else
  ls -la "${SHARED_DIR}/"
  exit 1
fi

typeset devicePath=''
if devicePath="$(oc debug -n default node/"${firstWorker}" --quiet -- \
  chroot /host readlink -f "${byIdPath}" 2>&1 \
  | sed -e '/Starting/d' -e '/Removing/d' -e '/To use/d')"; then
  :
fi
if [[ -z "${devicePath}" || "${devicePath}" != /dev/* ]]; then
  oc debug -n default node/"${firstWorker}" --quiet -- \
    chroot /host ls -la "${byIdPath}" || :
  exit 1
fi

{
  oc create -f - --dry-run=client -o json --save-config |
  jq -c \
    --arg name "${FA__LOCALDISK_NAME}" \
    --arg ns "${FA__SCALE__NAMESPACE}" \
    --arg device "${devicePath}" \
    --arg node "${firstWorker}" \
    '
      .metadata.name = $name |
      .metadata.namespace = $ns |
      .spec.device = $device |
      .spec.node = $node
    '
} 0<<'YAML' | oc apply -f -
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: LocalDisk
metadata: {}
spec:
  nodeConnectionSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/worker
      operator: Exists
  existingDataSkipVerify: true
YAML

if ! oc wait --for=condition=Ready \
    localdisk/"${FA__LOCALDISK_NAME}" -n "${FA__SCALE__NAMESPACE}" --timeout=300s; then
  oc debug -n default node/"${firstWorker}" --quiet -- chroot /host ls -la "${devicePath}" || :
  oc debug -n default node/"${firstWorker}" --quiet -- chroot /host ls -la /dev/disk/by-id/ | sed -n '/[nN][vV][mM][eE]/p'
  oc get localdisk "${FA__LOCALDISK_NAME}" -n "${FA__SCALE__NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

true
