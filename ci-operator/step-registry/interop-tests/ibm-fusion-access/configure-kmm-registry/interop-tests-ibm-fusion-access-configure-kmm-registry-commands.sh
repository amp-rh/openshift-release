#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset FA__NAMESPACE="${FA__NAMESPACE:-ibm-fusion-access}"
typeset FA__KMM__REGISTRY_URL="${FA__KMM__REGISTRY_URL:-}"
typeset FA__KMM__REGISTRY_ORG="${FA__KMM__REGISTRY_ORG:-}"
typeset FA__KMM__REGISTRY_REPO="${FA__KMM__REGISTRY_REPO:-gpfs-compat-kmod}"

typeset junitResultsFile="${ARTIFACT_DIR}/junit_configure_kmm_registry_tests.xml"
typeset testStartTime=0
testStartTime="$(date +%s)"
typeset -i testsTotal=0
typeset -i testsFailed=0
typeset testCases=''

function AddTestResult () {
  typeset testName="${1}"; (($#)) && shift
  typeset testStatus="${1}"; (($#)) && shift
  typeset testDuration="${1}"; (($#)) && shift
  typeset testMessage="${1:-}"; (($#)) && shift
  typeset testClassName="${1:-ConfigureKMMRegistryTests}"; (($#)) && shift
  typeset -n testsTotalRef="${1}"; (($#)) && shift
  typeset -n testsFailedRef="${1}"; (($#)) && shift
  typeset -n testCasesRef="${1}"; (($#)) && shift

  testsTotalRef=$((testsTotalRef + 1))

  if [[ "${testStatus}" == 'passed' ]]; then
    testCasesRef="${testCasesRef}
    <testcase name=\"${testName}\" classname=\"${testClassName}\" time=\"${testDuration}\"/>"
  else
    testsFailedRef=$((testsFailedRef + 1))
    testCasesRef="${testCasesRef}
    <testcase name=\"${testName}\" classname=\"${testClassName}\" time=\"${testDuration}\">
      <failure message=\"Test failed\">${testMessage}</failure>
    </testcase>"
  fi

  true
}

function InstallYqIfNotExists () {
  typeset yqPath=''
  if command -v yq; then
    yqPath="$(command -v yq)"
  fi
  if [[ -z "${yqPath}" ]]; then
    mkdir -p /tmp/bin
    export PATH="${PATH}:/tmp/bin/"
    typeset arch=''
    arch="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
    curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}" -o /tmp/bin/yq
    chmod +x /tmp/bin/yq
  fi
  true
}

function MapTestsForComponentReadiness () {
  [[ "${MAP_TESTS:-false}" != 'true' ]] && { true; return; }
  typeset resultsFile="${1}"; (($#)) && shift
  if [[ -f "${resultsFile}" ]]; then
    InstallYqIfNotExists
    export REPORTPORTAL_CMP="${REPORTPORTAL_CMP:-}"
    yq eval -px -ox -iI0 '.testsuites.testsuite.+@name=env(REPORTPORTAL_CMP)' "${resultsFile}"
  fi
  true
}

function GenerateJunitXml () {
  typeset totalDuration=0
  totalDuration="$(($(date +%s) - testStartTime))"
  
  cat > "${junitResultsFile}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Configure KMM Registry Tests" tests="${testsTotal}" failures="${testsFailed}" errors="0" time="${totalDuration}">
${testCases}
  </testsuite>
</testsuites>
EOF

  MapTestsForComponentReadiness "${junitResultsFile}"

  if [[ -n "${SHARED_DIR}" ]] && [[ -d "${SHARED_DIR}" ]]; then
    cp "${junitResultsFile}" "${SHARED_DIR}/$(basename "${junitResultsFile}")"
  fi

  if [[ "${testsFailed}" -gt 0 ]]; then
    exit 1
  fi

  true
}

trap '{( GenerateJunitXml; true )}' EXIT

typeset test1Start=0
test1Start="$(date +%s)"
typeset test1Status='passed'
typeset test1Message=''

if oc get configmap kmm-image-config -n "${FA__NAMESPACE}"; then
  test1Status='passed'
else
  test1Status='failed'
  test1Message='kmm-image-config ConfigMap not found (idempotency pre-check)'
fi

typeset test1Duration=0
test1Duration="$(($(date +%s) - test1Start))"
AddTestResult 'test_kmm_config_idempotency_check' "${test1Status}" "${test1Duration}" "${test1Message}" 'ConfigureKMMRegistryTests' 'testsTotal' 'testsFailed' 'testCases'

typeset test2Start=0
test2Start="$(date +%s)"
typeset test2Status='failed'
typeset test2Message=''

typeset finalRegistryUrl=''
typeset fullRepo=''
if [[ -n "${FA__KMM__REGISTRY_ORG}" ]]; then
  finalRegistryUrl="${FA__KMM__REGISTRY_URL:-quay.io}"
  fullRepo="${FA__KMM__REGISTRY_ORG}/${FA__KMM__REGISTRY_REPO}"
else
  finalRegistryUrl='image-registry.openshift-image-registry.svc:5000'
  fullRepo="ibm-spectrum-scale/${FA__KMM__REGISTRY_REPO}"
fi

if oc create configmap kmm-image-config \
  -n "${FA__NAMESPACE}" \
  --from-literal=kmm_image_registry_url="${finalRegistryUrl}" \
  --from-literal=kmm_image_repo="${fullRepo}" \
  --from-literal=kmm_tls_insecure="false" \
  --from-literal=kmm_tls_skip_verify="false" \
  --dry-run=client -o yaml --save-config | oc apply -f -
then
  test2Status='passed'
else
  test2Message='Failed to create kmm-image-config ConfigMap via oc apply'
fi

typeset test2Duration=0
test2Duration="$(($(date +%s) - test2Start))"
AddTestResult 'test_create_kmm_config' "${test2Status}" "${test2Duration}" "${test2Message}" 'ConfigureKMMRegistryTests' 'testsTotal' 'testsFailed' 'testCases'

typeset test3Start=0
test3Start="$(date +%s)"
typeset test3Status='failed'
typeset test3Message=''

typeset cmJson=''
typeset ocExit=0
cmJson="$(oc get configmap kmm-image-config -n "${FA__NAMESPACE}" -o json)" || ocExit=$?
if (( ocExit == 0 )); then
  typeset registryUrl=''
  registryUrl="$(printf '%s' "${cmJson}" | jq -r '.data.kmm_image_registry_url // empty')"
  typeset registryRepo=''
  registryRepo="$(printf '%s' "${cmJson}" | jq -r '.data.kmm_image_repo // empty')"

  if [[ -n "${registryUrl}" ]] && [[ -n "${registryRepo}" ]]; then
    test3Status='passed'
  else
    test3Message='ConfigMap exists but missing kmm_image_registry_url or kmm_image_repo'
  fi
else
  test3Message="kmm-image-config ConfigMap not found in namespace ${FA__NAMESPACE}"
fi

typeset test3Duration=0
test3Duration="$(($(date +%s) - test3Start))"
AddTestResult 'test_verify_kmm_config_content' "${test3Status}" "${test3Duration}" "${test3Message}" 'ConfigureKMMRegistryTests' 'testsTotal' 'testsFailed' 'testCases'

typeset test4Start=0
test4Start="$(date +%s)"
typeset test4Status='failed'
typeset test4Message=''

if oc create configmap kmm-image-config \
  -n ibm-spectrum-scale-operator \
  --from-literal=kmm_image_registry_url="${finalRegistryUrl}" \
  --from-literal=kmm_image_repo="${fullRepo}" \
  --from-literal=kmm_tls_insecure="false" \
  --from-literal=kmm_tls_skip_verify="false" \
  --dry-run=client -o yaml --save-config | oc apply -f -
then
  test4Status='passed'
else
  test4Message='Failed to create kmm-image-config in ibm-spectrum-scale-operator namespace'
fi

typeset test4Duration=0
test4Duration="$(($(date +%s) - test4Start))"
AddTestResult 'test_create_kmm_config_in_scale_operator_namespace' "${test4Status}" "${test4Duration}" "${test4Message}" 'ConfigureKMMRegistryTests' 'testsTotal' 'testsFailed' 'testCases'

true
