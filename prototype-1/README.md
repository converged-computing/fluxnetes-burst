# Prototype 1: EC2 Control Plane to EC2 Workers

This is a prototype to test:

1. Bringing up Flux with a Usernetes control plane.
 - This mirrors a job running on HPC (although here we will deploy to AWS)
 - We will expose the control plane with an IP address 
 - Generate join key for it
2. Automated deployment of usernetes from that instance (just worker nodes), that writes join command directly into startup script (double check this is secure).
3. Then we will have kubectl get nodes working, and theoretically from inside a flux job. 

A basic setup we get working like this could work from on premises, and the main difference would be having the control plane running under a job. If that isn't possible (to join a cluster node) we would have the job do similar to deploy a single EC2 control plane with, for example, Sage Maker, and have that job reach back to request more resources.

## Usage

Bring up the Flux cluster (that will provide the usernetes control plane) with Terraform. You will need AWS credentials, along with specifying a pem key name in the main.tf. If you haven't built your images, do so with packer in [build](control-plane/build) first. The AMI also needs to go into the main.tf

```bash
# This will bring up one node with a public ip address
cd control-plane
make
```

Next, get the address of your instance to ssh into. You'll need to use the key you provided in the main.tf.

```bash
region="us-east-1"
for instance in $(aws ec2 describe-instances --region ${region} --filters Name=instance-state-name,Values=running | jq .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].Association.PublicDnsName); do
   instance=$(echo "$instance" | tr -d '"')
   echo "ssh -i ~/.ssh/dinosaur-llnl-flux.pem -o IdentitiesOnly=yes ubuntu@${instance}"
done
```

Use the command printed out above to ssh in. Then update usernetes

```bash
# At time of testing, commit b259da818f84fe33fe9ea32c71c9ea7317d467cc Monday Feb 10 2025
cd usernetes
git pull origin master
```

To use the kubeconfig from somewhere else (e.g., a local machine) you need the instance public ip address:

```bash
public_ip=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
```

Bring up the usernetes control plane using this address. Note that the sleeps are because when you do them too quickly, you can hit errors.

```bash
# Pull containers, bring up kubelet
HOST_IP=$public_ip make up
sleep 5

# run kubeadm init
HOST_IP=$public_ip make kubeadm-init
sleep 5

# Install flannel!
HOST_IP=$public_ip make install-flannel
sleep 5

# Create the kubeconfig with the public address
# Enable kubectl (and make publicly accessible)
HOST_IP=$public_ip make kubeconfig
sed "s#https://127.0.0.1:6443#https://$public_ip:6443#g" kubeconfig > kubeconfig.yaml

# This is important so your kubectl knows what kubeconfig to use.
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get pods -A

# Make join command for instances
HOST_IP=$public_ip make join-command
```

You can now copy it to your local machine to use! We will next deploy workers.

### Workers

We need Terraform! This is for arm (hpc7g).

```bash
wget https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_arm64.zip
unzip terraform_1.10.5_linux_arm64.zip 
chmod +x ./terraform
sudo mv terraform /usr/local/bin
```

You will also need `~/.aws/credentials`, e.g.,

```bash
[default]
aws_access_key_id = xxxxxxxxxxxxxx
aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Right now we will use a full usernetes setup, and eventually we can build an AMI just with usernetes.

```bash
git clone https://github.com/converged-computing/fluxnetes-burst
cd fluxnetes-burst/prototype-1/workers
```

This will use the start-script.sh as a template to generate startup.sh, which
is the base plus the join command.

```bash
echo "cat <<EOF > /home/ubuntu/usernetes/join-command" >> start-script.sh
cat start-script.sh ../../../join-command > startup.sh
echo "EOF" >> startup.sh
echo "make up && sleep 5 && make kubeadm-join" >> ./startup.sh
```

Then bring up the workers! Note you can customize terraform variables in the environment. E.g.,

```bash
export TF_VAR_name=workers
make
```

And then you can see the worker joins by himself! Hooray!

```bash
$ kubectl  get nodes
```
```console
NAME                      STATUS     ROLES           AGE     VERSION
u7s-i-004cae8d99336b2ac   Ready      control-plane   3h48m   v1.32.1
u7s-i-0b2c9fce342fca957   Ready      <none>          9s      v1.32.1
```
```bash
$ kubectl  get pods -A
```
```console
NAMESPACE      NAME                                              READY   STATUS    RESTARTS        AGE
kube-flannel   kube-flannel-ds-59xpz                             1/1     Running   0               3h48m
kube-flannel   kube-flannel-ds-jwmns                             1/1     Running   0               13s
kube-system    coredns-668d6bf9bc-tgfhn                          1/1     Running   0               3h48m
kube-system    coredns-668d6bf9bc-wctnd                          1/1     Running   0               3h48m
kube-system    etcd-u7s-i-004cae8d99336b2ac                      1/1     Running   0               3h48m
kube-system    kube-apiserver-u7s-i-004cae8d99336b2ac            1/1     Running   0               3h48m
kube-system    kube-controller-manager-u7s-i-004cae8d99336b2ac   1/1     Running   0               3h48m
kube-system    kube-proxy-2sc2q                                  1/1     Running   0               14s
kube-system    kube-proxy-l4gxx                                  1/1     Running   0               3h48m
kube-system    kube-proxy-tw2ll                                  1/1     Running   0               3h43m
kube-system    kube-scheduler-u7s-i-004cae8d99336b2ac            1/1     Running   0               3h48m
```

Finally, you'll want to run `make sync-external-ip`

```bash
make sync-external-ip
```
```console
docker compose exec -e HOST_IP=10.0.2.89 -e NODE_NAME=u7s-i-004cae8d99336b2ac -e NODE_SUBNET=10.100.251.0/24 -e NODE_IP=10.100.251.100 -e PORT_KUBE_APISERVER=6443 -e PORT_FLANNEL=8472 -e PORT_KUBELET=10250 -e PORT_ETCD=2379 node /usernetes/Makefile.d/sync-external-ip.sh
node/u7s-i-004cae8d99336b2ac patched (no change)
node/u7s-i-004cae8d99336b2ac annotated
node/u7s-i-0b2c9fce342fca957 patched
node/u7s-i-0b2c9fce342fca957 annotated
node/u7s-i-0b2c9fce342fca957 untainted
node/u7s-i-0fba007f256d20de2 patched (no change)
node/u7s-i-0fba007f256d20de2 annotated
```

We will want to figure out how to best put these commands together to orchestrate the entire thing. The design really depends on the environment, which I'm not sure about yet.
