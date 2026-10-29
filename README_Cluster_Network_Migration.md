# Cluster Network Migration


Until now, I had two Kubernetes clusters. 

One runs K3s on four Raspberry Pi 4 Model B devices and serves as my home lab. Each machine runs Raspberry Pi OS. This is intended to be my stable environment. I may recreate this cluster with upstream Kubernetes in the future, but for now I prefer to keep it stable on K3s, as I have other priorities.

The other cluster consists of three Raspberry Pi 4 Model B devices running Ubuntu Server and upstream Kubernetes. This is the cluster I used to prepare for the CKAD exam. Its purpose is to test, break, and rebuild the cluster.

Until now, both clusters shared the `192.168.3.0/24` network. However, I decided to separate the clusters into different networks. The more stable K3s cluster remains on `192.168.3.0/24`. The upstream Kubernetes cluster was moved to the new `192.168.4.0/24` network.

## Machines Running, but no Cluster

The machines were running and accessible at the static IP addresses I had reserved for them on the router. As expected, however, the cluster was broken: its configuration depended on the previous IP addresses, including the control-plane address, so `kubectl` could no longer communicate with the cluster.

The first things I thought needed checking were:

1) .kube/config  so that kubectl knows where the cluster is
2) cluster configuration
3) calico configuration


```bash
$ kubectl config view
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://192.168.3.20:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
kind: Config
preferences: {}
users:
- name: kubernetes-admin
  user:
    client-certificate-data: DATA+OMITTED
    client-key-data: DATA+OMITTED
``` 


The first change was to update `~/.kube/config` so that the cluster endpoint used the correct IP address. At least the expected control-plane IP was now configured.

```bash
$ kubectl get nodes -o wide
E1016 20:13:08.198150    5357 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:13:08.200202    5357 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:13:08.202208    5357 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:13:08.204503    5357 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:13:08.206577    5357 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
The connection to the server 192.168.4.10:6443 was refused - did you specify the right host or port?

``` 

In a production environment, I would not expect to handle this kind of network change by manually updating a cluster. If a cluster needed to move to a new network, I would consider creating a new cluster on that network instead. Next, I would install the required CRDs and configure Argo CD. After verifying that everything was running correctly, I would remove the old cluster. In this homelab, given the purpose of this cluster, I could simply reformat the Raspberry Pi storage, install the control plane, and join the worker nodes. But then I thought: Kubernetes relies on configuration, so why not inspect the files one by one and replace the old network IP addresses?  In the worst-case scenario, this would still be useful study material, because I would inspect the files one by one and learn what they contain.


I started by checking the files under `/etc/kubernetes` one by one. The following files contained either a node IP address or a network address that needed to be changed:

### Control Plane

* /etc/kubernetes/admin.conf
* /etc/kubernetes/controller-manager.conf
* /etc/kubernetes/kubelet.conf
* /etc/kubernetes/scheduler.conf
* /etc/kubernetes/super-admin.conf
* /etc/kubernetes/manifests/etcd.yaml
* /etc/kubernetes/manifests/kube-apiserver.yaml

Files that did not need to be changed

* /etc/kubernetes/manifests/kube-controller-manager.yaml
* /etc/kubernetes/manifests/kube-scheduler.yaml
* /etc/kubernetes/pki (since these are just certificates, which I'll need to recreate)


### Data Plane - Node 1

* /etc/kubernetes/kubelet.conf


### Data Plane - Node 2

* /etc/kubernetes/kubelet.conf


After these changes, the connection to the API server was still not working.


```bash
$ kubectl get nodes
E1016 20:46:25.616384    7186 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:46:25.618393    7186 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:46:25.620278    7186 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:46:25.622351    7186 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
E1016 20:46:25.624421    7186 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": dial tcp 192.168.4.10:6443: connect: connection refused"
The connection to the server 192.168.4.10:6443 was refused - did you specify the right host or port?

``` 

The first step was to restart all nodes in the cluster. Based on a previous experience with my K3s cluster—which had previously used `192.168.2.0/24` before moving to `192.168.3.0/24`—I knew that I would also need to address the certificates. After the reboot, checking the nodes confirmed the certificate problem.




```bash
$ kubectl get nodes
E1016 20:50:49.148080    2271 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": tls: failed to verify certificate: x509: certificate is valid for 10.96.0.1, 192.168.3.20, not 192.168.4.10"
E1016 20:50:49.162462    2271 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": tls: failed to verify certificate: x509: certificate is valid for 10.96.0.1, 192.168.3.20, not 192.168.4.10"
E1016 20:50:49.176513    2271 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": tls: failed to verify certificate: x509: certificate is valid for 10.96.0.1, 192.168.3.20, not 192.168.4.10"
E1016 20:50:49.191035    2271 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": tls: failed to verify certificate: x509: certificate is valid for 10.96.0.1, 192.168.3.20, not 192.168.4.10"
E1016 20:50:49.205696    2271 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"https://192.168.4.10:6443/api?timeout=32s\": tls: failed to verify certificate: x509: certificate is valid for 10.96.0.1, 192.168.3.20, not 192.168.4.10"
Unable to connect to the server: tls: failed to verify certificate: x509: certificate is valid for 10.96.0.1, 192.168.3.20, not 192.168.4.10

``` 

I therefore ran the following command on the control-plane node:

```bash
kubeadm certs renew all

``` 



```bash

$ sudo kubeadm certs renew all
[renew] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[renew] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.
[renew] Error reading configuration from the Cluster. Falling back to default configuration

certificate embedded in the kubeconfig file for the admin to use and for kubeadm itself renewed
certificate for serving the Kubernetes API renewed
certificate the apiserver uses to access etcd renewed
certificate for the API server to connect to kubelet renewed
certificate embedded in the kubeconfig file for the controller manager to use renewed
certificate for liveness probes to healthcheck etcd renewed
certificate for etcd nodes to communicate with each other renewed
certificate for serving etcd renewed
certificate for the front proxy client renewed
certificate embedded in the kubeconfig file for the scheduler manager to use renewed
certificate embedded in the kubeconfig file for the super-admin renewed

Done renewing certificates. You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd, so that they can use the new certificates.

```

I restarted all the nodes, but the problem persisted. After making this change and recreating the affected Pods:me research, I backed up the relevant data.

backup data

```bash
sudo tar czf "$HOME/kubernetes-pki-backup.tar.gz" -C /etc/kubernetes pki

sudo cp -a /etc/kubernetes/manifests  "$HOME/kubernetes-manifests-backup"

```

Since the Certificate Authority (CA) private key was available at `/etc/kubernetes/pki/ca.key`, I could generate a new API server certificate.

First, I checked the contents of the existing certificate:

```bash
 sudo openssl x509 \
  -in /etc/kubernetes/pki/apiserver.crt \
  -noout -ext subjectAltName
```

And I got

```bash
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, IP Address:10.96.0.1, IP Address:192.168.3.20
```

```bash

sudo mkdir -p /root/apiserver-old-cert

sudo mv /etc/kubernetes/pki/apiserver.crt \
  /root/apiserver-old-cert/

sudo mv /etc/kubernetes/pki/apiserver.key \
  /root/apiserver-old-cert/

```

followed by

```bash

sudo kubeadm init phase certs apiserver \
  --apiserver-advertise-address=192.168.4.10 \
  --apiserver-cert-extra-sans=192.168.4.10 \
  --service-cidr=10.96.0.0/12 \
  --service-dns-domain=cluster.local

```

```bash
$ sudo kubeadm init phase certs apiserver \
  --apiserver-advertise-address=192.168.4.10 \
  --apiserver-cert-extra-sans=192.168.4.10 \
  --service-cidr=10.96.0.0/12 \
  --service-dns-domain=cluster.local
I1016 21:19:15.317806    3116 version.go:261] remote version is much newer: v1.37.1; falling back to: stable-1.33
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [c2master kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 192.168.4.10]
```


The validation showed that all the DNS names were still present, along with the new control-plane IP address.

```bash

sudo openssl x509 \
  -in /etc/kubernetes/pki/apiserver.crt \
  -noout -ext subjectAltName
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, IP Address:10.96.0.1, IP Address:192.168.4.10

```

I now needed to restart the API server. Because it runs as a static Pod, I temporarily moved `kube-apiserver.yaml` out of the manifests directory and then moved it back.

```bash

sudo mkdir -p /root/k8s-manifest-hold

sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml  /root/k8s-manifest-hold/
```


After waiting a while, I restored the API server manifest.

```bash

sudo mv /root/k8s-manifest-hold/kube-apiserver.yaml  /etc/kubernetes/manifests/

```

After this, the nodes returned the expected result:

```bash
$ kubectl get nodes -o wide
NAME        STATUS   ROLES           AGE   VERSION    INTERNAL-IP    EXTERNAL-IP   OS-IMAGE           KERNEL-VERSION     CONTAINER-RUNTIME
c2master    Ready    control-plane   15d   v1.33.13   192.168.4.10   <none>        Ubuntu 26.04 LTS   7.0.0-1020-raspi   containerd://2.2.2
c2worker1   Ready    <none>          15d   v1.33.13   192.168.4.11   <none>        Ubuntu 26.04 LTS   7.0.0-1020-raspi   containerd://2.2.2
c2worker2   Ready    <none>          15d   v1.33.13   192.168.4.12   <none>        Ubuntu 26.04 LTS   7.0.0-1020-raspi   containerd://2.2.2

```

However, the work was not finished yet.


```bash
$ kubectl get pods -A -o wide
NAMESPACE           NAME                                       READY   STATUS             RESTARTS         AGE     IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-lhkxm   0/1     Unknown            10               15d     <none>         c2master    <none>           <none>
calico-system       calico-node-8fr9c                          0/1     Unknown            8                15d     192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-q7mrb                          0/1     Unknown            9                15d     192.168.4.10   c2master    <none>           <none>
calico-system       calico-node-srrwr                          0/1     Unknown            8                15d     192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-typha-589dbfbbd5-r5rzk              0/1     CrashLoopBackOff   9 (2m55s ago)    14d     192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-typha-589dbfbbd5-z7zp4              0/1     Running            10 (2m25s ago)   14d     192.168.4.10   c2master    <none>           <none>
calico-system       csi-node-driver-dtxg8                      0/2     Unknown            18               15d     <none>         c2master    <none>           <none>
calico-system       csi-node-driver-tblb4                      0/2     Unknown            16               15d     <none>         c2worker1   <none>           <none>
calico-system       csi-node-driver-v7nxw                      0/2     Unknown            16               15d     <none>         c2worker2   <none>           <none>
gateway-study       android-deploy-8597675569-pb59g            0/1     Unknown            0                26h     <none>         c2worker1   <none>           <none>
gateway-study       android-deploy-8597675569-xt27j            0/1     Unknown            0                26h     <none>         c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-4rg4p            0/1     Unknown            0                26h     <none>         c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-jqv7q            0/1     Unknown            0                26h     <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-zw4s8              0/1     Unknown            0                26h     <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-zz92c              0/1     Unknown            0                26h     <none>         c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-27k49                   0/1     Unknown            5                9d      <none>         c2master    <none>           <none>
kube-system         coredns-674b8bbfcf-p9756                   0/1     Unknown            7                14d     <none>         c2master    <none>           <none>
kube-system         etcd-c2master                              1/1     Running            1 (30m ago)      8m25s   192.168.4.10   c2master    <none>           <none>
kube-system         kube-apiserver-c2master                    1/1     Running            2 (5m7s ago)     8m25s   192.168.4.10   c2master    <none>           <none>
kube-system         kube-controller-manager-c2master           1/1     Running            12 (5m27s ago)   14d     192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-8tvnj                           1/1     Running            8 (130m ago)     14d     192.168.4.12   c2worker2   <none>           <none>
kube-system         kube-proxy-jn2jz                           1/1     Running            9 (130m ago)     14d     192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-ncxjv                           1/1     Running            8 (130m ago)     14d     192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-scheduler-c2master                    1/1     Running            12 (5m27s ago)   14d     192.168.4.10   c2master    <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-r8f6z             0/1     Unknown            0                26h     <none>         c2worker2   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-wv6bj   0/1     Unknown            0                26h     <none>         c2worker1   <none>           <none>
study               web-6c79984869-2htwt                       0/1     Unknown            1                2d3h    <none>         c2worker2   <none>           <none>
tigera-operator     tigera-operator-747864d56d-krn5f           1/1     Running            12 (130m ago)    15d     192.168.4.10   c2master    <none>           <none>
traefik             traefik-66bfd6b9b4-kc6jc                   0/1     Unknown            1                2d2h    <none>         c2worker2   <none>           <none>

```

I renewed all certificates as an additional precaution. This time, I did not receive the error message "Error reading configuration from the Cluster. Falling back to default configuration


```bash
 sudo kubeadm certs renew all
[renew] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[renew] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.

certificate embedded in the kubeconfig file for the admin to use and for kubeadm itself renewed
certificate for serving the Kubernetes API renewed
certificate the apiserver uses to access etcd renewed
certificate for the API server to connect to kubelet renewed
certificate embedded in the kubeconfig file for the controller manager to use renewed
certificate for liveness probes to healthcheck etcd renewed
certificate for etcd nodes to communicate with each other renewed
certificate for serving etcd renewed
certificate for the front proxy client renewed
certificate embedded in the kubeconfig file for the scheduler manager to use renewed
certificate embedded in the kubeconfig file for the super-admin renewed

Done renewing certificates. You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd, so that they can use the new certificates.
```


I then ran the following command on both worker nodes: 


```bash

sudo systemctl restart kubelet

```

I also noticed that the Calico Typha Pods were restarting.

```bash
$ kubectl get pods -A -o wide
NAMESPACE           NAME                                       READY   STATUS    RESTARTS        AGE    IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-lhkxm   0/1     Unknown   10              15d    <none>         c2master    <none>           <none>
calico-system       calico-node-8fr9c                          0/1     Unknown   8               15d    192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-q7mrb                          0/1     Unknown   9               15d    192.168.4.10   c2master    <none>           <none>
calico-system       calico-node-srrwr                          0/1     Unknown   8               15d    192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-typha-589dbfbbd5-r5rzk              0/1     Running   11 (10s ago)    14d    192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-typha-589dbfbbd5-z7zp4              0/1     Running   13 (9s ago)     14d    192.168.4.10   c2master    <none>           <none>
calico-system       csi-node-driver-dtxg8                      0/2     Unknown   18              15d    <none>         c2master    <none>           <none>
calico-system       csi-node-driver-tblb4                      0/2     Unknown   16              15d    <none>         c2worker1   <none>           <none>
calico-system       csi-node-driver-v7nxw                      0/2     Unknown   16              15d    <none>         c2worker2   <none>           <none>
gateway-study       android-deploy-8597675569-pb59g            0/1     Unknown   0               26h    <none>         c2worker1   <none>           <none>
gateway-study       android-deploy-8597675569-xt27j            0/1     Unknown   0               26h    <none>         c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-4rg4p            0/1     Unknown   0               26h    <none>         c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-jqv7q            0/1     Unknown   0               26h    <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-zw4s8              0/1     Unknown   0               26h    <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-zz92c              0/1     Unknown   0               26h    <none>         c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-27k49                   0/1     Unknown   5               9d     <none>         c2master    <none>           <none>
kube-system         coredns-674b8bbfcf-p9756                   0/1     Unknown   7               14d    <none>         c2master    <none>           <none>
kube-system         etcd-c2master                              1/1     Running   1 (37m ago)     15m    192.168.4.10   c2master    <none>           <none>
kube-system         kube-apiserver-c2master                    1/1     Running   2 (11m ago)     15m    192.168.4.10   c2master    <none>           <none>
kube-system         kube-controller-manager-c2master           1/1     Running   12 (12m ago)    14d    192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-8tvnj                           1/1     Running   8 (136m ago)    14d    192.168.4.12   c2worker2   <none>           <none>
kube-system         kube-proxy-jn2jz                           1/1     Running   9 (137m ago)    14d    192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-ncxjv                           1/1     Running   8 (136m ago)    14d    192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-scheduler-c2master                    1/1     Running   12 (12m ago)    14d    192.168.4.10   c2master    <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-r8f6z             0/1     Unknown   0               26h    <none>         c2worker2   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-wv6bj   0/1     Unknown   0               26h    <none>         c2worker1   <none>           <none>
study               web-6c79984869-2htwt                       0/1     Unknown   1               2d3h   <none>         c2worker2   <none>           <none>
tigera-operator     tigera-operator-747864d56d-krn5f           1/1     Running   12 (137m ago)   15d    192.168.4.10   c2master    <none>           <none>
traefik             traefik-66bfd6b9b4-kc6jc                   0/1     Unknown   1               2d2h   <none>         c2worker2   <none>           <none>
```


When I created the cluster and installed Calico, I configured some IP-address-related settings. Reviewing these settings, I could not find a reference to the node network CIDR or the control-plane IP address.

```bash

# 1) Install the operator and CRDs
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/tigera-operator.yaml

# 2) Apply a minimal Installation CR (no calico-apiserver)
cat <<'EOF' | kubectl apply -f -
apiVersion: operator.tigera.io/v1        # Calico Operator API group/version
kind: Installation                        # Cluster-wide Calico install spec
metadata:
  name: default                           # Must be named 'default' (singleton)
spec:
  calicoNetwork:                          # Calico networking settings
    bgp: Disabled                         # Added later. Refer "Calico Troubleshooting" section of this lecture
    ipPools:
    - cidr: 10.2.0.0/16                   # Pod CIDR (matches kubeadm --pod-network-cidr)
      natOutgoing: Enabled                # SNAT pod→external traffic at node egress
      blockSize: 26                       # Per-node IP block size (/26 = 64 pod IPs)
      encapsulation: VXLANCrossSubnet     # Use VXLAN; skip encapsulation within same L2 subnet
      nodeSelector: all()                 # Apply this pool to all nodes
EOF


```

I then grouped the Pods by their status.


```bash
$ kubectl get pods -A -o wide
NAMESPACE           NAME                                       READY   STATUS    RESTARTS        AGE     IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-typha-589dbfbbd5-r5rzk              0/1     Running   14 (78s ago)    14d     192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-typha-589dbfbbd5-z7zp4              0/1     Running   16 (71s ago)    14d     192.168.4.10   c2master    <none>           <none>
kube-system         etcd-c2master                              1/1     Running   2 (7m6s ago)    9h      192.168.4.10   c2master    <none>           <none>
kube-system         kube-apiserver-c2master                    1/1     Running   3 (7m6s ago)    9h      192.168.4.10   c2master    <none>           <none>
kube-system         kube-controller-manager-c2master           1/1     Running   13 (7m6s ago)   14d     192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-8tvnj                           1/1     Running   9 (7m ago)      14d     192.168.4.12   c2worker2   <none>           <none>
kube-system         kube-proxy-jn2jz                           1/1     Running   10 (7m6s ago)   14d     192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-ncxjv                           1/1     Running   9 (7m ago)      14d     192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-scheduler-c2master                    1/1     Running   13 (7m6s ago)   14d     192.168.4.10   c2master    <none>           <none>
tigera-operator     tigera-operator-747864d56d-krn5f           1/1     Running   13 (7m6s ago)   15d     192.168.4.10   c2master    <none>           <none>

```


```bash
$ kubectl get pods -A -o wide
NAMESPACE           NAME                                       READY   STATUS    RESTARTS        AGE     IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-lhkxm   0/1     Unknown   10              15d     <none>         c2master    <none>           <none>
calico-system       calico-node-8fr9c                          0/1     Unknown   8               15d     192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-q7mrb                          0/1     Unknown   9               15d     192.168.4.10   c2master    <none>           <none>
calico-system       calico-node-srrwr                          0/1     Unknown   8               15d     192.168.4.11   c2worker1   <none>           <none>
calico-system       csi-node-driver-dtxg8                      0/2     Unknown   18              15d     <none>         c2master    <none>           <none>
calico-system       csi-node-driver-tblb4                      0/2     Unknown   16              15d     <none>         c2worker1   <none>           <none>
calico-system       csi-node-driver-v7nxw                      0/2     Unknown   16              15d     <none>         c2worker2   <none>           <none>
gateway-study       android-deploy-8597675569-pb59g            0/1     Unknown   0               35h     <none>         c2worker1   <none>           <none>
gateway-study       android-deploy-8597675569-xt27j            0/1     Unknown   0               35h     <none>         c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-4rg4p            0/1     Unknown   0               35h     <none>         c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-jqv7q            0/1     Unknown   0               35h     <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-zw4s8              0/1     Unknown   0               35h     <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-zz92c              0/1     Unknown   0               35h     <none>         c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-27k49                   0/1     Unknown   5               9d      <none>         c2master    <none>           <none>
kube-system         coredns-674b8bbfcf-p9756                   0/1     Unknown   7               14d     <none>         c2master    <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-r8f6z             0/1     Unknown   0               35h     <none>         c2worker2   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-wv6bj   0/1     Unknown   0               35h     <none>         c2worker1   <none>           <none>
study               web-6c79984869-2htwt                       0/1     Unknown   1               2d12h   <none>         c2worker2   <none>           <none>
traefik             traefik-66bfd6b9b4-kc6jc                   0/1     Unknown   1               2d12h   <none>         c2worker2   <none>           <none>

```

The Pods in the `kube-system` namespace appeared to be running. The `csi-node-driver` Pods were not working. I decided to start with these Pods because this cluster uses NFS, whose IP address had been in the `192.168.3.0/24` subnet.



```bash
$ kubectl -n calico-system get pods
NAME                                       READY   STATUS             RESTARTS         AGE
calico-kube-controllers-76fc5b9999-lhkxm   0/1     Unknown            10               15d
calico-node-8fr9c                          0/1     Unknown            8                15d
calico-node-q7mrb                          0/1     Unknown            9                15d
calico-node-srrwr                          0/1     Unknown            8                15d
calico-typha-589dbfbbd5-r5rzk              0/1     Running            19 (109s ago)    14d
calico-typha-589dbfbbd5-z7zp4              0/1     CrashLoopBackOff   19 (4m42s ago)   14d
csi-node-driver-dtxg8                      0/2     Unknown            18               15d
csi-node-driver-tblb4                      0/2     Unknown            16               15d
csi-node-driver-v7nxw                      0/2     Unknown            16               15d
```


```bash
 kubectl -n calico-system describe pod calico-typha-589dbfbbd5-z7zp4

(...)
Events:
  Type     Reason          Age                   From     Message
  ----     ------          ----                  ----     -------
  Normal   SandboxChanged  10h                   kubelet  Pod sandbox changed, it will be killed and re-created.
  Warning  Unhealthy       10h (x6 over 10h)     kubelet  Liveness probe failed: Get "http://localhost:9098/liveness": dial tcp [::1]:9098: connect: connection refused
  Normal   Killing         9h (x5 over 10h)      kubelet  Container calico-typha failed liveness probe, will be restarted
  Normal   Pulled          9h (x6 over 10h)      kubelet  Container image "docker.io/calico/typha:v3.30.2" already present on machine
  Normal   Created         9h (x6 over 10h)      kubelet  Created container: calico-typha
  Normal   Started         9h (x6 over 10h)      kubelet  Started container calico-typha
  Warning  Unhealthy       9h (x49 over 10h)     kubelet  Readiness probe failed: Get "http://localhost:9098/readiness": dial tcp [::1]:9098: connect: connection refused
  Normal   SandboxChanged  27m                   kubelet  Pod sandbox changed, it will be killed and re-created.
  Warning  Failed          27m (x2 over 27m)     kubelet  Error: services have not yet been read at least once, cannot construct envvars
  Warning  Unhealthy       17m (x33 over 26m)    kubelet  Readiness probe failed: Get "http://localhost:9098/readiness": dial tcp [::1]:9098: connect: connection refused
  Normal   Pulled          8m10s (x8 over 27m)   kubelet  Container image "docker.io/calico/typha:v3.30.2" already present on machine
  Normal   Started         8m10s (x6 over 27m)   kubelet  Started container calico-typha
  Normal   Created         8m10s (x6 over 27m)   kubelet  Created container: calico-typha
  Warning  Unhealthy       7m10s (x16 over 27m)  kubelet  Liveness probe failed: Get "http://localhost:9098/liveness": dial tcp [::1]:9098: connect: connection refused
  Normal   Killing         5m10s (x6 over 25m)   kubelet  Container calico-typha failed liveness probe, will be restarted
  Warning  BackOff         2m26s (x39 over 16m)  kubelet  Back-off restarting failed container calico-typha in pod calico-typha-589dbfbbd5-z7zp4_calico-system(e29e301c-ab12-4dd9-a088-143b521ef018)
```

I decided to recreate all Pods. This would cause them all to be recreated. I could then investigate each problem from that point. This would give me a clean slate, with Pods created under the new configuration.

```bash
kubectl get pods -A --no-headers |
while read -r namespace name _; do
    kubectl delete pod "$name" -n "$namespace" --grace-period=0 --force
done
```

Once I did that, I still see some errors

```bash
NAMESPACE           NAME                                       READY   STATUS              RESTARTS      AGE   IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-p2m26   0/1     ContainerCreating   0             75s   <none>         c2worker1   <none>           <none>
calico-system       calico-node-2fcdx                          0/1     Init:Error          1 (41s ago)   75s   192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-j4jpm                          0/1     Init:Error          1 (39s ago)   74s   192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-node-s9pvh                          0/1     Init:Error          1 (39s ago)   75s   192.168.4.10   c2master    <none>           <none>
calico-system       calico-typha-589dbfbbd5-77zs9              0/1     Running             0             74s   192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-typha-589dbfbbd5-87z57              0/1     Running             0             74s   192.168.4.12   c2worker2   <none>           <none>
calico-system       csi-node-driver-2t6hj                      0/2     ContainerCreating   0             72s   <none>         c2worker1   <none>           <none>
calico-system       csi-node-driver-755zx                      0/2     ContainerCreating   0             73s   <none>         c2master    <none>           <none>
calico-system       csi-node-driver-zx44c                      0/2     ContainerCreating   0             72s   <none>         c2worker2   <none>           <none>
gateway-study       android-deploy-8597675569-ckggs            0/1     ContainerCreating   0             71s   <none>         c2worker2   <none>           <none>
gateway-study       android-deploy-8597675569-pv2gk            0/1     ContainerCreating   0             72s   <none>         c2worker1   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-grwxr            0/1     ContainerCreating   0             71s   <none>         c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-hkswb            0/1     ContainerCreating   0             71s   <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-24dr8              0/1     ContainerCreating   0             70s   <none>         c2worker1   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-xlm9h              0/1     ContainerCreating   0             70s   <none>         c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-gbg6r                   0/1     ContainerCreating   0             69s   <none>         c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-mz54z                   0/1     ContainerCreating   0             70s   <none>         c2worker1   <none>           <none>
kube-system         etcd-c2master                              1/1     Running             2 (41m ago)   7s    192.168.4.10   c2master    <none>           <none>
kube-system         kube-controller-manager-c2master           0/1     Pending             0             0s    <none>         c2master    <none>           <none>
kube-system         kube-proxy-682wt                           1/1     Running             0             68s   192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-hkcjz                           1/1     Running             0             67s   192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-proxy-m8nzh                           1/1     Running             0             68s   192.168.4.12   c2worker2   <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-r5hfc             0/1     Init:0/1            0             67s   <none>         c2worker1   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-9sg6v   0/1     ContainerCreating   0             66s   <none>         c2worker1   <none>           <none>
study               web-6c79984869-hjwxl                       0/1     ContainerCreating   0             66s   <none>         c2worker2   <none>           <none>
tigera-operator     tigera-operator-747864d56d-9gm6v           1/1     Running             0             66s   192.168.4.10   c2master    <none>           <none>
traefik             traefik-66bfd6b9b4-pgc2b                   0/1     ContainerCreating   0             65s   <none>         c2worker2   <none>           <none>
```



```bash
kubectl -n calico-system logs calico-typha-589dbfbbd5-87z57  --previous

2026-10-17 06:45:02.454 [INFO][1] typha/daemon.go 256: Using Kubernetes API datastore, checking if we need to migrate v1 -> v3
2026-10-17 06:45:32.458 [ERROR][1] typha/daemon.go 282: Failed to determine migration requirements error=unable to query ClusterInformation to determine Calico version: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
2026-10-17 06:46:03.490 [ERROR][1] typha/daemon.go 282: Failed to determine migration requirements error=unable to query ClusterInformation to determine Calico version: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
2026-10-17 06:46:34.520 [ERROR][1] typha/daemon.go 282: Failed to determine migration requirements error=unable to query ClusterInformation to determine Calico version: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
2026-10-17 06:47:05.523 [ERROR][1] typha/daemon.go 282: Failed to determine migration requirements error=unable to query ClusterInformation to determine Calico version: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
2026-10-17 06:47:36.538 [ERROR][1] typha/daemon.go 282: Failed to determine migration requirements error=unable to query ClusterInformation to determine Calico version: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout

```


```bash
kubectl -n gateway-study describe pod android-deploy-8597675569-ckggs

Events:
  Type     Reason                  Age    From               Message
  ----     ------                  ----   ----               -------
  Normal   Scheduled               9m53s  default-scheduler  Successfully assigned gateway-study/android-deploy-8597675569-ckggs to c2worker2
  Warning  FailedCreatePodSandBox  8m53s  kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "54ee01f6b1ab07f8df8e04edfea552fd94ac92ac4d6d41db694a5face086e0bc": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
  Warning  FailedCreatePodSandBox  7m39s  kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "0725e85e0e22a86c8ded8ed84ea003d0c1751d678bd2818a928468b64a7dd815": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
  Warning  FailedCreatePodSandBox  6m25s  kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "092bf75709727a63d9daf30fa8293962dedf4705b2978ae4e49c583ab757d465": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
  Warning  FailedCreatePodSandBox  5m13s  kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "903ae9cb937403afbf59030110001f2d0ffcba6e5d24828dd4ac106adf783c45": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
  Warning  FailedCreatePodSandBox  4m2s   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "f0642f1fdd7936fd217af5b966a8c721e7e7f5aed77b52df0ccb80ae7e57e42f": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
  Warning  FailedCreatePodSandBox  2m51s  kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "d8ea69ef875aaf2e94c1e4ed0e9e54d87efd83fc86bbb32ce559fe1707cdf2d6": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
  Warning  FailedCreatePodSandBox  99s    kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "9ba5c8fd31f44521e370bdd39cfcda4df05118ac8828a5c5236214539e9e0447": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
  Warning  FailedCreatePodSandBox  26s    kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "7b3d7e81d3d686a4a75c7ed86137d82b00bd53758db602ea9fccbff98f473f28": plugin type="calico" failed (add): error getting ClusterInformation: Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
```


```bash
$ kubectl get svc kubernetes -o wide
kubectl get endpoints kubernetes -o wide
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE   SELECTOR
kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   15d   <none>
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME         ENDPOINTS           AGE
kubernetes   192.168.4.10:6443   15d
```


```bash
curl -k --connect-timeout 3   https://192.168.4.10:6443/readyz
ok


curl -k --connect-timeout 3   https://10.96.0.1:443/readyz
curl: (28) Connection timed out after 3002 milliseconds



```

checking kube-proxy 



```bash
 kubectl -n kube-system describe pod kube-proxy-682wt
Name:                 kube-proxy-682wt
Namespace:            kube-system
Priority:             2000001000
Priority Class Name:  system-node-critical
Service Account:      kube-proxy
Node:                 c2master/192.168.4.10
Start Time:           Sat, 17 Oct 2026 07:42:06 +0100
Labels:               controller-revision-hash=84977d7f4c
                      k8s-app=kube-proxy
                      pod-template-generation=2
Annotations:          <none>
Status:               Running
IP:                   192.168.4.10
IPs:
  IP:           192.168.4.10
Controlled By:  DaemonSet/kube-proxy
Containers:
  kube-proxy:
    Container ID:  containerd://b280eb7a1ac940147d2726cae14dbd2dea0f2f67fc7e130b13d85156de76488a
    Image:         registry.k8s.io/kube-proxy:v1.33.13
    Image ID:      registry.k8s.io/kube-proxy@sha256:dc4788df776179d96e5a106ad64cf6aa1086108a0323950d68a27f9bfaca9bce
    Port:          <none>
    Host Port:     <none>
    Command:
      /usr/local/bin/kube-proxy
      --config=/var/lib/kube-proxy/config.conf 
      --hostname-override=$(NODE_NAME)
    State:          Running
      Started:      Sat, 17 Oct 2026 07:42:08 +0100
    Ready:          True
    Restart Count:  0
```

The file config.conf is a ConfigMap. Let's check it out



```bash
$ kubectl -n kube-system get cm kube-proxy -o yaml
apiVersion: v1
data:
  config.conf: |-
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    bindAddress: 0.0.0.0
    bindAddressHardFail: false
(...)
  kubeconfig.conf: |-
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        server: https://192.168.3.20:6443 <<<-------------------------------------------------
      name: default
    contexts:
    - context:
        cluster: default
        namespace: default
        user: default
      name: default
    current-context: default
    users:
    - name: default
      user:
        tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
kind: ConfigMap
metadata:
  annotations:
    kubeadm.kubernetes.io/component-config.hash: sha256:dff32e573134354170d654b41780b497cd8cc347f8e688a805237431f07cd0e1
  creationTimestamp: "2026-10-01T17:58:26Z"
  labels:
    app: kube-proxy
  name: kube-proxy
  namespace: kube-system
  resourceVersion: "307"
  uid: c0f1def5-064c-4ba2-a275-fd71f465f319
```


I could see the old control-plane IP address in the configuration, so I replaced it with the new IP. Deleted the existing kube-proxy pods.



```bash
 kubectl -n kube-system delete pod kube-proxy-682wt kube-proxy-hkcjz kube-proxy-m8nzh --grace-period=0 --force
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
pod "kube-proxy-682wt" force deleted
pod "kube-proxy-hkcjz" force deleted
pod "kube-proxy-m8nzh" force deleted
```

```bash
kubectl get pods -A --no-headers |
  while read -r namespace name _; do
  kubectl delete pod "$name" -n "$namespace" --grace-period=0 --force                                                                                                                                               done
```


After making this change and recreating the affected Pods:

```bash
kubectl get pods -A -o wide
NAMESPACE           NAME                                       READY   STATUS            RESTARTS       AGE   IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-qnsz6   0/1     Running           0              46s   10.2.81.104    c2master    <none>           <none>
calico-system       calico-node-9wwvv                          1/1     Running           0              45s   192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-sbrlw                          1/1     Running           0              45s   192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-node-zczcq                          0/1     Running           0              44s   192.168.4.10   c2master    <none>           <none>
calico-system       calico-typha-589dbfbbd5-gcbqk              1/1     Running           0              43s   192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-typha-589dbfbbd5-wjdkw              1/1     Running           0              43s   192.168.4.11   c2worker1   <none>           <none>
calico-system       csi-node-driver-d7t8t                      2/2     Running           0              42s   10.2.231.46    c2worker1   <none>           <none>
calico-system       csi-node-driver-fbt7h                      2/2     Running           0              41s   10.2.230.35    c2worker2   <none>           <none>
calico-system       csi-node-driver-rlpb8                      2/2     Running           0              41s   10.2.81.103    c2master    <none>           <none>
gateway-study       android-deploy-8597675569-bvh6g            1/1     Running           0              39s   10.2.231.36    c2worker1   <none>           <none>
gateway-study       android-deploy-8597675569-qd6gx            1/1     Running           0              40s   10.2.230.14    c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-47rc8            1/1     Running           0              38s   10.2.231.37    c2worker1   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-jqcgc            1/1     Running           0              38s   10.2.230.13    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-859kx              1/1     Running           0              37s   10.2.230.21    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-t46j6              1/1     Running           0              37s   10.2.231.35    c2worker1   <none>           <none>
kube-system         coredns-674b8bbfcf-k4lwh                   1/1     Running           0              36s   10.2.230.16    c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-p592n                   1/1     Running           0              35s   10.2.231.41    c2worker1   <none>           <none>
kube-system         kube-proxy-2v6wd                           1/1     Running           0              33s   192.168.4.12   c2worker2   <none>           <none>
kube-system         kube-proxy-rtm6d                           1/1     Running           0              32s   192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-proxy-zpm46                           1/1     Running           0              32s   192.168.4.10   c2master    <none>           <none>
kube-system         kube-scheduler-c2master                    1/1     Running           13 (80m ago)   31s   192.168.4.10   c2master    <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-47qtn             0/1     PodInitializing   0              31s   10.2.231.38    c2worker1   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-lpk4v   1/1     Running           0              30s   10.2.231.39    c2worker1   <none>           <none>
study               web-6c79984869-brlxz                       1/1     Running           0              29s   10.2.231.31    c2worker1   <none>           <none>
tigera-operator     tigera-operator-747864d56d-s8lvm           1/1     Running           0              29s   192.168.4.10   c2master    <none>           <none>
traefik             traefik-66bfd6b9b4-847gf                   1/1     Running           0              28s   10.2.230.30    c2worker2   <none>           <none>
```

Some Pods still showed restart counts, so I continued monitoring them.


```bash
 kubectl get pods -A -o wide
NAMESPACE           NAME                                       READY   STATUS    RESTARTS       AGE    IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-qnsz6   1/1     Running   0              117s   10.2.81.104    c2master    <none>           <none>
calico-system       calico-node-9wwvv                          1/1     Running   0              116s   192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-sbrlw                          1/1     Running   0              116s   192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-node-zczcq                          1/1     Running   0              115s   192.168.4.10   c2master    <none>           <none>
calico-system       calico-typha-589dbfbbd5-gcbqk              1/1     Running   0              114s   192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-typha-589dbfbbd5-wjdkw              1/1     Running   0              114s   192.168.4.11   c2worker1   <none>           <none>
calico-system       csi-node-driver-d7t8t                      2/2     Running   0              113s   10.2.231.46    c2worker1   <none>           <none>
calico-system       csi-node-driver-fbt7h                      2/2     Running   0              112s   10.2.230.35    c2worker2   <none>           <none>
calico-system       csi-node-driver-rlpb8                      2/2     Running   0              112s   10.2.81.103    c2master    <none>           <none>
gateway-study       android-deploy-8597675569-bvh6g            1/1     Running   0              110s   10.2.231.36    c2worker1   <none>           <none>
gateway-study       android-deploy-8597675569-qd6gx            1/1     Running   0              111s   10.2.230.14    c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-47rc8            1/1     Running   0              109s   10.2.231.37    c2worker1   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-jqcgc            1/1     Running   0              109s   10.2.230.13    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-859kx              1/1     Running   0              108s   10.2.230.21    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-t46j6              1/1     Running   0              108s   10.2.231.35    c2worker1   <none>           <none>
kube-system         coredns-674b8bbfcf-k4lwh                   1/1     Running   0              107s   10.2.230.16    c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-p592n                   1/1     Running   0              106s   10.2.231.41    c2worker1   <none>           <none>
kube-system         etcd-c2master                              1/1     Running   2 (82m ago)    30s    192.168.4.10   c2master    <none>           <none>
kube-system         kube-apiserver-c2master                    1/1     Running   3 (82m ago)    17s    192.168.4.10   c2master    <none>           <none>
kube-system         kube-controller-manager-c2master           1/1     Running   13 (82m ago)   39s    192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-2v6wd                           1/1     Running   0              104s   192.168.4.12   c2worker2   <none>           <none>
kube-system         kube-proxy-rtm6d                           1/1     Running   0              103s   192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-proxy-zpm46                           1/1     Running   0              103s   192.168.4.10   c2master    <none>           <none>
kube-system         kube-scheduler-c2master                    1/1     Running   13 (82m ago)   102s   192.168.4.10   c2master    <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-47qtn             1/1     Running   0              102s   10.2.231.38    c2worker1   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-lpk4v   1/1     Running   0              101s   10.2.231.39    c2worker1   <none>           <none>
study               web-6c79984869-brlxz                       1/1     Running   0              100s   10.2.231.31    c2worker1   <none>           <none>
tigera-operator     tigera-operator-747864d56d-s8lvm           1/1     Running   0              100s   192.168.4.10   c2master    <none>           <none>
traefik             traefik-66bfd6b9b4-847gf                   1/1     Running   0              99s    10.2.230.30    c2worker2   <none>           <none>
```

The increase in restart counts compared with the previous output was due to a cluster reboot.



```bash
$ kubectl get pods -A -o wide
NAMESPACE           NAME                                       READY   STATUS    RESTARTS       AGE    IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-qnsz6   1/1     Running   1 (14m ago)    115m   10.2.81.105    c2master    <none>           <none>
calico-system       calico-node-9wwvv                          1/1     Running   1 (14m ago)    115m   192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-sbrlw                          1/1     Running   1 (14m ago)    115m   192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-node-zczcq                          1/1     Running   1 (14m ago)    115m   192.168.4.10   c2master    <none>           <none>
calico-system       calico-typha-589dbfbbd5-gcbqk              1/1     Running   1 (14m ago)    115m   192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-typha-589dbfbbd5-wjdkw              1/1     Running   1 (14m ago)    115m   192.168.4.11   c2worker1   <none>           <none>
calico-system       csi-node-driver-d7t8t                      2/2     Running   2 (14m ago)    115m   10.2.231.42    c2worker1   <none>           <none>
calico-system       csi-node-driver-fbt7h                      2/2     Running   2 (14m ago)    115m   10.2.230.32    c2worker2   <none>           <none>
calico-system       csi-node-driver-rlpb8                      2/2     Running   2 (14m ago)    115m   10.2.81.106    c2master    <none>           <none>
gateway-study       android-deploy-8597675569-bvh6g            1/1     Running   1 (14m ago)    115m   10.2.231.50    c2worker1   <none>           <none>
gateway-study       android-deploy-8597675569-qd6gx            1/1     Running   1 (14m ago)    115m   10.2.230.37    c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-47rc8            1/1     Running   1 (14m ago)    115m   10.2.231.52    c2worker1   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-jqcgc            1/1     Running   1 (14m ago)    115m   10.2.230.33    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-859kx              1/1     Running   1 (14m ago)    115m   10.2.230.34    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-t46j6              1/1     Running   1 (14m ago)    115m   10.2.231.45    c2worker1   <none>           <none>
kube-system         coredns-674b8bbfcf-k4lwh                   1/1     Running   1 (14m ago)    115m   10.2.230.29    c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-p592n                   1/1     Running   1 (14m ago)    115m   10.2.231.47    c2worker1   <none>           <none>
kube-system         etcd-c2master                              1/1     Running   3 (14m ago)    113m   192.168.4.10   c2master    <none>           <none>
kube-system         kube-apiserver-c2master                    1/1     Running   4 (14m ago)    113m   192.168.4.10   c2master    <none>           <none>
kube-system         kube-controller-manager-c2master           1/1     Running   14 (14m ago)   114m   192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-2v6wd                           1/1     Running   1 (14m ago)    115m   192.168.4.12   c2worker2   <none>           <none>
kube-system         kube-proxy-rtm6d                           1/1     Running   1 (14m ago)    115m   192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-proxy-zpm46                           1/1     Running   1 (14m ago)    115m   192.168.4.10   c2master    <none>           <none>
kube-system         kube-scheduler-c2master                    1/1     Running   14 (14m ago)   115m   192.168.4.10   c2master    <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-47qtn             1/1     Running   1 (14m ago)    115m   10.2.231.51    c2worker1   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-lpk4v   1/1     Running   1 (14m ago)    115m   10.2.231.43    c2worker1   <none>           <none>
study               web-6c79984869-brlxz                       1/1     Running   1 (14m ago)    115m   10.2.231.48    c2worker1   <none>           <none>
tigera-operator     tigera-operator-747864d56d-s8lvm           1/1     Running   1 (14m ago)    115m   192.168.4.10   c2master    <none>           <none>
traefik             traefik-66bfd6b9b4-847gf                   1/1     Running   1 (14m ago)    115m   10.2.230.31    c2worker2   <none>           <none>
```


To make it easier to identify differences and assess stability, I created a script that compares the output of `kubectl get pods -A` between executions and displays any changes.

```bash

#!/bin/bash

previous=$(kubectl get pods -A -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount,IP:.status.podIP,NODE:.spec.nodeName')

while true; do
    sleep 60

    current==$(kubectl get pods -A -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount,IP:.status.podIP,NODE:.spec.nodeName')

    changes=$(diff <(echo "$previous") <(echo "$current"))

    if [[ -n "$changes" ]]; then
        echo "=== $(date) ==="
        echo "$changes"
    else
        echo "=== $(date) ==="
        echo "No changes"
    fi

    previous="$current"
done

```
After a few minutes, no changes were observed, indicating that no Pods had restarted during the monitoring period.


```bash
$ ./check_pods_differences.sh
 === Sat Oct 17 10:49:52 WEST 2026 ===
No changes
=== Sat Oct 17 10:50:52 WEST 2026 ===
No changes
=== Sat Oct 17 10:51:53 WEST 2026 ===
No changes
=== Sat Oct 17 10:52:53 WEST 2026 ===
No changes
=== Sat Oct 17 10:53:54 WEST 2026 ===
No changes
=== Sat Oct 17 10:54:54 WEST 2026 ===
No changes
=== Sat Oct 17 10:55:54 WEST 2026 ===
No changes
=== Sat Oct 17 10:56:55 WEST 2026 ===
No changes
=== Sat Oct 17 10:57:56 WEST 2026 ===
No changes
=== Sat Oct 17 10:58:56 WEST 2026 ===
No changes
=== Sat Oct 17 10:59:56 WEST 2026 ===
No changes
=== Sat Oct 17 11:00:57 WEST 2026 ===
No changes
=== Sat Oct 17 11:01:57 WEST 2026 ===
No changes
=== Sat Oct 17 11:02:58 WEST 2026 ===
No changes
=== Sat Oct 17 11:03:58 WEST 2026 ===
No changes
=== Sat Oct 17 11:04:59 WEST 2026 ===
No changes
=== Sat Oct 17 11:05:59 WEST 2026 ===
No changes
=== Sat Oct 17 11:06:59 WEST 2026 ===
No changes

```

The final test was to create a Deployment with enough replicas to verify that both worker nodes would be used.

```bash

 kubectl create ns test
namespace/test created

```


```bash
$ kubectl -n test create deploy test-dp --image=nginx --replicas=10
deployment.apps/test-dp created
```


```bash
$ watch -n 10  kubectl get pods -A -o wide

Every 10.0s: kubectl get pods -A -o wide 

NAMESPACE           NAME                                       READY   STATUS    RESTARTS       AGE     IP             NODE        NOMINATED NODE   READINESS GATES
calico-system       calico-kube-controllers-76fc5b9999-qnsz6   1/1     Running   1 (69m ago)    170m    10.2.81.105    c2master    <none>           <none>
calico-system       calico-node-9wwvv                          1/1     Running   1 (69m ago)    170m    192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-node-sbrlw                          1/1     Running   1 (69m ago)    170m    192.168.4.11   c2worker1   <none>           <none>
calico-system       calico-node-zczcq                          1/1     Running   1 (69m ago)    170m    192.168.4.10   c2master    <none>           <none>
calico-system       calico-typha-589dbfbbd5-gcbqk              1/1     Running   1 (69m ago)    170m    192.168.4.12   c2worker2   <none>           <none>
calico-system       calico-typha-589dbfbbd5-wjdkw              1/1     Running   1 (69m ago)    170m    192.168.4.11   c2worker1   <none>           <none>
calico-system       csi-node-driver-d7t8t                      2/2     Running   2 (69m ago)    170m    10.2.231.42    c2worker1   <none>           <none>
calico-system       csi-node-driver-fbt7h                      2/2     Running   2 (69m ago)    170m    10.2.230.32    c2worker2   <none>           <none>
calico-system       csi-node-driver-rlpb8                      2/2     Running   2 (69m ago)    170m    10.2.81.106    c2master    <none>           <none>
gateway-study       android-deploy-8597675569-bvh6g            1/1     Running   1 (69m ago)    170m    10.2.231.50    c2worker1   <none>           <none>
gateway-study       android-deploy-8597675569-qd6gx            1/1     Running   1 (69m ago)    170m    10.2.230.37    c2worker2   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-47rc8            1/1     Running   1 (69m ago)    170m    10.2.231.52    c2worker1   <none>           <none>
gateway-study       desktop-deploy-698bcccbd4-jqcgc            1/1     Running   1 (69m ago)    170m    10.2.230.33    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-859kx              1/1     Running   1 (69m ago)    170m    10.2.230.34    c2worker2   <none>           <none>
gateway-study       iphone-deploy-bf5dfbccf-t46j6              1/1     Running   1 (69m ago)    170m    10.2.231.45    c2worker1   <none>           <none>
kube-system         coredns-674b8bbfcf-k4lwh                   1/1     Running   1 (69m ago)    170m    10.2.230.29    c2worker2   <none>           <none>
kube-system         coredns-674b8bbfcf-p592n                   1/1     Running   1 (69m ago)    170m    10.2.231.47    c2worker1   <none>           <none>
kube-system         etcd-c2master                              1/1     Running   3 (69m ago)    169m    192.168.4.10   c2master    <none>           <none>
kube-system         kube-apiserver-c2master                    1/1     Running   4 (69m ago)    169m    192.168.4.10   c2master    <none>           <none>
kube-system         kube-controller-manager-c2master           1/1     Running   14 (69m ago)   169m    192.168.4.10   c2master    <none>           <none>
kube-system         kube-proxy-2v6wd                           1/1     Running   1 (69m ago)    170m    192.168.4.12   c2worker2   <none>           <none>
kube-system         kube-proxy-rtm6d                           1/1     Running   1 (69m ago)    170m    192.168.4.11   c2worker1   <none>           <none>
kube-system         kube-proxy-zpm46                           1/1     Running   1 (69m ago)    170m    192.168.4.10   c2master    <none>           <none>
kube-system         kube-scheduler-c2master                    1/1     Running   14 (69m ago)   170m    192.168.4.10   c2master    <none>           <none>
ngf-gatewayapi-ns   gateway-nginx-6b74fd656c-47qtn             1/1     Running   1 (69m ago)    170m    10.2.231.51    c2worker1   <none>           <none>
ngf-gatewayapi-ns   ngf-nginx-gateway-fabric-fd7c5fff4-lpk4v   1/1     Running   1 (69m ago)    170m    10.2.231.43    c2worker1   <none>           <none>
study               web-6c79984869-brlxz                       1/1     Running   1 (69m ago)    170m    10.2.231.48    c2worker1   <none>           <none>
test                test-dp-8467467c4-48tmv                    1/1     Running   0              3m13s   10.2.230.41    c2worker2   <none>           <none>
test                test-dp-8467467c4-6kvjg                    1/1     Running   0              3m13s   10.2.230.40    c2worker2   <none>           <none>
test                test-dp-8467467c4-989rr                    1/1     Running   0              3m13s   10.2.230.28    c2worker2   <none>           <none>
test                test-dp-8467467c4-9wlmg                    1/1     Running   0              3m13s   10.2.231.53    c2worker1   <none>           <none>
test                test-dp-8467467c4-f78dp                    1/1     Running   0              3m13s   10.2.231.44    c2worker1   <none>           <none>
test                test-dp-8467467c4-l9tnw                    1/1     Running   0              3m13s   10.2.230.36    c2worker2   <none>           <none>
test                test-dp-8467467c4-llzxk                    1/1     Running   0              3m13s   10.2.230.27    c2worker2   <none>           <none>
test                test-dp-8467467c4-qhjfm                    1/1     Running   0              3m13s   10.2.231.49    c2worker1   <none>           <none>
test                test-dp-8467467c4-ssq4d                    1/1     Running   0              3m13s   10.2.231.55    c2worker1   <none>           <none>
test                test-dp-8467467c4-t2ck9                    1/1     Running   0              3m13s   10.2.231.58    c2worker1   <none>           <none>
tigera-operator     tigera-operator-747864d56d-s8lvm           1/1     Running   1 (69m ago)    170m    192.168.4.10   c2master    <none>           <none>
traefik             traefik-66bfd6b9b4-847gf                   1/1     Running   1 (69m ago)    170m    10.2.230.31    c2worker2   <none>           <none>

```


Although cluster seems to be up and running another ConfigMap was changed: kubeadm-config

```bash
$ k -n kube-system get cm kubeadm-config -o yaml
apiVersion: v1
data:
  ClusterConfiguration: |
    apiServer: {}
    apiVersion: kubeadm.k8s.io/v1beta4
    caCertificateValidityPeriod: 87600h0m0s
    certificateValidityPeriod: 8760h0m0s
    certificatesDir: /etc/kubernetes/pki
    clusterName: kubernetes
    controlPlaneEndpoint: 192.168.3.20:6443  <<<<<-------------------
    controllerManager: {}
    dns: {}
    encryptionAlgorithm: RSA-2048
    etcd:
      local:
        dataDir: /var/lib/etcd
    imageRepository: registry.k8s.io
    kind: ClusterConfiguration
    kubernetesVersion: v1.33.13
    networking:
      dnsDomain: cluster.local
      podSubnet: 10.2.0.0/16
      serviceSubnet: 10.96.0.0/12
    proxy: {}
    scheduler: {}
kind: ConfigMap
metadata:
  creationTimestamp: "2026-10-01T17:58:24Z"
  name: kubeadm-config
  namespace: kube-system
  resourceVersion: "15953"
  uid: 3282f72a-6fdc-4ac2-b6af-61bebc71ce0d


```


After a few days, I decided to do an etcd backup and restore, in order to pratice the procedure.

The strategy is well documented online so no problems were expected. I deciedd to start to check the endpoint health with:

```bash
sudo etcdctl \
  --endpoints=https://192.168.4.10:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```


For my surprise I got an answer I did not expected at this stage:

```bash
{"level":"warn","ts":"2026-10-29T19:24:52.916894Z","logger":"client","caller":"v3/retry_interceptor.go:63","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0x40004032c0/192.168.4.10:2379","attempt":0,"error":"rpc error: code = DeadlineExceeded desc = latest balancer error: last connection error: connection error: desc = \"transport: authentication handshake failed: tls: failed to verify certificate: x509: certificate is valid for 192.168.3.20, 127.0.0.1, ::1, not 192.168.4.10\""}
https://192.168.4.10:2379 is unhealthy: failed to commit proposal: context deadline exceeded
Error: unhealthy cluster
```

but if I replaced the IP address with `localhost` then it worked

```bash
 sudo etcdctl   --endpoints=https://localhost:2379   --cacert=/etc/kubernetes/pki/etcd/ca.crt   --cert=/etc/kubernetes/pki/etcd/server.crt   --key=/etc/kubernetes/pki/etcd/server.key   endpoint health

https://localhost:2379 is healthy: successfully committed proposal: took = 36.896007ms
```

Looking back when I run `sudo kubeadm init phase certs` I only run it for api-server.

I should also have run, for etcd-server and etcd-healthcheck-client. Instead of simply executing the command to renew all certificates, I decided to execute the specific commands related to etcd

```bash
sudo kubeadm certs renew etcd-healthcheck-client
``` 

got

```bash

$ sudo kubeadm certs renew etcd-healthcheck-client
[renew] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[renew] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.

certificate for liveness probes to healthcheck etcd renewed
------------------------
$ sudo etcdctl   --endpoints=https://192.168.4.10:2379   --cacert=/etc/kubernetes/pki/etcd/ca.crt   --cert=/etc/kubernetes/pki/etcd/server.crt   --key=/etc/kubernetes/pki/etcd/server.key   endpoint health
{"level":"warn","ts":"2026-10-29T19:35:34.661211Z","logger":"client","caller":"v3/retry_interceptor.go:63","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0x40002272c0/192.168.4.10:2379","attempt":0,"error":"rpc error: code = DeadlineExceeded desc = latest balancer error: last connection error: connection error: desc = \"transport: authentication handshake failed: tls: failed to verify certificate: x509: certificate is valid for 192.168.3.20, 127.0.0.1, ::1, not 192.168.4.10\""}
https://192.168.4.10:2379 is unhealthy: failed to commit proposal: context deadline exceeded
Error: unhealthy cluster

```

So the problem did not disapear. Decided to inspect the mentioned ConfigMap

```bash
$ k -n kube-system get cm
NAME                                                   DATA   AGE
coredns                                                1      28d
extension-apiserver-authentication                     6      28d
kube-apiserver-legacy-service-account-token-tracking   1      28d
kube-proxy                                             2      28d
kube-root-ca.crt                                       1      28d
kubeadm-config                                         1      28d
kubelet-config                                         1      28d
------------------------
```

Checking for the old control-plane IP it was not found

```bash
k -n kube-system get cm -o yaml |grep 192.168.3
```

Inspecting the information of the certificate

```bash
sudo openssl x509 \
  -in /etc/kubernetes/pki/etcd/server.crt \
  -noout -subject -issuer -ext subjectAltName
```

it still references the IP address (`192.168.3.20` ) of the control-plane when it was on the other network.

```bash
subject=CN=c2master
issuer=CN=etcd-ca
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:localhost, IP Address:192.168.3.20, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1
```

So basically regeneration of certificates with the correct IP address is required. 


Once I did that

```bash
sudo rm /etc/kubernetes/pki/etcd/server.crt /etc/kubernetes/pki/etcd/server.key

sudo kubeadm certs renew etcd-server
sudo kubeadm certs renew etcd-healthcheck-client
```

I checked the certificate details and all good

```bash
$ sudo openssl x509   -in /etc/kubernetes/pki/etcd/server.crt   -noout -ext subjectAltName
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:localhost, IP Address:192.168.4.10, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1

```

and now etcd health check worked

```bash
 sudo etcdctl   --endpoints=https://192.168.4.10:2379   --cacert=/etc/kubernetes/pki/etcd/ca.crt   --cert=/etc/kubernetes/pki/etcd/server.crt   --key=/etc/kubernetes/pki/etcd/server.key   endpoint health
https://192.168.4.10:2379 is healthy: successfully committed proposal: took = 27.225193ms
```

So decided to check all certificates

```bash
for cert in \
  /etc/kubernetes/pki/etcd/server.crt \
  /etc/kubernetes/pki/etcd/peer.crt \
  /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  /etc/kubernetes/pki/apiserver-etcd-client.crt
do
  if [ -f "$cert" ]; then
    echo
    echo "===== $cert ====="
    openssl x509 -in "$cert" -noout \
      -subject -issuer -dates -ext subjectAltName
  fi
done
```



```bash
$ for cert in \
  /etc/kubernetes/pki/etcd/server.crt \
  /etc/kubernetes/pki/etcd/peer.crt \
  /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  /etc/kubernetes/pki/apiserver-etcd-client.crt
do
  if [ -f "$cert" ]; then
    echo
    echo "===== $cert ====="
    openssl x509 -in "$cert" -noout \
      -subject -issuer -dates -ext subjectAltName
  fi
done

===== /etc/kubernetes/pki/etcd/server.crt =====
subject=CN=c2master
issuer=CN=etcd-ca
notBefore=Oct 29 19:52:18 2026 GMT
notAfter=Oct 29 19:57:18 2027 GMT
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:localhost, IP Address:192.168.4.10, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1

===== /etc/kubernetes/pki/etcd/peer.crt =====
subject=CN=c2master
issuer=CN=etcd-ca
notBefore=Oct 29 19:37:29 2026 GMT
notAfter=Oct 29 19:42:29 2027 GMT
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:localhost, IP Address:192.168.3.20, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1  <<<-------------------

===== /etc/kubernetes/pki/etcd/healthcheck-client.crt =====
subject=CN=kube-etcd-healthcheck-client
issuer=CN=etcd-ca
notBefore=Oct 29 19:30:20 2026 GMT
notAfter=Oct 29 19:35:20 2027 GMT
No extensions in certificate

===== /etc/kubernetes/pki/apiserver-etcd-client.crt =====
subject=CN=kube-apiserver-etcd-client
issuer=CN=etcd-ca
notBefore=Oct 29 19:38:53 2026 GMT
notAfter=Oct 29 19:43:53 2027 GMT
No extensions in certificate
```

So /etc/kubernetes/pki/etcd/peer.crt  also needs update. Deleted old peer.crt and peer.key and executed

```bash
sudo rm /etc/kubernetes/pki/etcd/peer.crt /etc/kubernetes/pki/etcd/peer.key
sudo kubeadm certs renew etcd-peer 
```
Now all etcd related certs are correct

```bash
$ for cert in \
  /etc/kubernetes/pki/etcd/server.crt \
  /etc/kubernetes/pki/etcd/peer.crt \
  /etc/kubernetes/pki/etcd/healthcheck-client.crt \
  /etc/kubernetes/pki/apiserver-etcd-client.crt
do
  if [ -f "$cert" ]; then
    echo
    echo "===== $cert ====="
    openssl x509 -in "$cert" -noout \
      -subject -issuer -dates -ext subjectAltName
  fi
done

===== /etc/kubernetes/pki/etcd/server.crt =====
subject=CN=c2master
issuer=CN=etcd-ca
notBefore=Oct 29 19:52:18 2026 GMT
notAfter=Oct 29 19:57:18 2027 GMT
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:localhost, IP Address:192.168.4.10, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1

===== /etc/kubernetes/pki/etcd/peer.crt =====
subject=CN=c2master
issuer=CN=etcd-ca
notBefore=Oct 29 19:37:29 2026 GMT
notAfter=Oct 29 19:42:29 2027 GMT
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:localhost, IP Address:192.168.4.10, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1

===== /etc/kubernetes/pki/etcd/healthcheck-client.crt =====
subject=CN=kube-etcd-healthcheck-client
issuer=CN=etcd-ca
notBefore=Oct 29 19:30:20 2026 GMT
notAfter=Oct 29 19:35:20 2027 GMT
No extensions in certificate

===== /etc/kubernetes/pki/apiserver-etcd-client.crt =====
subject=CN=kube-apiserver-etcd-client
issuer=CN=etcd-ca
notBefore=Oct 29 19:38:53 2026 GMT
notAfter=Oct 29 19:43:53 2027 GMT
No extensions in certificate
```

Rechecking all other certificates all seem ok as well.

```bash

===== /etc/kubernetes/pki/apiserver-etcd-client.crt =====
subject=CN=kube-apiserver-etcd-client
issuer=CN=etcd-ca
notBefore=Oct 29 19:38:53 2026 GMT
notAfter=Oct 29 19:43:53 2027 GMT
No extensions in certificate

===== /etc/kubernetes/pki/apiserver-kubelet-client.crt =====
subject=O=kubeadm:cluster-admins, CN=kube-apiserver-kubelet-client
issuer=CN=kubernetes
notBefore=Oct 16 20:27:28 2026 GMT
notAfter=Oct 16 20:32:28 2027 GMT
No extensions in certificate

===== /etc/kubernetes/pki/apiserver.crt =====
subject=CN=kube-apiserver
issuer=CN=kubernetes
notBefore=Oct 16 20:27:28 2026 GMT
notAfter=Oct 16 20:32:28 2027 GMT
X509v3 Subject Alternative Name:
    DNS:c2master, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, IP Address:10.96.0.1, IP Address:192.168.4.10

===== /etc/kubernetes/pki/ca.crt =====
subject=CN=kubernetes
issuer=CN=kubernetes
notBefore=Oct  1 17:52:07 2026 GMT
notAfter=Sep 28 17:57:07 2036 GMT
X509v3 Subject Alternative Name:
    DNS:kubernetes

===== /etc/kubernetes/pki/front-proxy-ca.crt =====
subject=CN=front-proxy-ca
issuer=CN=front-proxy-ca
notBefore=Oct  1 17:52:07 2026 GMT
notAfter=Sep 28 17:57:07 2036 GMT
X509v3 Subject Alternative Name:
    DNS:front-proxy-ca

===== /etc/kubernetes/pki/front-proxy-client.crt =====
subject=CN=front-proxy-client
issuer=CN=front-proxy-ca
notBefore=Oct 16 20:27:28 2026 GMT
notAfter=Oct 16 20:32:28 2027 GMT
No extensions in certificate
```
