#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset FA__SCALE__NAMESPACE="${FA__SCALE__NAMESPACE:-ibm-spectrum-scale}"
typeset FA__SCALE__CLUSTER_NAME="${FA__SCALE__CLUSTER_NAME:-ibm-spectrum-scale}"
typeset FA__SCALE__CLIENT_CPU="${FA__SCALE__CLIENT_CPU:-2}"
typeset FA__SCALE__CLIENT_MEMORY="${FA__SCALE__CLIENT_MEMORY:-4Gi}"
typeset FA__SCALE__STORAGE_CPU="${FA__SCALE__STORAGE_CPU:-2}"
typeset FA__SCALE__STORAGE_MEMORY="${FA__SCALE__STORAGE_MEMORY:-8Gi}"

typeset junitResultsFile="${ARTIFACT_DIR}/junit_create_cluster_tests.xml"
typeset -i testStartTime=0
testStartTime=$(date +%s)
typeset -i testsTotal=0
typeset -i testsFailed=0
typeset testCases=''

function AddTestResult () {
  typeset testName="${1}"; (($#)) && shift
  typeset testStatus="${1}"; (($#)) && shift
  typeset testDuration="${1}"; (($#)) && shift
  typeset testMessage="${1:-}"; (($#)) && shift
  typeset testClassName="${1:-ClusterCreationTests}"; (($#)) && shift
  
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
        yq --version
    else
        mkdir -p /tmp/bin
        export PATH="${PATH}:/tmp/bin/"
        curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')" \
            -o /tmp/bin/yq
        chmod +x /tmp/bin/yq
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
  typeset totalDuration=0
  totalDuration=$(($(date +%s) - testStartTime))
  
  cat > "${junitResultsFile}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Create Cluster Tests" tests="${testsTotal}" failures="${testsFailed}" errors="0" time="${totalDuration}">
${testCases}
  </testsuite>
</testsuites>
EOF

  MapTestsForComponentReadiness "${junitResultsFile}"

  # Copy to SHARED_DIR for data router reporter (if available)
  if [[ -n "${SHARED_DIR}" ]] && [[ -d "${SHARED_DIR}" ]]; then
    cp "${junitResultsFile}" "${SHARED_DIR}/$(basename "${junitResultsFile}")"
  fi

  if [[ "${testsFailed}" -gt 0 ]]; then
    exit 1
  fi

  true
}

# Trap to ensure JUnit XML is generated even on failure
trap '{( GenerateJunitXml; true ); }' EXIT

typeset -i test1Start=0
test1Start=$(date +%s)
typeset test1Status="passed"
typeset test1Message=''

typeset clusterJson=''
typeset clusterExists=false
if clusterJson="$(oc get cluster "${FA__SCALE__CLUSTER_NAME}" -n "${FA__SCALE__NAMESPACE}" -o json)"; then
  clusterExists=true
else
  clusterJson=''
fi

typeset -i test1Duration=0
test1Duration=$(($(date +%s) - test1Start))
AddTestResult "test_cluster_idempotency_check" "${test1Status}" "${test1Duration}" "${test1Message}"

if [[ "${clusterExists}" == "false" ]]; then
  typeset -i test2Start=0
  test2Start=$(date +%s)
  typeset test2Status="failed"
  typeset test2Message=''
  
  typeset -i workerCount=0
  workerCount=$(
    oc get nodes \
      -l node-role.kubernetes.io/worker= \
      -o jsonpath-as-json='{.items[*].metadata.name}' |
    jq 'length'
  )

  if {
    oc create -f - --dry-run=client -o json --save-config |
    jq \
      --arg ns "${FA__SCALE__NAMESPACE}" \
      --arg name "${FA__SCALE__CLUSTER_NAME}" \
      --arg clientCpu "${FA__SCALE__CLIENT_CPU}" \
      --arg clientMem "${FA__SCALE__CLIENT_MEMORY}" \
      --arg storageCpu "${FA__SCALE__STORAGE_CPU}" \
      --arg storageMem "${FA__SCALE__STORAGE_MEMORY}" \
      --argjson quorum "$(( workerCount >= 3 ? 1 : 0 ))" \
      '
        .metadata.name = $name |
        .metadata.namespace = $ns |
        .spec.daemon.roles[0].resources = { cpu: $clientCpu, memory: $clientMem } |
        .spec.daemon.roles[1].resources = { cpu: $storageCpu, memory: $storageMem } |
        if $quorum == 0 then del(.spec.quorum) else . end
      '
  } 0<<'SKELETON' | oc apply -f -
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: Cluster
metadata:
  name: placeholder
  namespace: placeholder
spec:
  license:
    accept: true
    license: data-management
  pmcollector:
    nodeSelector:
      scale.spectrum.ibm.com/role: storage
  daemon:
    nodeSelector:
      scale.spectrum.ibm.com/role: storage
    nsdDevicesConfig:
      bypassDiscovery: false
    clusterProfile:
      cloudEnv: general
      controlSetxattrImmutableSELinux: "yes"
      enforceFilesetQuotaOnRoot: "yes"
      ignorePrefetchLUNCount: "yes"
      ignoreReplicaSpaceOnStat: "yes"
      ignoreReplicationForQuota: "yes"
      ignoreReplicationOnStatfs: "yes"
      initPrefetchBuffers: "128"
      maxblocksize: 16M
      prefetchPct: "25"
      prefetchTimeout: "30"
      readReplicaPolicy: local
      traceGenSubDir: /var/mmfs/tmp/traces
      tscCmdPortRange: 60000-61000
    update:
      paused: false
    roles:
    - name: client
      resources:
        cpu: ""
        memory: ""
    - name: storage
      resources:
        cpu: ""
        memory: ""
  gui:
    enableSessionIPCheck: true
  quorum:
    autoAssign: true
SKELETON
  then
    test2Status="passed"
  else
    test2Message="Failed to create Cluster resource via oc apply"
  fi
  
  typeset -i test2Duration=0
  test2Duration=$(($(date +%s) - test2Start))
  AddTestResult "test_cluster_creation" "${test2Status}" "${test2Duration}" "${test2Message}"

  clusterJson=''
  if ! clusterJson="$(oc get cluster "${FA__SCALE__CLUSTER_NAME}" -n "${FA__SCALE__NAMESPACE}" -o json)"; then
    clusterJson=''
  fi
fi

typeset -i test3Start=0
test3Start=$(date +%s)
typeset test3Status="failed"
typeset test3Message=''

if [[ -n "${clusterJson}" ]]; then
  test3Status="passed"
else
  test3Message="Cluster ${FA__SCALE__CLUSTER_NAME} not found in namespace ${FA__SCALE__NAMESPACE}"
fi

typeset -i test3Duration=0
test3Duration=$(($(date +%s) - test3Start))
AddTestResult "test_cluster_exists" "${test3Status}" "${test3Duration}" "${test3Message}"

typeset -i test4Start=0
test4Start=$(date +%s)
typeset test4Status="failed"
typeset test4Message=''

typeset bypassDiscovery=''
if [[ -n "${clusterJson}" ]]; then
  bypassDiscovery="$(printf '%s' "${clusterJson}" | jq -r '.spec.daemon.nsdDevicesConfig.bypassDiscovery // empty')"
fi

if [[ "${bypassDiscovery}" == "false" ]]; then
  test4Status="passed"
else
  test4Message="Cluster should have bypassDiscovery: false for shared SAN storage"
fi

typeset -i test4Duration=0
test4Duration=$(($(date +%s) - test4Start))
AddTestResult "test_cluster_auto_discovery" "${test4Status}" "${test4Duration}" "${test4Message}"

true
