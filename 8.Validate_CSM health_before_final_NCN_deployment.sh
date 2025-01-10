
#!/bin/bash

# Function for error handling
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed. Exiting."
        exit 1
    else
        echo "Success: $1 completed."
    fi
}

# User prompt
echo "At this point, Configure the Cray Command Line Interface (cray CLI)."
read -p "Press (yes/no): " user_response

if [[ "$user_response" != "yes" ]]; then
    echo "You need to Configure the Cray Command Line Interface (cray CLI) then come here and proceed"
    exit 1
else
    echo "Proceeding with the script..."
fi

# Set up CSM release and proxy
export CSM_RELEASE=1.6.0-rc.6
echo "Setting up proxy..."
export http_proxy=http://hpeproxy.its.hpecorp.net:443
export https_proxy=http://hpeproxy.its.hpecorp.net:443

# Download docs-csm and libcsm
echo "Downloading docs-csm and libcsm packages..."
wget "https://release.algol60.net/$(awk -F. '{print "csm-"$1"."$2}' <<< ${CSM_RELEASE})/docs-csm/docs-csm-latest.noarch.rpm" -O /root/docs-csm-latest.noarch.rpm
check_command "Download docs-csm"

wget "https://release.algol60.net/lib/sle-$(awk -F= '/VERSION=/{gsub(/["-]/, "") ; print tolower($NF)}' /etc/os-release)/libcsm-latest.noarch.rpm" -O /root/libcsm-latest.noarch.rpm
check_command "Download libcsm"

# Unset proxy
echo "Unsetting proxy..."
unset http_proxy https_proxy
check_command "Unset proxy"

# Platform health checks
echo "Restarting goss-servers on NCN nodes..."
mtoken='ncn-m(?!001)\w+-mgmt'
stoken='ncn-s\w+-mgmt'
wtoken='ncn-w\w+-mgmt'
ncn_nodes=$(grep -oP "(${mtoken}|${stoken}|${wtoken})" /etc/dnsmasq.d/statics.conf | sort -u | sed -e "s/-mgmt//" | tr -t '\n' ',')
ncn_nodes=${ncn_nodes%,}
pdsh -S -b -w $ncn_nodes 'systemctl restart goss-servers'
check_command "Restart goss-servers"

echo "Running NCN health checks..."
/opt/cray/tests/install/ncn/automated/ncn-k8s-combined-healthcheck
check_command "ncn-k8s-combined-healthcheck"

echo "Running optional NCN resource checks..."
/opt/cray/platform-utils/ncnHealthChecks.sh -s ncn_uptimes
check_command "ncn_uptimes"
/opt/cray/platform-utils/ncnHealthChecks.sh -s node_resource_consumption
check_command "node_resource_consumption"
/opt/cray/platform-utils/ncnHealthChecks.sh -s pods_not_running
check_command "pods_not_running"

# SSH and execute verification scripts on ncn-m002
echo "Executing scripts on ncn-m002..."
ssh -o StrictHostKeyChecking=no -T root@ncn-m002 << EOF
  /opt/cray/csm/scripts/hms_verification/hsm_discovery_status_test.sh
  check_command "hsm_discovery_status_test.sh"

  /opt/cray/csm/scripts/hms_verification/verify_hsm_discovery.py
  check_command "verify_hsm_discovery.py"

  /opt/cray/csm/scripts/hms_verification/run_hardware_checks.sh
  check_command "run_hardware_checks.sh"

  /usr/share/doc/csm/scripts/operations/pyscripts/start.py test_bican_internal
  check_command "test_bican_internal"

  /opt/cray/tests/integration/csm/barebones_image_test
  check_command "barebones_image_test"

  /usr/share/doc/csm/scripts/operations/gateway-test/gateway-test.py eniac.dev.cray.com
  check_command "gateway-test.py"
EOF

# User instructions for additional tests
echo "User needs to perform the following additional steps:"
echo "1. External SSH access test execution."
echo "2. Running Gateway Tests on a Device Outside the System."
echo "3. UAN test execution."

echo "Script execution completed."
