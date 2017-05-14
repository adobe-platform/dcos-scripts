#!/usr/bin/bash

if [[ -z "$INTERVAL" ]]; then
	INTERVAL=30
fi

while [[ true ]]; do
	sudo ps aux > ps_aux
	sudo systemctl > systemctl
	sudo cat /etc/os-release > os_release
	sudo ss -s > ss
	sudo ls -lah /home/core > ls_home
	sudo docker ps > docker_ps
	sudo docker info > docker_info
	sudo docker version > docker_version

	sleep $INTERVAL
done
