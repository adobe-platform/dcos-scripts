#!/bin/bash -x

# Source the environment
if [ -f /opt/klam/environment ]; then
  source /opt/klam/environment;
fi

docker run --privileged --userns=host --rm -e ROLE_NAME=${ROLE_NAME} -e ENCRYPTION_ID=${ENCRYPTION_ID} -e ENCRYPTION_KEY=${ENCRYPTION_KEY} -e KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX} ${IMAGE} /usr/lib/klam/downloadS3.py
exit 0
