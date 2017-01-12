#!/bin/bash -x

# Source the etcd
if [ -f /opt/klam/environment ]; then
  source /opt/klam/environment;
fi

echo "Creating User Directory"

if grep "pam_mkhomedir" /etc/pam.d/system-login; then
  echo "PAM userdir"
else
  echo "create userdir"
  mkdir -p /home/$1 > /dev/null
  chown -R $1. /home/$1 > /dev/null
fi

echo "Running authorizedkeys_command for $1" | systemd-cat -p info -t klam-ssh

docker run --privileged --userns=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/getKeys.py $1
exit 0
