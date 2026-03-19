#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset FA__NAMESPACE="${FA__NAMESPACE:-ibm-fusion-access}"
typeset FA__IBM_REGISTRY="${FA__IBM_REGISTRY:-cp.icr.io}"
typeset FA__SCALE__NAMESPACE="${FA__SCALE__NAMESPACE:-ibm-spectrum-scale}"
typeset FA__SCALE__DNS_NAMESPACE="${FA__SCALE__DNS_NAMESPACE:-ibm-spectrum-scale-dns}"
typeset FA__SCALE__CSI_NAMESPACE="${FA__SCALE__CSI_NAMESPACE:-ibm-spectrum-scale-csi}"
typeset FA__SCALE__OPERATOR_NAMESPACE="${FA__SCALE__OPERATOR_NAMESPACE:-ibm-spectrum-scale-operator}"

typeset ibmEntitlementKeyPath="/var/run/secrets/ibm-entitlement-key"
typeset fusionPullSecretExtraPath="/var/run/secrets/fusion-pullsecret-extra"

function CreateRegistryAuth () {
  typeset ns="${1}"; (($#)) && shift
  typeset name="${1}"; (($#)) && shift
  typeset regHost="${1}"; (($#)) && shift
  typeset regUsr="${1}"; (($#)) && shift
  typeset regPwdFile="${1}"; (($#)) && shift

  oc -n "${ns}" create secret generic "${name}" \
    --from-file=.dockerconfigjson=<(
      set +x
      jq -cnr \
        --arg host "${regHost}" \
        --arg usr "${regUsr}" \
        --rawfile pwd "${regPwdFile}" \
        '{auths: {($host): {auth: ("\($usr):\($pwd | rtrimstr("\n"))" | @base64), email: ""}}}'
      true
    ) \
    --type=kubernetes.io/dockerconfigjson \
    --dry-run=client -o json --save-config | oc apply -f -

  true
}

function CreateRegistryAuthFromFile () {
  typeset ns="${1}"; (($#)) && shift
  typeset name="${1}"; (($#)) && shift
  typeset regHost="${1}"; (($#)) && shift
  typeset b64AuthFile="${1}"; (($#)) && shift

  oc -n "${ns}" create secret generic "${name}" \
    --from-file=.dockerconfigjson=<(
      set +x
      jq -cnr \
        --arg host "${regHost}" \
        --rawfile auth "${b64AuthFile}" \
        '{auths: {($host): {auth: ($auth | rtrimstr("\n")), email: ""}}}'
      true
    ) \
    --type=kubernetes.io/dockerconfigjson \
    --dry-run=client -o json --save-config | oc apply -f -

  true
}

function CreateEntitlementSecretInNamespace () {
  typeset targetNamespace="${1}"; (($#)) && shift

  oc get namespace "${targetNamespace}" || return 0
  if oc get secret ibm-entitlement-key -n "${targetNamespace}"; then
    return 0
  fi

  CreateRegistryAuth "${targetNamespace}" ibm-entitlement-key "${FA__IBM_REGISTRY}" cp "${ibmEntitlementKeyPath}"
  if ! oc wait --for=create secret/ibm-entitlement-key -n "${targetNamespace}" --timeout=60s; then
    oc get secret ibm-entitlement-key -n "${targetNamespace}" -o yaml --ignore-not-found
    exit 1
  fi

  true
}

oc get namespace "${FA__NAMESPACE}" || exit 1
[[ -f "${ibmEntitlementKeyPath}" ]] || exit 1

if oc get secret fusion-pullsecret -n "${FA__NAMESPACE}"; then
  typeset currentSaSecrets=''
  if ! currentSaSecrets="$(oc get serviceaccount default -n "${FA__NAMESPACE}" -o jsonpath='{.imagePullSecrets[*].name}')"; then
    currentSaSecrets=""
  fi
  if [[ "${currentSaSecrets}" != *"fusion-pullsecret"* ]]; then
    oc patch serviceaccount default -n "${FA__NAMESPACE}" -p '{"imagePullSecrets":[{"name":"fusion-pullsecret"}]}'
  fi
else
  oc -n "${FA__NAMESPACE}" create secret generic fusion-pullsecret \
    --from-file=ibm-entitlement-key="${ibmEntitlementKeyPath}" \
    --dry-run=client -o json --save-config | oc apply -f -

  if ! oc wait --for=create secret/fusion-pullsecret -n "${FA__NAMESPACE}" --timeout=60s; then
    oc get secret fusion-pullsecret -n "${FA__NAMESPACE}" -o yaml --ignore-not-found
    exit 1
  fi

  CreateRegistryAuth "${FA__NAMESPACE}" ibm-entitlement-key "${FA__IBM_REGISTRY}" cp "${ibmEntitlementKeyPath}"

  if ! oc wait --for=create secret/ibm-entitlement-key -n "${FA__NAMESPACE}" --timeout=60s; then
    oc get secret ibm-entitlement-key -n "${FA__NAMESPACE}" -o yaml --ignore-not-found
    exit 1
  fi

  set +x
  if [[ -f "${fusionPullSecretExtraPath}" ]]; then
    oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | \
      jq -c \
        --arg host "${FA__IBM_REGISTRY}" \
        --rawfile pwd "${ibmEntitlementKeyPath}" \
        --rawfile extra "${fusionPullSecretExtraPath}" \
        '.auths[$host] = {auth: ("cp:" + ($pwd | rtrimstr("\n")) | @base64), email: ""} | .auths["quay.io/openshift-storage-scale"] = {auth: ($extra | rtrimstr("\n")), email: ""}' | \
      oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/dev/stdin
  else
    oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | \
      jq -c \
        --arg host "${FA__IBM_REGISTRY}" \
        --rawfile pwd "${ibmEntitlementKeyPath}" \
        '.auths[$host] = {auth: ("cp:" + ($pwd | rtrimstr("\n")) | @base64), email: ""}' | \
      oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/dev/stdin
  fi
  set -x

  for ns in "${FA__SCALE__NAMESPACE}" "${FA__SCALE__DNS_NAMESPACE}" "${FA__SCALE__CSI_NAMESPACE}" "${FA__SCALE__OPERATOR_NAMESPACE}"; do
    CreateEntitlementSecretInNamespace "${ns}"
  done

  typeset currentSaSecrets=''
  if ! currentSaSecrets="$(oc get serviceaccount default -n "${FA__NAMESPACE}" -o jsonpath='{.imagePullSecrets[*].name}')"; then
    currentSaSecrets=""
  fi
  if [[ "${currentSaSecrets}" != *"fusion-pullsecret"* ]]; then
    oc patch serviceaccount default -n "${FA__NAMESPACE}" -p '{"imagePullSecrets":[{"name":"fusion-pullsecret"}]}'
  fi
fi

if oc get secret fusion-pullsecret-extra -n "${FA__NAMESPACE}"; then
  typeset currentSaSecrets=''
  if ! currentSaSecrets="$(oc get serviceaccount default -n "${FA__NAMESPACE}" -o jsonpath='{.imagePullSecrets[*].name}')"; then
    currentSaSecrets=""
  fi
  if [[ "${currentSaSecrets}" != *"fusion-pullsecret-extra"* ]]; then
    if [[ -n "${currentSaSecrets}" ]]; then
      oc patch serviceaccount default -n "${FA__NAMESPACE}" -p "{\"imagePullSecrets\":[{\"name\":\"fusion-pullsecret\"},{\"name\":\"fusion-pullsecret-extra\"}]}"
    else
      oc patch serviceaccount default -n "${FA__NAMESPACE}" -p '{"imagePullSecrets":[{"name":"fusion-pullsecret-extra"}]}'
    fi
  fi
else
  if [[ -f "${fusionPullSecretExtraPath}" ]]; then
    CreateRegistryAuthFromFile "${FA__NAMESPACE}" fusion-pullsecret-extra 'quay.io/openshift-storage-scale' "${fusionPullSecretExtraPath}"

    if ! oc wait --for=create secret/fusion-pullsecret-extra -n "${FA__NAMESPACE}" --timeout=60s; then
      oc get secret fusion-pullsecret-extra -n "${FA__NAMESPACE}" -o yaml --ignore-not-found
      exit 1
    fi

    typeset currentSaSecrets=''
    if ! currentSaSecrets="$(oc get serviceaccount default -n "${FA__NAMESPACE}" -o jsonpath='{.imagePullSecrets[*].name}')"; then
      currentSaSecrets=""
    fi
    if [[ "${currentSaSecrets}" != *"fusion-pullsecret-extra"* ]]; then
      if [[ -n "${currentSaSecrets}" ]]; then
        oc patch serviceaccount default -n "${FA__NAMESPACE}" -p "{\"imagePullSecrets\":[{\"name\":\"fusion-pullsecret\"},{\"name\":\"fusion-pullsecret-extra\"}]}"
      else
        oc patch serviceaccount default -n "${FA__NAMESPACE}" -p '{"imagePullSecrets":[{"name":"fusion-pullsecret-extra"}]}'
      fi
    fi
  else
    true
  fi
fi

true
