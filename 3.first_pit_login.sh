
#!/bin/bash

# Set environment variables
export CSM_RELEASE=1.6.0-rc.6
export SYSTEM_NAME=fanta



# Function to check command success and exit on failure
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed."
        exit 1
    fi
}


# Echo statement asking user to manually add network info like below

echo "User needs to manually add the network info before continuing:"
echo "Example network info:"
echo "site_ip=172.30.52.72/20"
echo "site_gw=172.30.48.1"
echo "site_dns=172.30.84.40"
echo "site_nics=em0 or em1"
echo "Once done, proceed with the script."
read -p "Are you done with above ? (yes/no): " user_response

if [[ "$user_response" == "yes" ]]; then
    echo "Proceeding with the script..."

else
	echo "You need to set network configuration then run the script"
    exit 1
fi
# Prepare the data partition
echo "Preparing the data partition..."
mount -vL PITDATA
check_command "Mounting PITDATA"

# Set environment variables

export PITDATA="$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)"
export CSM_PATH="${PITDATA}/csm-${CSM_RELEASE}"


# Update /etc/environment
echo "Updating /etc/environment to set necessary variables..."
cat << EOF >/etc/environment
CSM_RELEASE=${CSM_RELEASE}
CSM_PATH=${PITDATA}/csm-${CSM_RELEASE}
GOSS_BASE=${GOSS_BASE}
PITDATA=${PITDATA}
SYSTEM_NAME=${SYSTEM_NAME}
EOF
check_command "Updating /etc/environment"

# Create admin directory for typescripts and administrative scratch work
echo "Creating admin directory for typescripts..."
mkdir -pv "$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)/prep/admin"
ls -l "$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)/prep/admin"
check_command "Creating admin directory"

# Running metalid.sh
echo "Running metalid.sh..."
/root/bin/metalid.sh
check_command "Running metalid.sh"

# Setup proxy
echo "Setting up proxy..."
export http_proxy=http://hpeproxy.its.hpecorp.net:443
export https_proxy=http://hpeproxy.its.hpecorp.net:443
check_command "Setting up proxy"

# Download documentation
echo "Downloading documentation..."
wget "https://release.algol60.net/$(awk -F. '{print "csm-"$1"."$2}' <<< ${CSM_RELEASE})/docs-csm/docs-csm-latest.noarch.rpm" -O /root/docs-csm-latest.noarch.rpm
check_command "Downloading docs-csm RPM"

# Download and install libcsm
wget "https://release.algol60.net/lib/sle-$(awk -F= '/VERSION=/{gsub(/["-]/, "") ; print tolower($NF)}' /etc/os-release)/libcsm-latest.noarch.rpm" -O /root/libcsm-latest.noarch.rpm
check_command "Downloading libcsm RPM"

# Download and extract the CSM Tarball with proxy
echo "Downloading and extracting the CSM Tarball..."
curl -C - -f -o "/var/www/ephemeral/csm-${CSM_RELEASE}.tar.gz" \
  "https://release.algol60.net/$(awk -F. '{print "csm-"$1"."$2}' <<< ${CSM_RELEASE})/csm/csm-${CSM_RELEASE}.tar.gz"
check_command "Downloading CSM tarball"

# Extract the tarball
tar -zxvf  "${PITDATA}/csm-${CSM_RELEASE}.tar.gz" -C ${PITDATA}
check_command "Extracting CSM tarball"

# Unset the proxy
unset http_proxy https_proxy

# Install/update RPMs necessary for CSM installation
echo "Installing/updating necessary RPMs for CSM..."
zypper --plus-repo "${CSM_PATH}/rpm/cray/csm/noos" --no-gpg-checks update -y cray-site-init metal-init metal-ipxe
check_command "Updating RPMs"

# Get the artifact versions
echo "Getting the artifact versions..."
KUBERNETES_VERSION="$(find ${CSM_PATH}/images/kubernetes -name '*.squashfs' -exec basename {} .squashfs \; | awk -F '-' '{print $(NF-1)}')"
echo "Kubernetes Version: ${KUBERNETES_VERSION}"

CEPH_VERSION="$(find ${CSM_PATH}/images/storage-ceph -name '*.squashfs' -exec basename {} .squashfs \; | awk -F '-' '{print $(NF-1)}')"
echo "Ceph Version: ${CEPH_VERSION}"

# Copy the NCN images from the expanded tarball
echo "Copying the NCN images from the expanded tarball..."
mkdir -pv "${PITDATA}/data/k8s/" "${PITDATA}/data/ceph/"
rsync -rltDP --delete "${CSM_PATH}/images/kubernetes/" --link-dest="${CSM_PATH}/images/kubernetes/" "${PITDATA}/data/k8s/${KUBERNETES_VERSION}"
check_command "Copying Kubernetes images"
rsync -rltDP --delete "${CSM_PATH}/images/storage-ceph/" --link-dest="${CSM_PATH}/images/storage-ceph/" "${PITDATA}/data/ceph/${CEPH_VERSION}"
check_command "Copying Ceph images"

# Generate SSH keys
echo "Generating SSH keys..."
ssh-keygen  -t rsa -f /root/.ssh/id_rsa -N ""
check_command "Generating SSH keys"

# Export the password hash for root
echo "Exporting the password hash for root..."
PW1=initial0
PW2=initial0
echo "Password for root: $PW1"

NCN_MOD_SCRIPT=$(rpm -ql docs-csm | grep ncn-image-modification.sh)

export SQUASHFS_ROOT_PW_HASH=$(echo -n "${PW1}" | openssl passwd -6 -salt $(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c4) --stdin)
if [[ -n ${SQUASHFS_ROOT_PW_HASH} ]]; then
    echo "Password hash set and exported."
else
    echo "ERROR: Problem generating password hash."
    exit 1
fi

echo "Running ncn-image-modification.sh..."
echo "${NCN_MOD_SCRIPT}"
"${NCN_MOD_SCRIPT}" -p \
   -d /root/.ssh \
   -k "/var/www/ephemeral/data/k8s/${KUBERNETES_VERSION}/kubernetes-${KUBERNETES_VERSION}.squashfs" \
   -s "/var/www/ephemeral/data/ceph/${CEPH_VERSION}/storage-ceph-${CEPH_VERSION}.squashfs"
check_command "Running ncn-image-modification.sh"

# Run metalid.sh again
echo "Running metalid.sh again..."
/root/bin/metalid.sh
check_command "Running metalid.sh again"

# Create System Configuration Using SHCD
echo "Creating system configuration using SHCD..."
echo "User needs to perform manually adding the system configuration files and proceed."
echo "Exit the script after manually creating the configuration."

exit 0

