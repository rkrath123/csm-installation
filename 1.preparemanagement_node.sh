#!/bin/bash

# Set the username and IPMI password
export username=root
export IPMI_PASSWORD=initial0

# Function to check command success and exit on failure
 check_command() {
     if [ $? -ne 0 ]; then
        echo "Error: $1 failed."
        exit 1
    fi
 }

# Disable DHCP service
echo "Disabling DHCP service..."
kubectl scale -n services --replicas=0 deployment cray-dhcp-kea
check_command "Disabling DHCP service"



# Power each NCN off using ipmitool from ncn-m001
echo "Powering off each NCN using ipmitool from ncn-m001..."

# Get the list of BMC IP addresses for the NCNs
readarray BMCS < <(grep mgmt /etc/hosts | awk '{print $NF}' | grep -v m001 | sort -u)
check_command "Getting list of BMC IP addresses"

# Power off the NCNs
echo "Powering off NCNs..."
printf "%s\n" ${BMCS[@]} | xargs -t -i ipmitool -I lanplus -U "${username}" -P "${IPMI_PASSWORD}" -E -H {} power off
check_command "Powering off NCNs"

# Check the power status to confirm that the nodes have powered off
echo "Checking power status of the NCNs..."
printf "%s\n" ${BMCS[@]} | xargs -t -i ipmitool -I lanplus -U "${username}" -P "${IPMI_PASSWORD}" -E -H {} power status
check_command "Checking power status of NCNs"

# Set the BMCs to DHCP
function bmcs_set_dhcp {
   echo "Setting BMCs to DHCP..."
   local lan=1
   for bmc in ${BMCS[@]}; do
      # By default the LAN for the BMC is lan channel 1, except on Intel systems
      if ipmitool -I lanplus -U "${username}" -P "${IPMI_PASSWORD}" -E -H "${bmc}" lan print 3 2>/dev/null; then
         lan=3
      fi
      printf "Setting %s to DHCP ... " "${bmc}"
      if ipmitool -I lanplus -U "${username}" -P "${IPMI_PASSWORD}" -E -H "${bmc}" lan set "${lan}" ipsrc dhcp; then
         echo "Done"
      else
         echo "Error: Failed to set %s to DHCP" "${bmc}"
         exit 1
      fi
   done
}

# Run the function to set DHCP on BMCs
bmcs_set_dhcp

# Perform a cold reset of any BMCs which are still reachable
function bmcs_cold_reset {
  echo "Performing cold reset on reachable BMCs..."
  for bmc in ${BMCS[@]}; do
     printf "Resetting %s ... " "${bmc}"
     if ipmitool -I lanplus -U "${username}" -P "${IPMI_PASSWORD}"  -E -H "${bmc}" mc reset cold; then
        echo "Done"
     else
        echo "Error: Failed to reset %s" "${bmc}"
        exit 1
     fi
  done
}

# Run the function to reset BMCs
bmcs_cold_reset

echo "Script completed successfully."
