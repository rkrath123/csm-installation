
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

# 1. Upload the CSM tarball's RPMs and container images to the local Nexus instance
echo "Step 1: Uploading the CSM tarball's RPMs and container images to the local Nexus instance..."
/srv/cray/metal-provision/scripts/nexus/setup-nexus.sh -s
check_command "Uploading CSM tarball to Nexus"

# 2. Add the local Zypper repositories for noos and the current SLES distribution
echo "Step 2: Adding the local Zypper repositories..."
zypper addrepo --no-gpgcheck --refresh http://packages/repository/csm-noos csm-noos
check_command "Adding csm-noos repository"

releasever_major=$(grep VERSION_ID /etc/os-release | awk -F '"' '{print $2}' | cut -d '.' -f 1)
releasever_minor=$(grep VERSION_ID /etc/os-release | awk -F '"' '{print $2}' | cut -d '.' -f 2)

zypper addrepo --no-gpgcheck --refresh "http://packages/repository/csm-sle-${releasever_major}sp${releasever_minor}" "csm-sle"
check_command "Adding csm-sle repository"

# 3. Ensure any new, updated packages pertinent to the CSM install are installed
echo "Step 3: Installing necessary packages for the CSM installation..."
zypper --no-gpg-checks install -y canu craycli csm-testing hpe-csm-goss-package iuf-cli platform-utils
check_command "Installing CSM-related packages"

# 4. Validate the LiveCD
echo "Step 4: Validating the LiveCD..."
csi pit validate --livecd-preflight
check_command "LiveCD validation"

echo "All steps completed successfully!"


