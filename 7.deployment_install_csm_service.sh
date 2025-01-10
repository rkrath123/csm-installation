#!/bin/bash

# Function to check the status of the last executed command
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed. Exiting."
        exit 1
    else
        echo "Success: $1 completed."
    fi
}

# Step 1: Confirm all management nodes are deployed
echo "At this point, all the management nodes should be deployed successfully and joined in the cluster."
read -p "Press (yes/no): " user_response

if [[ "$user_response" == "yes" ]]; then
    echo "Proceeding with the script..."
else
    echo "You need to complete all the management nodes deployment before proceeding. Exiting."
    exit 1
fi

# Step 2: Run 'kubectl get nodes' on ncn-m002 and retrieve the first master hostname
echo "Running 'kubectl get nodes' on ncn-m002..."
FM=$(cat "${PITDATA}"/configs/data.json | jq -r '."Global"."meta-data"."first-master-hostname"')
check_command "Retrieve first master hostname"
echo "First master hostname: ${FM}"

# Step 3: Setup kubeconfig
echo "Setting up kubeconfig..."
mkdir -v ~/.kube
check_command "Create .kube directory"

scp "${FM}.nmn:/etc/kubernetes/admin.conf" ~/.kube/config
check_command "Copy admin.conf to .kube/config"

# Step 4: Change directory to prep
echo "Changing directory to ${PITDATA}/prep..."
cd "${PITDATA}/prep"
check_command "Change directory to prep"

# Step 5: Validate storage nodes
echo "Validating storage nodes..."
csi pit validate --ceph
check_command "Validate Ceph"

csi pit validate --k8s
check_command "Validate Kubernetes"

# Step 6: Install CSM services
echo "Starting installation of CSM services..."

# Install YAPL
echo "Installing YAPL..."
rpm -Uvh "${CSM_PATH}"/rpm/cray/csm/sle-15sp2/x86_64/yapl-*.x86_64.rpm
check_command "Install YAPL"

# Install CSM services using YAPL
echo "Installing CSM services using YAPL..."
pushd /usr/share/doc/csm/install/scripts/csm_services
check_command "Change directory to csm_services"
yapl -f install.yaml execute
check_command "Run YAPL to install CSM services"
popd

# Step 7: Wait for BSS deployment rollout
echo "Waiting for BSS deployment to roll out..."
kubectl -n services rollout status deployment cray-bss
check_command "Rollout status of BSS deployment"

# Step 8: Retrieve an API token
echo "Retrieving API token..."
export TOKEN=$(curl -k -s -S -d grant_type=client_credentials \
                  -d client_id=admin-client \
                  -d client_secret=`kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}' | base64 -d` \
                  https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token | jq -r '.access_token')
check_command "Retrieve API token"

# Step 9: Create empty boot parameters
echo "Creating empty boot parameters..."
curl -i -k -H "Authorization: Bearer ${TOKEN}" -X PUT \
    https://api-gw-service-nmn.local/apis/bss/boot/v1/bootparameters \
    --data '{"hosts":["Global"]}'
check_command "Create empty boot parameters"

# Step 10: Restart cray-spire-update-bss job
echo "Restarting cray-spire-update-bss job..."
SPIRE_JOB=$(kubectl -n spire get jobs -l app.kubernetes.io/name=cray-spire-update-bss -o name)

kubectl -n spire get "${SPIRE_JOB}" -o json | jq 'del(.spec.selector)' \
    | jq 'del(.spec.template.metadata.labels."controller-uid")' \
    | kubectl replace --force -f -
check_command "Restart cray-spire-update-bss job"

# Step 11: Wait for the cray-spire-update-bss job to complete
echo "Waiting for cray-spire-update-bss job to complete..."
kubectl -n spire wait "${SPIRE_JOB}" --for=condition=complete --timeout=5m
check_command "Wait for cray-spire-update-bss job to complete"

echo "
 Wait for everything to settle
Wait at least 15 minutes to let the various Kubernetes resources initialize and start before proceeding with the rest of the install. Because there are a number of dependencies between them, some services are not expected to work immediately after the install script completes.

After having waited until services are healthy ( run kubectl get po -A | grep -v 'Completed\|Running' to see which pods may still be Pending), take a manual backup of all Etcd clusters. These clusters are automatically backed up every 24 hours, but not until the clusters have been up that long. Taking a manual backup enables restoring from backup later in this install process if needed.

/usr/share/doc/csm/scripts/operations/etcd/take-etcd-manual-backups.sh post_install

"
# Script completion
echo "Script completed successfully!"

