#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

oc create namespace "${FA__NAMESPACE}" --dry-run=client -o yaml --save-config | oc apply -f -
oc wait --for create namespace/"${FA__NAMESPACE}" --timeout=60s

jq -cn \
  --arg ns "${FA__NAMESPACE}" \
  '{
    apiVersion: "operators.coreos.com/v1",
    kind: "OperatorGroup",
    metadata: {name: "storage-scale-operator-group", namespace: $ns},
    spec: {upgradeStrategy: "Default"}
  }' | oc apply -f -

jq -cn \
  --arg image "${FA__CATALOG_SOURCE_IMAGE}" \
  '{
    apiVersion: "operators.coreos.com/v1alpha1",
    kind: "CatalogSource",
    metadata: {name: "test-fusion-access-operator", namespace: "openshift-marketplace"},
    spec: {displayName: "Test Storage Scale Operator", sourceType: "grpc", image: $image}
  }' | oc apply -f -

jq -cn \
  --arg ns "${FA__NAMESPACE}" \
  --arg channel "${FA__OPERATOR_CHANNEL}" \
  '{
    apiVersion: "operators.coreos.com/v1alpha1",
    kind: "Subscription",
    metadata: {name: "openshift-fusion-access-operator", namespace: $ns},
    spec: {
      channel: $channel,
      installPlanApproval: "Automatic",
      name: "openshift-fusion-access-operator",
      source: "test-fusion-access-operator",
      sourceNamespace: "openshift-marketplace"
    }
  }' | oc apply -f -

oc wait --for=jsonpath='{.status.state}'=AtLatestKnown subscription/openshift-fusion-access-operator -n "${FA__NAMESPACE}" --timeout=600s

typeset csvName=''
csvName=$(oc get subscription openshift-fusion-access-operator -n "${FA__NAMESPACE}" -o json | jq -r '.status.installedCSV')
[[ "${csvName}" == "null" ]] && false
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv/"${csvName}" -n "${FA__NAMESPACE}" --timeout=600s

true
