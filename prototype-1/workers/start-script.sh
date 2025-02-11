#!/bin/bash

# Install AWS client
python3 -m pip install awscli

# Wait for the count to be up
# We used to do this for flux (and it isn't required) but I'm keeping so they come up at the same time.
while [[ $(aws ec2 describe-instances --region ${region} --filters "Name=tag:selector,Values=${selector_name}-selector" | jq .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateDnsName | wc -l) -ne ${desired_size} ]]
do
   echo "Desired count not reached, sleeping."
   sleep 10
done
found_count=$(aws ec2 describe-instances --region ${region} --filters "Name=tag:selector,Values=${selector_name}-selector" | jq .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddress | wc -l)
echo "Desired count $found_count is reached"

# Update the flux config files with our hosts - we need the ones from hostname
hosts=$(aws ec2 describe-instances --region ${region} --filters "Name=tag:selector,Values=${selector_name}-selector" | jq -r .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateDnsName)

# Hack them together into comma separated list, also get the lead broker
NODELIST=""
lead_broker=""
for host in $hosts; do
   barehost=$(python3 -c "print('$host'.split('.')[0])")
   if [[ "$NODELIST" == "" ]]; then
      NODELIST=$barehost
      lead_broker=$barehost
   else
      NODELIST=$NODELIST,$barehost
   fi
done

host=$(hostname)
echo "The host is $host"

# These won't take from the build
echo "export LD_LIBRARY_PATH=/opt/amazon/efa/lib:\$LD_LIBRARY_PATH" >> /home/ubuntu/.bashrc
echo "export PATH=/opt/amazon/openmpi/bin:\$PATH" >> /home/ubuntu/.bashrc

# This will be appended to by the deploying script.
cd /home/ubuntu/usernetes
