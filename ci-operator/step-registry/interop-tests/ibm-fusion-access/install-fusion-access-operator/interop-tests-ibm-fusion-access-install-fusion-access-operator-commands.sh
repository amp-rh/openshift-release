#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset faNamespace="${FA__NAMESPACE:-ibm-fusion-access}"
typeset faCatalogSourceImage="${FA__CATALOG_SOURCE_IMAGE:-quay.io/openshift-storage-scale/openshift-fusion-access-catalog:stable}"
typeset faOperatorChannel="${FA__OPERATOR_CHANNEL:-alpha}"

oc create namespace "${faNamespace}" --dry-run=client -o json --save-config | oc apply -f -
if ! oc wait --for=create "namespace/${faNamespace}" --timeout=60s; then
  oc get namespace "${faNamespace}" -o yaml --ignore-not-found
  exit 1
fi

{
  oc create -f - --dry-run=client -o yaml --save-config
} 0<<YAML | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: storage-scale-operator-group
  namespace: ${faNamespace}
spec:
  upgradeStrategy: Default
YAML

{
  oc create -f - --dry-run=client -o yaml --save-config
} 0<<YAML | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: test-fusion-access-operator
  namespace: openshift-marketplace
spec:
  displayName: Test Storage Scale Operator
  image: ${faCatalogSourceImage}
  sourceType: grpc
YAML

{
  oc create -f - --dry-run=client -o yaml --save-config
} 0<<YAML | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-fusion-access-operator
  namespace: ${faNamespace}
spec:
  channel: ${faOperatorChannel}
  installPlanApproval: Automatic
  name: openshift-fusion-access-operator
  source: test-fusion-access-operator
  sourceNamespace: openshift-marketplace
YAML

if ! oc wait --for=jsonpath='{.status.state}'=AtLatestKnown subscription/openshift-fusion-access-operator -n "${faNamespace}" --timeout=600s; then
  oc get subscription openshift-fusion-access-operator -n "${faNamespace}" -o yaml --ignore-not-found
  exit 1
fi

typeset csvName=''
csvName="$(oc get subscription openshift-fusion-access-operator -n "${faNamespace}" -o jsonpath='{.status.installedCSV}')"
if [[ -z "${csvName}" ]]; then
  : "installedCSV is empty"
  exit 1
fi
if ! oc wait --for=jsonpath='{.status.phase}'=Succeeded "csv/${csvName}" -n "${faNamespace}" --timeout=600s; then
  oc get csv "${csvName}" -n "${faNamespace}" -o yaml --ignore-not-found
  exit 1
fi

true
