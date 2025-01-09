
#!/bin/bash

# Function to check the exit status of a command
check_command() {
    if [[ $? -ne 0 ]]; then
        echo "Error: $1 failed. Exiting."
        exit 1
    fi
}

# Set environment variables
export SYSTEM_NAME=fanta
export PITDATA="$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)"
check_command "Fetching PITDATA"

export CSM_RELEASE=1.6.0-rc.6
export CSM_PATH="${PITDATA}/csm-${CSM_RELEASE}"
export IPMI_PASSWORD=initial0

# Update /etc/environment
cat << EOF >/etc/environment
CSM_RELEASE=${CSM_RELEASE}
CSM_PATH=${PITDATA}/csm-${CSM_RELEASE}
PITDATA=${PITDATA}
SYSTEM_NAME=${SYSTEM_NAME}
EOF
check_command "Updating /etc/environment"

# Pre-check before proceeding
echo "Before running this script, make sure that Create System Configuration Using SHCD stage is completed."
read -p "Is the CSM tarball file present locally? (yes/no): " user_response

if [[ "$user_response" != "yes" ]]; then
    echo "You need to complete SHCD stage then come here to proceed."
    exit 1
fi

echo "Proceeding with the script..."

# Initialize system configuration
cd ${PITDATA}/prep
check_command "Changing directory to ${PITDATA}/prep"

csi config init
check_command "Initializing CSI configuration"

cat ${PITDATA}/prep/${SYSTEM_NAME}/system_config.yaml
check_command "Displaying system_config.yaml"

# Set and initialize SITE_INIT
SITE_INIT="${PITDATA}/prep/site-init"
mkdir -pv "${SITE_INIT}"
check_command "Creating SITE_INIT directory"

"${CSM_PATH}/shasta-cfg/meta/init.sh" "${SITE_INIT}"
check_command "Initializing site-init from CSM"

# Create Baseline System Customizations
cd "${SITE_INIT}"
check_command "Changing directory to SITE_INIT"

yq merge -xP -i "${SITE_INIT}/customizations.yaml" <(yq prefix -P "${PITDATA}/prep/${SYSTEM_NAME}/customizations.yaml" spec)
check_command "Merging customizations.yaml"

yq write -i "${SITE_INIT}/customizations.yaml" spec.wlm.cluster_name "${SYSTEM_NAME}"
check_command "Updating cluster_name in customizations.yaml"

cp -pv "${SITE_INIT}/customizations.yaml" "${SITE_INIT}/customizations.yaml.prepassword"
check_command "Backing up customizations.yaml"

# Edit customization.yaml
sed -i 's/{"Cray": {"Username": "root", "Password": "XXXX"}}/{"Cray": {"Username": "root", "Password": "initial0"}}/g' customizations.yaml
check_command "Updating Cray password"

sed -i 's/{"SNMPUsername": "testuser", "SNMPAuthPassword": "XXXX", "SNMPPrivPassword": "XXXX"}/{"SNMPUsername": "testuser", "SNMPAuthPassword": "testpass1", "SNMPPrivPassword": "testpass2"}/g' customizations.yaml
check_command "Updating SNMP credentials"

sed -i 's/{"Username": "admn", "Password": "XXXX"}/{"Username": "admn", "Password": "admn"}/g' customizations.yaml
check_command "Updating admin credentials"

sed -i 's/{"Username": "root", "Password": "XXXX"}/{"Username": "root", "Password": "initial0"}/g' customizations.yaml
check_command "Updating root credentials"

# Review changes
diff "${SITE_INIT}/customizations.yaml" "${SITE_INIT}/customizations.yaml.prepassword"
check_command "Reviewing changes to customizations.yaml"

# Example: Validate the LiveCD
csi pit validate --livecd-preflight
check_command "Validating LiveCD preflight tests"

# Inject certificates
LDAP=dcldap2.hpc.amslabs.hpecorp.net
PORT=636
openssl s_client -showcerts -connect "${LDAP}:${PORT}" </dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > cacert.pem
check_command "Fetching issuer certificate"

podman run --rm -v "$(pwd):/data" \
    artifactory.algol60.net/csm-docker/stable/docker.io/library/openjdk:11-jre-slim keytool \
    -importcert -trustcacerts -file /data/cacert.pem -alias cray-data-center-ca \
    -keystore /data/certs.jks -storepass password -noprompt
check_command "Creating certs.jks"

base64 certs.jks > certs.jks.b64
check_command "Encoding certs.jks to base64"

cat <<EOF | yq w - 'data."certs.jks"' "$(<certs.jks.b64)" | \
    yq r -j - | ${SITE_INIT}/utils/secrets-encrypt.sh | \
    yq w -f - -i ${SITE_INIT}/customizations.yaml 'spec.kubernetes.sealed_secrets.cray-keycloak'
{
  "kind": "Secret",
  "apiVersion": "v1",
  "metadata": {
    "name": "keycloak-certs",
    "namespace": "services",
    "creationTimestamp": null
  },
  "data": {}
}
EOF
check_command "Injecting certs.jks into customizations.yaml"

# Encrypt secrets
"${SITE_INIT}/utils/secrets-reencrypt.sh" \
    "${SITE_INIT}/customizations.yaml" \
    "${SITE_INIT}/certs/sealed_secrets.key" \
    "${SITE_INIT}/certs/sealed_secrets.crt"
check_command "Re-encrypting secrets"

"${SITE_INIT}/utils/secrets-seed-customizations.sh" "${SITE_INIT}/customizations.yaml"
check_command "Generating secrets"

cd "${PITDATA}"
check_command "Changing directory to ${PITDATA}"

# Run PIT initialization script
/root/bin/pit-init.sh
check_command "Running pit-init.sh"



# Final message
echo "Script executed successfully. If there were no issues, you can proceed with deploying the management node."
exit 0
