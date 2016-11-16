#!/bin/bash

# Source: https://github.com/meltwater/docker-cleanup

checkPatterns() {
    keepit=$3
    if [ -n "$1" ]; then
        for PATTERN in $(echo $1 | tr "," "\n"); do
        if [[ "$2" = $PATTERN* ]]; then
            if [ $DEBUG ]; then echo "DEBUG: Matches $PATTERN - keeping" >> stdout; fi
            keepit=1
        else
            if [ $DEBUG ]; then echo "DEBUG: No match for $PATTERN" >> stdout; fi
        fi
        done
    fi
    return $keepit
}

if [ ! -e "/var/run/docker.sock" ]; then
    echo "=> Cannot find docker socket(/var/run/docker.sock), please check the command!" >> stderr
    exit 1
fi

if docker version >/dev/null; then
    echo "docker is running properly" >> stdout
else
    echo "Cannot run docker binary at /usr/bin/docker" >> stderr
    echo "Please check if the docker binary is mounted correctly"  >> stderr
    exit 1
fi

if [[ -z "${CLEAN_PERIOD}" ]]; then
    echo "=> CLEAN_PERIOD not defined, use the default value." >> stdout
    CLEAN_PERIOD=1800
fi

if [[ -z "${DELAY_TIME}" ]]; then
    echo "=> DELAY_TIME not defined, use the default value." >> stdout
    DELAY_TIME=1800
fi

if [ "${KEEP_IMAGES}" == "**None**" ]; then
    unset KEEP_IMAGES
fi

if [ "${KEEP_CONTAINERS}" == "**None**" ]; then
    unset KEEP_CONTAINERS
fi
if [ "${KEEP_CONTAINERS}" == "**All**" ]; then
    KEEP_CONTAINERS="."
fi

if [ "${KEEP_CONTAINERS_NAMED}" == "**None**" ]; then
    unset KEEP_CONTAINERS_NAMED
fi
if [ "${KEEP_CONTAINERS_NAMED}" == "**All**" ]; then
    KEEP_CONTAINERS_NAMED="."
fi

if [ "${LOOP}" != "false" ]; then
    LOOP=true
fi

if [ "${DEBUG}" == "0" ]; then
    unset DEBUG
fi

if [ "${CLEANUP_VOLUMES}" == "0" ]; then
    unset CLEANUP_VOLUMES
fi

if [ $DEBUG ]; then echo DEBUG ENABLED; fi

echo "=> Run the clean script every ${CLEAN_PERIOD} seconds and delay ${DELAY_TIME} seconds to clean." >> stdout

trap '{ echo "User Interupt." >> stderr; exit 1; }' SIGINT
trap '{ echo "SIGTERM received, exiting." >> stderr; exit 0; }' SIGTERM
while [ 1 ]
do
    if [ $DEBUG ]; then echo DEBUG: Starting loop >> stdout; fi

    # Cleanup unused volumes
    if [ $CLEANUP_VOLUMES ]; then
      if [ $DEBUG ]; then echo DEBUG: Cleaning uo volumes >> stdout; fi
      if [[ $(docker version --format '{{(index .Server.Version)}}' | grep -E '^[01]\.[012345678]\.') ]]; then
        echo "=> Removing unused volumes using 'docker-cleanup-volumes.sh' script" >> stdout
        /docker-cleanup-volumes.sh
      else
        echo "=> Removing unused volumes using native 'docker volume' command" >> stdout
        for volume in $(docker volume ls -qf dangling=true); do
          echo "Deleting ${volume}" >> stdout
          docker volume rm "${volume}"
        done
      fi
    fi

    IFS='
 '

    # Cleanup exited/dead containers
    echo "=> Removing exited/dead containers" >> stdout
    EXITED_CONTAINERS_IDS="`docker ps -a -q -f status=exited -f status=dead | xargs echo`"
    for CONTAINER_ID in $EXITED_CONTAINERS_IDS; do
      CONTAINER_IMAGE=$(docker inspect --format='{{(index .Config.Image)}}' $CONTAINER_ID)
      CONTAINER_NAME=$(docker inspect --format='{{(index .Name)}}' $CONTAINER_ID)
      if [ $DEBUG ]; then echo "DEBUG: Check container image $CONTAINER_IMAGE named $CONTAINER_NAME" >> stdout; fi
      keepit=0
      checkPatterns "${KEEP_CONTAINERS}" "${CONTAINER_IMAGE}" $keepit
      keepit=$?
      checkPatterns "${KEEP_CONTAINERS_NAMED}" "${CONTAINER_NAME}" $keepit
      keepit=$?
      if [[ $keepit -eq 0 ]]; then
        echo "Removing stopped container $CONTAINER_ID" >> stdout
        docker rm -v $CONTAINER_ID
      fi
    done
    unset CONTAINER_ID

    echo "=> Removing unused images" >> stdout

    # Get all containers in "created" state
    rm -f CreatedContainerIdList
    docker ps -a -q -f status=created | sort > CreatedContainerIdList

    # Get all image ID
    ALL_LAYER_NUM=$(docker images -a | tail -n +2 | wc -l)
    docker images -q --no-trunc | sort -o ImageIdList
    CONTAINER_ID_LIST=$(docker ps -aq --no-trunc)
    # Get Image ID that is used by a containter
    rm -f ContainerImageIdList
    touch ContainerImageIdList
    for CONTAINER_ID in ${CONTAINER_ID_LIST}; do
        LINE=$(docker inspect ${CONTAINER_ID} | grep "\"Image\": \"\(sha256:\)\?[0-9a-fA-F]\{64\}\"")
        IMAGE_ID=$(echo ${LINE} | awk -F '"' '{print $4}')
        echo "${IMAGE_ID}" >> ContainerImageIdList
    done
    sort ContainerImageIdList -o ContainerImageIdList

    # Remove the images being used by containers from the delete list
    comm -23 ImageIdList ContainerImageIdList > ToBeCleanedImageIdList

    # Remove those reserved images from the delete list
    if [ -n "${KEEP_IMAGES}" ]; then
      rm -f KeepImageIdList
      touch KeepImageIdList
      # This looks to see if anything matches the regexp
      docker images --no-trunc | (
        while read repo tag image junk; do
          keepit=0
          if [ $DEBUG ]; then echo "DEBUG: Check image $repo:$tag" >> stdout; fi
          for PATTERN in $(echo ${KEEP_IMAGES} | tr "," "\n"); do
            if [[ -n "$PATTERN" && "${repo}:${tag}" = $PATTERN* ]]; then
              if [ $DEBUG ]; then echo "DEBUG: Matches $PATTERN" >> stdout; fi
              keepit=1
            else
              if [ $DEBUG ]; then echo "DEBUG: No match for $PATTERN" >> stdout; fi
            fi
          done
          if [[ $keepit -eq 1 ]]; then
            if [ $DEBUG ]; then echo "DEBUG: Marking image $repo:$tag to keep" >> stdout; fi
            echo $image >> KeepImageIdList
          fi
        done
      )
      # This explicitly looks for the images specified
      arr=$(echo ${KEEP_IMAGES} | tr "," "\n")
      for x in $arr
      do
          if [ $DEBUG ]; then echo "DEBUG: Identifying image $x" >> stdout; fi
          docker inspect $x 2>/dev/null| grep "\"Id\": \"\(sha256:\)\?[0-9a-fA-F]\{64\}\"" | head -1 | awk -F '"' '{print $4}'  >> KeepImageIdList
      done
      sort KeepImageIdList -o KeepImageIdList
      comm -23 ToBeCleanedImageIdList KeepImageIdList > ToBeCleanedImageIdList2
      mv ToBeCleanedImageIdList2 ToBeCleanedImageIdList
    fi

    # Touch the health check file before any sleep commands
    echo "=> Updating health check file" >> stdout
    echo $(date) > healthcheck

    # Wait before cleaning containers and images
    echo "=> Waiting ${DELAY_TIME} seconds before cleaning" >> stdout
    sleep ${DELAY_TIME} & wait

    # Remove created containers that haven't managed to start within the DELAY_TIME interval
    rm -f CreatedContainerToClean
    comm -12 CreatedContainerIdList <(docker ps -a -q -f status=created | sort) > CreatedContainerToClean
    if [ -s CreatedContainerToClean ]; then
        echo "=> Start to clean $(cat CreatedContainerToClean | wc -l) created/stuck containers" >> stdout
        if [ $DEBUG ]; then echo "DEBUG: Removing unstarted containers" >> stdout; fi
        docker rm -v $(cat CreatedContainerToClean)
    fi

    # Remove images being used by containers from the delete list again. This prevents the images being pulled from deleting
    CONTAINER_ID_LIST=$(docker ps -aq --no-trunc)
    rm -f ContainerImageIdList
    touch ContainerImageIdList
    for CONTAINER_ID in ${CONTAINER_ID_LIST}; do
        LINE=$(docker inspect ${CONTAINER_ID} | grep "\"Image\": \"\(sha256:\)\?[0-9a-fA-F]\{64\}\"")
        IMAGE_ID=$(echo ${LINE} | awk -F '"' '{print $4}')
        echo "${IMAGE_ID}" >> ContainerImageIdList
    done
    sort ContainerImageIdList -o ContainerImageIdList
    comm -23 ToBeCleanedImageIdList ContainerImageIdList > ToBeCleaned

    # Remove Images
    if [ -s ToBeCleaned ]; then
        echo "=> Start to clean $(cat ToBeCleaned | wc -l) images" >> stdout
        docker rmi $(cat ToBeCleaned) 2>/dev/null
        (( DIFF_LAYER=${ALL_LAYER_NUM}- $(docker images -a | tail -n +2 | wc -l) ))
        (( DIFF_IMG=$(cat ImageIdList | wc -l) - $(docker images | tail -n +2 | wc -l) ))
        if [ ! ${DIFF_LAYER} -gt 0 ]; then
                DIFF_LAYER=0
        fi
        if [ ! ${DIFF_IMG} -gt 0 ]; then
                DIFF_IMG=0
        fi
        echo "=> Done! ${DIFF_IMG} images and ${DIFF_LAYER} layers have been cleaned." >> stdout
    else
        echo "No images need to be cleaned" >> stdout
    fi

    rm -f ToBeCleanedImageIdList ContainerImageIdList ToBeCleaned ImageIdList KeepImageIdList

    # Run forever or exit after the first run depending on the value of $LOOP
    [ "${LOOP}" == "true" ] || break

    # Touch the health check file at the end of a successful loop
    echo "=> Updating health check file" >> stdout
    echo $(date) > healthcheck

    echo "=> Next clean will be started in ${CLEAN_PERIOD} seconds" >> stdout
    sleep ${CLEAN_PERIOD} & wait
done
