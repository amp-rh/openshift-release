#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

oc create namespace "${FA__NAMESPACE}" --dry-run=client -o json --save-config | oc apply -f -
if ! oc wait --for=create namespace/"${FA__NAMESPACE}" --timeout=60s; then
  oc get namespace "${FA__NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

{
  oc create -f - --dry-run=client -o yaml --save-config
} 0<<YAML | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: storage-scale-operator-group
  namespace: ${FA__NAMESPACE}
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
  image: ${FA__CATALOG_SOURCE_IMAGE}
  sourceType: grpc
YAML

{
  oc create -f - --dry-run=client -o yaml --save-config
} 0<<YAML | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-fusion-access-operator
  namespace: ${FA__NAMESPACE}
spec:
  channel: ${FA__OPERATOR_CHANNEL}
  installPlanApproval: Automatic
  name: openshift-fusion-access-operator
  source: test-fusion-access-operator
  sourceNamespace: openshift-marketplace
YAML

if ! oc wait --for=jsonpath='{.status.state}'=AtLatestKnown subscription/openshift-fusion-access-operator -n "${FA__NAMESPACE}" --timeout=600s; then
  oc get subscription openshift-fusion-access-operator -n "${FA__NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

typeset csvName=''
csvName="$(oc get subscription openshift-fusion-access-operator -n "${FA__NAMESPACE}" -o jsonpath='{.status.installedCSV}')"
[[ -n "${csvName}" ]]
if ! oc wait --for=jsonpath='{.status.phase}'=Succeeded csv/"${csvName}" -n "${FA__NAMESPACE}" --timeout=600s; then
  oc get csv "${csvName}" -n "${FA__NAMESPACE}" -o yaml --ignore-not-found
  exit 1
fi

{
  oc create -f - --dry-run=client -o yaml --save-config
} 0<<YAML | oc apply -f -
apiVersion: fusion.storage.openshift.io/v1alpha1
kind: FusionAccess
metadata:
  name: fusionaccess-object
  namespace: ${FA__NAMESPACE}
spec:
  storageDeviceDiscovery:
    create: true
  storageScaleVersion: ${FA__STORAGE_SCALE_VERSION}
YAML

true
