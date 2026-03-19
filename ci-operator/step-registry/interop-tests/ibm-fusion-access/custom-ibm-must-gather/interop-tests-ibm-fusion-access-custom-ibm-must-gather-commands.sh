#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset FA__MUST_GATHER_IMAGE="${FA__MUST_GATHER_IMAGE:-pipeline:ibm-must-gather}"

mkdir -p /tmp/ibm-must-gather

oc adm must-gather --image="${FA__MUST_GATHER_IMAGE}" --dest-dir="/tmp/ibm-must-gather"

tar -czf "${ARTIFACT_DIR}/ibm-must-gather.tar.gz" -C /tmp ibm-must-gather

true
