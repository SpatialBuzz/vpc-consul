#!/bin/bash -u

# to install awscli
# pip install awscli

# to install jq
# http://stedolan.github.io/jq/download/

STACK_NAME='consul-test'
TEMPLATE='file:///data/docker/vpc-consul/template.json'

KEY_NAME='vpc-test'
KEY_PEM='vpc-test.pem'

AVAILABILITY_ZONES='a,b,c'
BASTIONINSTANCETYPE='m1.small'
CONSULINSTANCETYPE='m1.small'
NATINSTANCETYPE='m1.small'

#
# step 1 - install ansible
#
apt-get install -y python-dev
pip install ansible


#
# step 2 - create the stack
#

aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-body ${TEMPLATE} \
    --parameters "[ { \"ParameterKey\": \"KeyName\", \"ParameterValue\": \"${KEY_NAME}\" }, { \"ParameterKey\": \"AvailabilityZones\", \"ParameterValue\": \"${AVAILABILITY_ZONES}\" }, { \"ParameterKey\": \"BastionInstanceType\", \"ParameterValue\": \"${BASTIONINSTANCETYPE}\" }, { \"ParameterKey\": \"ConsulInstanceType\", \"ParameterValue\": \"${CONSULINSTANCETYPE}\" }, { \"ParameterKey\": \"NATInstanceType\", \"ParameterValue\": \"${NATINSTANCETYPE}\" } ]"

result="Unknown"

while [[ "${result}" != "CREATE_COMPLETE" ]]; do
    echo "Stack status: ${result}"
    sleep 2
    result=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} | jq ".Stacks[].StackStatus" --raw-output)
done

echo "Stack status: ${result}"

#
# step 3 - provision the bastion
#

BASTION_HOST_IP=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} | jq ".Stacks[].Outputs[].OutputValue" --raw-output)
echo "Bastion host IP: ${BASTION_HOST_IP}"
echo "export BASTION_HOST_IP=${BASTION_HOST_IP}"
export BASTION_HOST_IP=${BASTION_HOST_IP}

eval $(ssh-agent -s)
ssh-add ${KEY_PEM}
ansible-playbook -i hosts provision_bastion.yaml

#
# step 4 - provision consul serveres
#

ssh ubuntu@${BASTION_HOST_IP} -A "export ANSIBLE_HOST_KEY_CHECKING=False ; ansible-playbook -i hosts provision_consul.yaml"

#
# step 5 - verify the cluster
#

ssh -A -t ubuntu@${BASTION_HOST_IP} ssh -A ubuntu@10.0.16.4 "consul members"#

#
# step 6 - verify DNS lookups
#

ssh -A -t ubuntu@${BASTION_HOST_IP} ssh -A ubuntu@10.0.16.4 "dig consul-server-10-0-32-4.node.consul"
