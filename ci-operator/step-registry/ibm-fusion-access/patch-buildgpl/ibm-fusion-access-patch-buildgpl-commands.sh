#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

if ! (
    oc -n "${FA__SCALE__NAMESPACE}" wait configmap/buildgpl \
        --for create \
        --timeout=900s
); then
    typeset kmmCrdExists=''
    kmmCrdExists=$(oc get crd modules.kmm.sigs.x-k8s.io -o json 2>/dev/null | jq -r '.metadata.name // empty' || true)
    [[ -n "${kmmCrdExists}" ]] && exit 0
    false
fi

oc patch configmap buildgpl -n "${FA__SCALE__NAMESPACE}" --type=merge -p "$(cat <<'EOF'
data:
  buildgpl: |
    #!/bin/sh
    kerv=$(uname -r)

    rsync -av /host/var/lib/firmware/lxtrace-* /usr/lpp/mmfs/bin/ || echo "Warning: No lxtrace files found"

    touch /usr/lpp/mmfs/bin/lxtrace-$kerv
    chmod +x /usr/lpp/mmfs/bin/lxtrace-$kerv

    mkdir -p /lib/modules/$kerv/extra
    echo "# This is a workaround to pass file validation on IBM container" > /lib/modules/$kerv/extra/mmfslinux.ko
    echo "# This is a workaround to pass file validation on IBM container" > /lib/modules/$kerv/extra/tracedev.ko

    exit 0
EOF
)"

typeset daemonPods=0
daemonPods=$(oc get pods -n "${FA__SCALE__NAMESPACE}" -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core -o json | jq '.items | length')

if [[ "${daemonPods}" -gt 0 ]]; then
  oc delete pods -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core \
    -n "${FA__SCALE__NAMESPACE}" --ignore-not-found

  oc wait --for=condition=Ready pods -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core \
    -n "${FA__SCALE__NAMESPACE}" --timeout="${FA__SCALE__CORE_PODS_READY_TIMEOUT}"
fi

true
