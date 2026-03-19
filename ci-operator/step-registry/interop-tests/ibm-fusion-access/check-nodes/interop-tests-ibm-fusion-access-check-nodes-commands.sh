#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

# JUnit XML test results configuration
typeset junitResultsFile="${ARTIFACT_DIR}/junit_check_nodes_tests.xml"
typeset -i testStartTime=0
testStartTime=$(date +%s)
typeset -i testsTotal=0
typeset -i testsFailed=0
typeset testCases=""

# Function to add test result to JUnit XML
function AddTestResult () {
  typeset testName="${1:-}"; (($#)) && shift
  typeset testStatus="${1:-}"; (($#)) && shift
  typeset testDuration="${1:-}"; (($#)) && shift
  typeset testMessage="${1:-}"; (($#)) && shift
  typeset testClassName="${1:-CheckNodesTests}"; (($#)) && shift
  
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
    if command -v yq; then
        true
    else
        mkdir -p /tmp/bin
        export PATH="${PATH}:/tmp/bin/"
        curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')" \
            -o /tmp/bin/yq && chmod +x /tmp/bin/yq
    fi
    true
}

function MapTestsForComponentReadiness () {
    [[ "${MAP_TESTS:-false}" != "true" ]] && return

    typeset resultsFile="${1:-}"
    if [[ -f "${resultsFile}" ]]; then
        InstallYQIfNotExists
        export REPORTPORTAL_CMP="${REPORTPORTAL_CMP:-}"
        yq eval -px -ox -iI0 '.testsuites.testsuite.+@name=env(REPORTPORTAL_CMP)' "${resultsFile}"
    fi
    true
}

# Function to generate JUnit XML report
function GenerateJunitXml () {
  typeset totalDuration=0
  totalDuration=$(($(date +%s) - testStartTime))
  
  cat > "${junitResultsFile}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Check Nodes Tests" tests="${testsTotal}" failures="${testsFailed}" errors="0" time="${totalDuration}">
${testCases}
  </testsuite>
</testsuites>
EOF
  
  MapTestsForComponentReadiness "${JUNIT_RESULTS_FILE:-${junitResultsFile}}"

  # Copy to SHARED_DIR for data router reporter (if available)
  if [[ -n "${SHARED_DIR}" ]] && [[ -d "${SHARED_DIR}" ]]; then
    cp "${junitResultsFile}" "${SHARED_DIR}/$(basename "${junitResultsFile}")"
  fi

  true
}

# Trap to ensure JUnit XML is generated even on failure
trap '{( GenerateJunitXml; true )}' EXIT

# Test 1: Verify minimum worker node count for quorum
typeset -i testStart=0
testStart=$(date +%s)
typeset testStatus="failed"
typeset testMessage=""

typeset nodesJson=''
nodesJson="$(oc get nodes -l node-role.kubernetes.io/worker= -o json)"
typeset -i workerNodeCount=0
workerNodeCount=$(printf '%s' "${nodesJson}" | jq '.items | length')

if [[ "${workerNodeCount}" -lt 3 ]]; then
  testMessage="Insufficient worker nodes: found ${workerNodeCount}, minimum 3 required for quorum"
else
  testStatus="passed"
fi

printf '%s' "${nodesJson}" | jq -r '.items[].metadata.name'

typeset -i testDuration=0
testDuration=$(($(date +%s) - testStart))
AddTestResult "test_worker_node_count_for_quorum" "${testStatus}" "${testDuration}" "${testMessage}"

true
