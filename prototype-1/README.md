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
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get pods -A

# Make join command for instances
HOST_IP=$public_ip make join-command
```

You can now copy it to your local machine to use! We will next deploy workers.

### Workers

TODO customize worker name in environment also launch template. We also need the public ip address as a hostname.
Also this will only be ssh'able from where you deploy it!

# control plane
ssh -i ~/.ssh/dinosaur-llnl-flux.pem -o IdentitiesOnly=yes ubuntu@ec2-18-234-56-43.compute-1.amazonaws.com

# worker
ssh -i ~/.ssh/dinosaur-llnl-flux.pem -o IdentitiesOnly=yes ubuntu@ec2-54-234-10-30.compute-1.amazonaws.com


ec2-18-234-56-43.compute-1.amazonaws.com 

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

# Combine the make up and join command
echo "cat <<EOF > /home/ubuntu/usernetes/join-command" >> start-script.sh
cat start-script.sh ../../../join-command > start-script.sh
echo "EOF" >> start-script.sh
echo "make up && sleep 5 && make kubeadm-join" >> ./start-script.sh
```


