#!/bin/bash -x

USER=$1
SYSDFILE="/etc/docker/daemon.json"

# docker start functions
start_nsdocker ()
{
  docker run --net=host --privileged --userns=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/getKeys.py ${USER}
}

start_docker ()
{
  docker run --net=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/getKeys.py ${USER}
}


# Source the etcd
if [ -f /opt/klam/environment ]; then
  source /opt/klam/environment;
fi

chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 640 /etc/gshadow
chmod 640 /etc/shadow
chmod 600 /etc/passwd-
chmod 600 /etc/group-
chmod 600 /etc/gshadow-
chmod 600 /etc/shadow-
chmod -R g-wx,o-rwx /var/log/*

echo "Running authorizedkeys_command for ${USER}" | systemd-cat -p info -t klam-ssh

if grep "userns" ${SYSDFILE}; then
  OUTPUT=`start_nsdocker`
else
  OUTPUT=`start_docker`
fi
if [[ ! -z $OUTPUT ]]; then
  echo "Klam verified: Creating User Directory"
  if grep "pam_mkhomedir" /etc/pam.d/system-login; then
    echo "Using PAM module"
  else
    echo "create userdir"
    mkdir -p /home/${USER} > /dev/null
    chown -R ${USER}. /home/${USER} > /dev/null
    chmod 750 /home/${USER}
  fi
  echo "adding user to passwd file"
  sed -i "/${USER}/d" /etc/passwd
  echo "${USER}:x:$(id -u ${USER}):$(id -g ${USER}):KLAM USER ${USER}:/home/${USER}:/bin/bash" >> /etc/passwd
  echo "Adding user to group file"
  sed -i "/$(id -g ${USER})/d" /etc/group
  echo "${USER}:x:$(id -g ${USER}):" >> /etc/group
  gpasswd -a ${USER} docker
  echo "$OUTPUT"
fi
exit 0
