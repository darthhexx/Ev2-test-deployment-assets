# script use to provide a base platform to run custom scripts in an ACI-type environment

set -ex

install_az_cli() {
    echo "importing Microsoft repository keys"
    rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo "configuring azure repositories"
    dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
    echo "installing the azure CLI"
    dnf -y install azure-cli
}

reboot_for_cleanup() {
    echo "rebooting"
    /sbin/reboot
}

setup_self_delete() {
    cat >/usr/local/bin/delete-myself.sh <<EOF
#!/bin/bash
set -eu

export AZURE_CONFIG_DIR=\$(mktemp -d)

echo "Logging into Azure..."
RETRIES=3
while [ "\$RETRIES" -gt 0 ]; do
    if az login -i --allow-no-subscriptions
    then
        echo "az login successful"
        break
    else
        echo "az login failed. Retrying..."
        let RETRIES-=1
        sleep 5
    fi
done

trap "cleanup" EXIT

cleanup() {
  az logout
  [[ "\$AZURE_CONFIG_DIR" =~ /tmp/.+ ]] && rm -rf \$AZURE_CONFIG_DIR
}

az vm delete -g $RESOURCE_GROUP -n $VM_NAME -y
EOF
    chmod u+x /usr/local/bin/delete-myself.sh

    cat >/etc/systemd/system/delete-myself.service <<EOF
[Unit]
Description=Delete myself
[Service]
Type=oneshot
ExecStart=/usr/local/bin/delete-myself.sh $var
EOF

cat >/etc/systemd/system/delete-myself.timer <<EOF
[Unit]
Description=Delete myself
After=network-online.target
Wants=network-online.target
[Timer]
OnBootSec=30s
OnCalendar=*:0/5
[Install]
WantedBy=timers.target
EOF
    systemctl enable delete-myself.timer
    # reboot once we exit to kick-off the delete timer
    trap "reboot_for_cleanup" EXIT
}

setup_self_delete
install_az_cli

# extract the package and run the specified script
tar xf $PACKAGE_NAME

./$SCRIPT_NAME
