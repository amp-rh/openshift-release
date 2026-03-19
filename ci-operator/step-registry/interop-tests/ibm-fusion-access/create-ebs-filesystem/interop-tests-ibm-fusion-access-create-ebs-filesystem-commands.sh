#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset FA__SCALE__NAMESPACE="${FA__SCALE__NAMESPACE:-ibm-spectrum-scale}"
typeset FA__SCALE__CSI_NAMESPACE="${FA__SCALE__CSI_NAMESPACE:-ibm-spectrum-scale-csi}"
typeset -i FA__FILESYSTEM_TIMEOUT="${FA__FILESYSTEM_TIMEOUT:-3600}"
typeset FA__LOCALDISK_NAME="${FA__LOCALDISK_NAME:-shared-san-disk}"

if ! oc get localdisk "${FA__LOCALDISK_NAME}" -n "${FA__SCALE__NAMESPACE}"; then
  oc get localdisk -n "${FA__SCALE__NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

{
  oc create -f - --dry-run=client -o json --save-config 0<<'YAML' |
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: Filesystem
metadata:
  name: shared-filesystem
  namespace: PLACEHOLDER_NS
spec:
  local:
    blockSize: 4M
    pools:
    - name: system
      disks:
      - PLACEHOLDER_DISK
    replication: 1-way
    type: shared
  seLinuxOptions:
    level: s0
    role: object_r
    type: container_file_t
    user: system_u
YAML
  jq -c \
    --arg ns "${FA__SCALE__NAMESPACE}" \
    --arg disk "${FA__LOCALDISK_NAME}" \
    '.metadata.namespace = $ns | .spec.local.pools[0].disks[0] = $disk'
} | oc apply -f -

if ! oc wait --for=condition=Success \
    filesystem/shared-filesystem -n "${FA__SCALE__NAMESPACE}" --timeout="${FA__FILESYSTEM_TIMEOUT}s"; then
  oc get filesystem shared-filesystem -n "${FA__SCALE__NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

if ! oc wait --for=condition=Healthy \
    filesystem/shared-filesystem -n "${FA__SCALE__NAMESPACE}" --timeout=600s; then
  oc get filesystem shared-filesystem -n "${FA__SCALE__NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

if ! oc wait --for=condition=Ready pod -l app=ibm-spectrum-scale-csi \
    -n "${FA__SCALE__CSI_NAMESPACE}" --timeout=300s; then
  oc get pods -l app=ibm-spectrum-scale-csi -n "${FA__SCALE__CSI_NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

true
