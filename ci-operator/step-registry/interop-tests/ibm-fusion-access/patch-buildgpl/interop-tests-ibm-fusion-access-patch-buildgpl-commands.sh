#!/bin/bash
set -eux -o pipefail; shopt -s inherit_errexit

typeset FA__SCALE__NAMESPACE="${FA__SCALE__NAMESPACE:-ibm-spectrum-scale}"
typeset FA__NAMESPACE="${FA__NAMESPACE:-ibm-fusion-access}"

if oc get configmap kmm-dockerfile -n "${FA__NAMESPACE}" -o name; then
  exit 0
fi

if ! oc -n "${FA__SCALE__NAMESPACE}" wait configmap/buildgpl --for=create --timeout=900s; then
  oc get configmap buildgpl -n "${FA__SCALE__NAMESPACE}" -o yaml --ignore-not-found
  exit 0
fi

oc patch configmap buildgpl -n "${FA__SCALE__NAMESPACE}" --type=merge -p "$(cat <<'EOF'
data:
  buildgpl: |
    #!/bin/sh
    kerv=$(uname -r)

    rsync -av /host/var/lib/firmware/lxtrace-* /usr/lpp/mmfs/bin/ || echo "Warning: No lxtrace files found"

    touch "/usr/lpp/mmfs/bin/lxtrace-${kerv}"
    chmod +x "/usr/lpp/mmfs/bin/lxtrace-${kerv}"

    mkdir -p "/lib/modules/${kerv}/extra"
    echo "# This is a workaround to pass file validation on IBM container" > "/lib/modules/${kerv}/extra/mmfslinux.ko"
    echo "# This is a workaround to pass file validation on IBM container" > "/lib/modules/${kerv}/extra/tracedev.ko"

    exit 0
EOF
)"

typeset -i daemonPods=0
daemonPods=$(oc get pods -n "${FA__SCALE__NAMESPACE}" -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core -o jsonpath-as-json='{.items[*].metadata.name}' | jq 'length')

if ((daemonPods > 0)); then
  oc delete pods -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core \
    -n "${FA__SCALE__NAMESPACE}" --ignore-not-found

  if ! oc wait --for=condition=Ready pods -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core \
    -n "${FA__SCALE__NAMESPACE}" --timeout="${FA__SCALE__CORE_PODS_READY_TIMEOUT:-120}s"; then
    oc get pods -l app.kubernetes.io/instance=ibm-spectrum-scale,app.kubernetes.io/name=core \
      -n "${FA__SCALE__NAMESPACE}" -o yaml --ignore-not-found
    exit 1
  fi
fi

true
