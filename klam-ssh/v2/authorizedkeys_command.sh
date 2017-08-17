#!/bin/bash -x

USER=$1
SYSDFILE="/etc/systemd/system/docker.service.d/10-enable-namespaces.conf"

# docker start functions
start_nsdocker ()
{
  docker run --privileged --userns=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/getKeys.py ${USER}
}

start_docker ()
{
  docker run --net=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/getKeys.py ${USER}
}


# Source the etcd
if [ -f /opt/klam/environment ]; then
  source /opt/klam/environment;
fi

echo "Creating User Directory"

if grep "pam_mkhomedir" /etc/pam.d/system-login; then
  echo "PAM userdir"
else
  echo "create userdir"
  mkdir -p /home/${USER} > /dev/null
  chown -R ${USER}. /home/${USER} > /dev/null
  chmod 750 /home/${USER}
fi

echo "adding user to docker group"
gpasswd -a ${USER} docker

echo "adding user to passwd file"
sed -i "/${USER}/d" /etc/passwd
echo "${USER}:x:$(id -u ${USER}):$(id -g ${USER}):KLAM USER ${USER}:/home/${USER}:/bin/bash" >> /etc/passwd
echo "adding group to group file"
sed -i "/$(id -g ${USER})/d" /etc/group
echo "${USER}:x:$(id -g ${USER}):" >> /etc/group

echo "Running authorizedkeys_command for ${USER}" | systemd-cat -p info -t klam-ssh

if [ -a ${SYSDFILE} ]; then
  if grep "userns-remap=default" ${SYSDFILE}; then
    start_nsdocker
  else
    start_docker
  fi
else
  start_docker
fi
exit 0
