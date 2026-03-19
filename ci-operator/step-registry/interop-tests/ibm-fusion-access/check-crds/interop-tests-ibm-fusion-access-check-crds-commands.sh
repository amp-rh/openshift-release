#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset junitResultsFile="${ARTIFACT_DIR}/junit_check_crds_tests.xml"
typeset -i testStartTime="${SECONDS}"
typeset -i testsTotal=0
typeset -i testsFailed=0
typeset testCases=''

function AddTestResult () {
  typeset testName="${1}"; (($#)) && shift
  typeset testStatus="${1}"; (($#)) && shift
  typeset testDuration="${1}"; (($#)) && shift
  typeset testMessage="${1:-}"; (($#)) && shift
  typeset testClassName="${1:-CheckCRDsTests}"; (($#)) && shift

  testsTotal=$((testsTotal + 1))

  if [[ "${testStatus}" == "passed" ]]; then
    testCases="${testCases}
    <testcase name=\"${testName}\" classname=\"${testClassName}\" time=\"${testDuration}\"/>"
  else
    testsFailed=$((testsFailed + 1))
    testCases="${testCases}
    <testcase name=\"${testName}\" classname=\"${testClassName}\" time=\"${testDuration}\">
      <failure message=\"Test failed\">${testMessage}</failure>
    </testcase>"
  fi

  true
}

function InstallYQIfNotExists () {
  if ! command -v yq; then
    mkdir -p /tmp/bin
    export PATH="${PATH}:/tmp/bin"
    curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')" \
      -o /tmp/bin/yq && chmod +x /tmp/bin/yq
  fi

  true
}

function MapTestsForComponentReadiness () {
  [[ "${MAP_TESTS:-false}" != "true" ]] && return

  typeset resultsFile="${1}"
  if [[ -f "${resultsFile}" ]]; then
    InstallYQIfNotExists
    export REPORTPORTAL_CMP="${REPORTPORTAL_CMP:-}"
    yq eval -px -ox -iI0 '.testsuites.testsuite.+@name=env(REPORTPORTAL_CMP)' "${resultsFile}"
  fi

  true
}

function GenerateJunitXml () {
  typeset -i totalDuration=$((SECONDS - testStartTime))
  
  cat > "${junitResultsFile}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Check CRDs Tests" tests="${testsTotal}" failures="${testsFailed}" errors="0" time="${totalDuration}">
${testCases}
  </testsuite>
</testsuites>
EOF

  MapTestsForComponentReadiness "${JUNIT_RESULTS_FILE:-${junitResultsFile}}"

  if [[ -n "${SHARED_DIR}" ]] && [[ -d "${SHARED_DIR}" ]]; then
    cp "${junitResultsFile}" "${SHARED_DIR}/$(basename "${junitResultsFile}")"
  fi

  true
}

trap '{( GenerateJunitXml; true )}' EXIT

# Test 1: Wait for CRDs to be established
typeset -i testStart="${SECONDS}"
typeset testStatus='failed'
typeset testMessage=''

# The FusionAccess operator installs the IBM Storage Scale operator which creates these CRDs
if oc wait --for=condition=Established crd/clusters.scale.spectrum.ibm.com --timeout=600s; then
  testStatus="passed"
else
  oc get crd clusters.scale.spectrum.ibm.com -o yaml --ignore-not-found
  testMessage="CRDs not established within 600s timeout"
fi

typeset -i testDuration=$((SECONDS - testStart))
AddTestResult "test_storage_scale_crds_established" "${testStatus}" "${testDuration}" "${testMessage}"

true
