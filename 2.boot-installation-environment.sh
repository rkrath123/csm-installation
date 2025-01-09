
#!/bin/bash


 
export CSM_RELEASE=1.6.0-rc.6

# Ask the user if the CSM tarball file is present locally

echo "Before running this script, make sure the CSM tarball (csm-${CSM_RELEASE}.tar.gz) is present locally and usb device is marked as /dev/sdd  \
 if not /dev/sdd then change USB valriable accordingly in the script "
 
# Function to check command success and exit on failure
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed."
        exit 1
    fi
}



 
read -p "Is the CSM tarball file present locally? (yes/no): " user_response

if [[ "$user_response" == "yes" ]]; then
    echo "Proceeding with the script..."

else
	echo "You need to download the CSM tarball file and place it in the current directory then proceed"
    exit 1
fi

# Get the vendor name from the FRU output
vendor_name=$(ipmitool fru | grep "Manufacturer" | awk -F ":" 'NR==1{print $2}' | xargs)

# Check if the vendor name is "Cray Inc." or "Intel Corporation"
if [[ "$vendor_name" == "Cray Inc." || "$vendor_name" == "Intel Corporation" ]]; then
    echo "Vendor is $vendor_name. Proceeding with USB creation..."

    # Create a USB stick using the following procedure. Get cray-site-init from the tarball.
    OUT_DIR="$(pwd)/csm-temp"
    mkdir -pv "${OUT_DIR}"
    tar -C "${OUT_DIR}" --wildcards --no-anchored --transform='s/.*\///' -xzvf "csm-${CSM_RELEASE}.tar.gz" 'cray-site-init-*.rpm'
    check_command "Extracting cray-site-init from tarball"

    # Install the write-livecd.sh script
    echo "Installing the write-livecd.sh script..."
    rpm -Uvh --force ${OUT_DIR}/cray-site-init*.rpm
    check_command "Installing cray-site-init RPM"

    # Check for the SCSI devices
    lsscsi
    check_command "Listing SCSI devices"

    # Set a variable with the USB device and for the CSM_PATH
    USB=/dev/sdd

    # Use the CSI application to format the USB stick
    echo "Using CSI application to format the USB stick..."
    csi pit format "${USB}" "${OUT_DIR}/"cray-pre-install-toolkit-*.iso 50000
    check_command "Formatting USB stick with CSI"

    # Sleep for 2 minutes, allowing the user to check for any issues
    echo "Sleeping for 2 minutes. Check if there are any issues and then exit..."
    sleep 1m

    # Prompt user to boot the LiveCD
    echo "Boot the LiveCD"

    # Prompt the user for manual reboot and BIOS selection
    echo "User needs to reboot the system manually and select the USB stick from the BIOS menu"
    exit
elif [[ "$vendor_name" == "HPE" ]]; then
    echo "HPE iLO BMCs"
    echo "Prepare a server on the network to host the pre-install-toolkit ISO file, if the current server is insufficient."
    echo "Then follow the HPE iLO BMCs to boot the RemoteISO before returning here."
else
    echo "Vendor is not Cray Inc., Intel Corporation, or HPE. Skipping specific processes for USB creation."
fi
