
#!/bin/bash

# Function for error handling
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: Command failed - $1"
        exit 1
    fi
}

export SYSTEM_NAME=fanta

# List of pods to check
pods=("Ceph" "cray-bss" "cray-dhcp-kea" "cray-dns-unbound" "cray-ipxe" "cray-sls" "cray-tftp")

# Loop through each pod and check its status
echo "Checking pods status..."
for pod in "${pods[@]}"; do
  echo "Checking status of pod $pod..."
  status=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}')
  
  if [[ "$status" != "Running" && "$status" != "Completed" ]]; then
    echo "Error: Pod $pod is not in 'Running' or 'Completed' state. Current status: $status"
    exit 1
  fi
done
echo "All pods are running correctly."

# Upload SLS file
echo "Uploading SLS file..."
csi upload-sls-file --sls-file "${PITDATA}/prep/${SYSTEM_NAME}/sls_input_file.json"
check_command "Upload SLS file"

# Upload Kubernetes NCN artifacts
echo "Uploading Kubernetes NCN artifacts..."
set -o pipefail
IMS_UPLOAD_SCRIPT=$(rpm -ql docs-csm | grep ncn-ims-image-upload.sh)
check_command "Find IMS upload script"

export IMS_ROOTFS_FILENAME="$(readlink -f /var/www/ncn-m002/rootfs)"
export IMS_INITRD_FILENAME="$(readlink -f /var/www/ncn-m002/initrd.img.xz)"
export IMS_KERNEL_FILENAME="$(readlink -f /var/www/ncn-m002/kernel)"
K8S_IMS_IMAGE_ID=$($IMS_UPLOAD_SCRIPT)
check_command "Upload Kubernetes NCN image"

[[ -n ${K8S_IMS_IMAGE_ID} ]] && echo -e "Kubernetes NCN image IMS ID: ${K8S_IMS_IMAGE_ID}\nSUCCESS" || check_command "Check Kubernetes IMS image ID"

# Upload Storage NCN artifacts
echo "Uploading Storage NCN artifacts..."
export IMS_ROOTFS_FILENAME="$(readlink -f /var/www/ncn-s001/rootfs)"
export IMS_INITRD_FILENAME="$(readlink -f /var/www/ncn-s001/initrd.img.xz)"
export IMS_KERNEL_FILENAME="$(readlink -f /var/www/ncn-s001/kernel)"
STORAGE_IMS_IMAGE_ID=$($IMS_UPLOAD_SCRIPT)
check_command "Upload Storage NCN image"

[[ -n ${STORAGE_IMS_IMAGE_ID} ]] && echo -e "Storage NCN image IMS ID: ${STORAGE_IMS_IMAGE_ID}\nSUCCESS" || check_command "Check Storage IMS image ID"

# Get a token for authenticated communication with the gateway
echo "Getting token for gateway communication..."
export TOKEN=$(curl -k -s -S -d grant_type=client_credentials -d client_id=admin-client \
                -d client_secret=`kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}' | base64 -d` \
                https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token | jq -r '.access_token')
check_command "Get gateway token"

# Upload the data.json file to BSS
echo "Uploading data.json file to BSS..."
csi handoff bss-metadata \
    --data-file "${PITDATA}/configs/data.json" \
    --kubernetes-ims-image-id "$K8S_IMS_IMAGE_ID" \
    --storage-ims-image-id "$STORAGE_IMS_IMAGE_ID" && echo SUCCESS
check_command "Upload BSS metadata"

# Patch metadata for Ceph nodes
echo "Patching metadata for Ceph nodes..."
python3 /usr/share/doc/csm/scripts/patch-ceph-runcmd.py
check_command "Patch Ceph metadata"

# Ensure DNS server value is correctly set
echo "Updating DNS server values..."
csi handoff bss-update-cloud-init --set meta-data.dns-server="10.92.100.225 10.94.100.225" --limit Global
check_command "Update DNS server values"




# Get the vendor name from the FRU output
vendor_name=$(ipmitool fru | grep "Manufacturer" | awk -F ":" 'NR==1{print $2}' | xargs)
check_command "vendor name display"

# Check if the vendor name is "Cray Inc." or "Intel Corporation"
if [[ "$vendor_name" == "Cray Inc."   ]]; then
     efibootmgr | grep -iP '(pxe ipv?4.*adapter)' | tee /tmp/bbs1


 
 elif [[ "$vendor_name" == "HPE" ]]; then
    efibootmgr | grep -i 'port 1' | grep -i 'pxe ipv4' | tee /tmp/bbs1
 elif [[ "$vendor_name" == "Intel Corporation" ]]; then
   efibootmgr | grep -i 'ipv4' | grep -iv 'baseboard' | tee /tmp/bbs1
 
else
    echo "No venodr specified"
fi

echo"Create a list of the Cray disk boot devices."

efibootmgr | grep -i cray | tee /tmp/bbs2
check_command "Cray disk boot devices"

echo "Set the boot order to first PXE boot, with disk boot as the fallback option."

efibootmgr -o $(cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | tr -t '\n' ',' | sed 's/,$//') | grep -i bootorder
check_command " pxe boot error"

echo "Set all of the desired boot options to be active."
cat /tmp/bbs* | awk '!x[$0]++' | sed 's/^Boot//g' | tr -d '*' | awk '{print $1}' | xargs -r -t -i efibootmgr -b {} -a
check_command "boot order activate"

if [[ "$vendor_name" == "Cray Inc." ||   ]]; then
    efibootmgr | grep -ivP '(pxe ipv?4.*)' | grep -iP '(adapter|connection|nvme|sata)' | tee /tmp/rbbs1
	efibootmgr | grep -iP '(pxe ipv?4.*)' | grep -i connection | tee /tmp/rbbs2

 elif [[ "$vendor_name" == "HPE" ]]; then
    efibootmgr | grep -vi 'pxe ipv4' | grep -i adapter |tee /tmp/rbbs1
    efibootmgr | grep -iP '(sata|nvme)' | tee /tmp/rbbs2
 elif [[ "$vendor_name" == "Intel Corporation" ]]; then
   efibootmgr | grep -vi 'ipv4' | grep -iP '(sata|nvme|uefi)' | tee /tmp/rbbs1
   efibootmgr | grep -i baseboard | tee /tmp/rbbs2
 
else
   echo "venodor is not Cray Inc or Intel Corporation or HPE"
    
fi

echo "Remove them."

cat /tmp/rbbs* | awk '!x[$0]++' | sed 's/^Boot//g' | awk '{print $1}' | tr -d '*' | xargs -r -t -i efibootmgr -b {} -B
check_command "Remove error"

echo "Tell the PIT node to PXE boot on the next boot."

efibootmgr -n $(efibootmgr | grep -m1 -Ei "ip(v4|4)" | awk '{match($0, /[[:xdigit:]]{4}/, m); print m[0]}') | grep -i bootnext
check_command "next boot"



#This script creates a backup of select files on the PIT node, copying them to both another master NCN and to S3.

# The script below may prompt for the NCN root password.
echo "Create PIT backup and copy it off."
/usr/share/doc/csm/install/scripts/backup-pit-data.sh
check_command "backup pit"



echo "
user need to manually continue from below reboot till last"
https://github.com/Cray-HPE/docs-csm/blob/release/1.6/install/deploy_final_non-compute_node.md#4-reboot

"
