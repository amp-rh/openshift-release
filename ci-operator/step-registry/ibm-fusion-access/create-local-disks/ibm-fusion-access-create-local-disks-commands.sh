#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset firstWorker=''
firstWorker="$(
    oc get nodes -l node-role.kubernetes.io/worker= -o json |
    jq -r 'first(.items[].metadata.name) // empty'
)"
[[ -z "${firstWorker}" ]] && false

typeset -a devices=("nvme2n1" "nvme3n1")
typeset diskCount=0

for device in "${devices[@]}"; do
  typeset localdiskName="shared-ebs-disk-${diskCount}"
  
  jq -cn \
    --arg name "${localdiskName}" \
    --arg ns "${FA__SCALE__NAMESPACE}" \
    --arg dev "/dev/${device}" \
    --arg node "${firstWorker}" \
    '{
      apiVersion: "scale.spectrum.ibm.com/v1beta1",
      kind: "LocalDisk",
      metadata: {name: $name, namespace: $ns},
      spec: {
        device: $dev,
        node: $node,
        nodeConnectionSelector: {matchExpressions: [{key: "node-role.kubernetes.io/worker", operator: "Exists"}]},
        existingDataSkipVerify: true
      }
    }' | oc apply -f -
  
  ((++diskCount))
done

true
