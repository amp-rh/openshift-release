#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

jq -cn \
  --arg ns "${FA__NAMESPACE}" \
  --arg ver "${FA__STORAGE_SCALE_VERSION}" \
  '{
    apiVersion: "fusion.storage.openshift.io/v1alpha1",
    kind: "FusionAccess",
    metadata: {name: "fusionaccess-object", namespace: $ns},
    spec: {storageScaleVersion: $ver, storageDeviceDiscovery: {create: true}}
  }' | oc apply -f -

true
