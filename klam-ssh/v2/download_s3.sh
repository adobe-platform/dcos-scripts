#!/bin/bash

USER=$1
SYSDFILE="/etc/docker/daemon.json"

# docker start functions
start_nsdocker ()
{
  docker run --net=host --privileged --userns=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/downloadS3/downloadS3
}

start_docker ()
{
  docker run --net=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/downloadS3/downloadS3
}


# Source the environment
if [ -f /opt/klam/environment ]; then
  source /opt/klam/environment;
fi

if grep "userns" ${SYSDFILE}; then
  start_nsdocker
else
  start_docker
fi
exit 0
