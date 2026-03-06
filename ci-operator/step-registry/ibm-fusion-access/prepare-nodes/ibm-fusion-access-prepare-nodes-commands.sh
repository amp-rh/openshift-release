#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

oc label nodes -l node-role.kubernetes.io/worker= scale.spectrum.ibm.com/role=storage --overwrite

typeset -i labeledCount=0
labeledCount=$(oc get nodes -l scale.spectrum.ibm.com/role=storage -o json | jq '.items | length')
((labeledCount)) || false

for node in $(oc get nodes -l node-role.kubernetes.io/worker= -o json | jq -r '.items[].metadata.name'); do
  for dir in /var/lib/firmware /var/mmfs/etc /var/mmfs/tmp/traces /var/mmfs/pmcollector; do
    oc debug -n default "node/${node}" -- chroot /host mkdir -p "${dir}"
  done
  oc debug -n default "node/${node}" -- chroot /host bash -c 'touch /var/lib/firmware/lxtrace-dummy && chmod 644 /var/lib/firmware/lxtrace-dummy'
done

true
