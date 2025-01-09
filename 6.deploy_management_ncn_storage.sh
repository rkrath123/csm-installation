

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

# Step 1: Validate prerequisites
echo "Before running this script, make sure that 'Configure management network switches' stage is completed."
read -p "Is the CSM tarball file present locally? (yes/no): " user_response

if [[ "$user_response" == "yes" ]]; then
    echo "Proceeding with the script..."
else
    echo "You need to complete 'Configure management network switches' and ensure the CSM tarball is present locally. Exiting."
    exit 1
fi

# Step 2: Export username and IPMI password
echo "Step 2: Exporting username and IPMI password..."
export USERNAME=root
export IPMI_PASSWORD=initial0
check_command "Exporting username and IPMI password"

# Step 3: Set remaining helper variables
echo "Step 3: Setting helper variables..."
export IPMI_PASSWORD 
mtoken='ncn-m(?!001)\w+-mgmt'
stoken='ncn-s\w+-mgmt'
wtoken='ncn-w\w+-mgmt'
check_command "Setting helper variables"

# Step 4: Enable DCMI/IPMI for HPE hardware
echo "Step 4: Enabling DCMI/IPMI for HPE hardware..."
/root/bin/bios-baseline.sh
check_command "Running bios-baseline.sh"

# Step 5: Check power status of all NCNs
echo "Step 5: Checking power status of all NCNs..."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power status
check_command "Checking power status of NCNs"

# Step 6: Power off all NCNs
echo "Step 6: Powering off all NCNs..."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power off
check_command "Powering off NCNs"

# Step 7: Clear CMOS for non-Cray and non-Intel vendors
echo "Step 7: Clearing CMOS settings if vendor is not Cray or Intel..."
vendor_name=$(ipmitool fru | grep "Manufacturer" | awk -F ":" 'NR==1{print $2}' | xargs)
if [[ "$vendor_name" == "Cray Inc." || "$vendor_name" == "Intel Corporation" ]]; then
    echo "Vendor is Cray or Intel, skipping CMOS clearing."
else
    grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
        xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} chassis bootdev none options=clear-cmos
    check_command "Clearing CMOS"
fi

# Step 8: Boot NCNs to BIOS
echo "Step 8: Booting NCNs to BIOS..."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} chassis bootdev bios options=efiboot
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power on
check_command "Booting NCNs to BIOS"

# Step 9: Run bios-baseline.sh again
echo "Step 9: Running bios-baseline.sh again for HPE servers..."
/root/bin/bios-baseline.sh
check_command "Running bios-baseline.sh (second time)"

# Step 10: Power off NCNs
echo "Step 10: Powering off NCNs..."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power off
check_command "Powering off NCNs"

# Step 11: Deploy management nodes
echo "Step 11: Deploying management nodes..."
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} chassis bootdev pxe options=efiboot,persistent
grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power off
check_command "Deploying management nodes"

# Step 12: Boot storage NCNs
echo "Step 12: Booting storage NCNs..."
grep -oP "${stoken}" /etc/dnsmasq.d/statics.conf | sort -u |
    xargs -t -i ipmitool -I lanplus -U "${USERNAME}" -E -H {} power on
check_command "Booting storage NCNs"

# Step 13: Wait for storage nodes readiness
echo "Step 13: Waiting for storage nodes to become ready...with below message"
echo "...sleeping 5 seconds until /etc/kubernetes/admin.conf"

echo "
After storage node booted with -sleeping 5 seconds until /etc/kubernetes/admin.conf message perform below 

Deploy Kubernetes NCNs
(pit#) Boot the Kubernetes NCNs.

grep -oP \"(${mtoken}|${wtoken})\" /etc/dnsmasq.d/statics.conf | sort -u | xargs -t -i ipmitool -I lanplus -U \"\${USERNAME}\" -E -H {} power on
(pit#) Start watching the first Kubernetes master's console.

Either stop watching ncn-s001-mgmt before doing this, or do it in a different window.

NOTE: To exit a conman console, press & followed by a . (e.g. keystroke &.)

Determine the first Kubernetes master.

FM=\$(jq -r '.\"Global\".\"meta-data\".\"first-master-hostname\"' \"\${PITDATA}\"/configs/data.json)
echo \${FM}
Open its console.

conman -j \"\${FM}-mgmt\"
NOTES:

If the nodes have PXE boot issues (e.g. getting PXE errors, not pulling the ipxe.efi binary), then see Troubleshooting PXE Boot.
If one of the master nodes seems hung waiting for the storage nodes to create a secret, then check the storage node consoles for error messages. If any are found, then consult CEPH CSI Troubleshooting.
(pit#) Wait for the deployment to finish.

Wait for the first Kubernetes master to complete cloud-init.

The following text should appear in the console of the first Kubernetes master:

The system is finally up, after 995.71 seconds cloud-init has come to completion.

ssh "${FM}" kubectl get nodes -o wide
Expected output looks similar to the following:

NAME       STATUS   ROLES                  AGE     VERSION    INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                                                  KERNEL-VERSION                 CONTAINER-RUNTIME
ncn-m002   Ready    control-plane,master   7m39s   v1.22.13   10.252.1.5    <none>        SUSE Linux Enterprise High Performance Computing 15 SP5   5.14.21-150500.55.12-default   containerd://1.5.16
ncn-m003   Ready    control-plane,master   7m16s   v1.22.13   10.252.1.6    <none>        SUSE Linux Enterprise High Performance Computing 15 SP5   5.14.21-150500.55.12-default   containerd://1.5.16
ncn-w001   Ready    <none>                 7m16s   v1.22.13   10.252.1.7    <none>        SUSE Linux Enterprise High Performance Computing 15 SP5   5.14.21-150500.55.12-default   containerd://1.5.16
ncn-w002   Ready    <none>                 7m18s   v1.22.13   10.252.1.8    <none>        SUSE Linux Enterprise High Performance Computing 15 SP5   5.14.21-150500.55.12-default   containerd://1.5.16
ncn-w003   Ready    <none>                 7m16s   v1.22.13   10.252.1.9    <none>        SUSE Linux Enterprise High Performance Computing 15 SP5   5.14.21-150500.55.12-default   containerd://1.5.16


"


echo "Script completed successfully!"


