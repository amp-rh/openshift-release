#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset faNamespace="${FA__NAMESPACE:-ibm-fusion-access}"
typeset faStorageScaleVersion="${FA__STORAGE_SCALE_VERSION:-v5.2.3.5}"

typeset exists=''
exists="$(oc get fusionaccess fusionaccess-object -n "${faNamespace}" --ignore-not-found -o jsonpath='{.metadata.name}')"
if [[ -z "${exists}" ]]; then
  {
    oc create -f - --dry-run=client -o json --save-config |
    jq -c \
      --arg ns "${faNamespace}" \
      --arg ver "${faStorageScaleVersion}" \
      '.metadata.namespace = $ns | .spec.storageScaleVersion = $ver'
  true
  } 0<<'YAML' | oc apply -f -
apiVersion: fusion.storage.openshift.io/v1alpha1
kind: FusionAccess
metadata:
  name: fusionaccess-object
spec:
  storageDeviceDiscovery:
    create: true
YAML
  if ! oc wait --for=create fusionaccess/fusionaccess-object -n "${faNamespace}" --timeout=600s; then
    oc get fusionaccess fusionaccess-object -n "${faNamespace}" -o yaml --ignore-not-found
    exit 1
  fi
fi

true
