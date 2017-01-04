#!/bin/bash -x

# Source the etcd
if [ -f /opt/klam/environment ]; then
  source /opt/klam/environment;
fi

echo "Creating User Directory"

mkdir -p /home/$1 > /dev/null
chown -R $1. /home/$1 > /dev/null

echo "Running authorizedkeys_command for $1" | systemd-cat -p info -t klam-ssh

docker run --net=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/getKeys.py $1
exit 0
