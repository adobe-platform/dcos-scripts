#!/usr/bin/bash

EXISTING="$(iptables -w -t nat -L | egrep 'instance-data|169.254.169.254')"

# If existing is not empty, simply sleep
if [[ ! -z $EXISTING ]]; then
	echo $(date -u) "IPTABLES rule already exists. Sleeping..."
	sleep infinity
fi

echo $(date -u) "IPTABLES rule does not exist. Creating..."

export NETWORK="bridge"
export GATEWAY="$(ifconfig docker0 | grep 'inet ' | awk -F: '{print $1}' | awk '{print $2}')"
export INTERFACE="docker0"

iptables -w -t nat -I PREROUTING -p tcp -d 169.254.169.254 --dport 80 -j DNAT --to-destination "$GATEWAY":8080 -i "$INTERFACE"

if [[ $? -eq 0 ]]; then
	echo $(date -u) "IPTABLES rule created. Sleeping..."
	sleep infinity
else
	while [ $? != 0 ]; do
		sleep 5;
		echo $(date -u) "IPTABLES rule creation failed. Retrying..."
		iptables -w -t nat -I PREROUTING -p tcp -d 169.254.169.254 --dport 80 -j DNAT --to-destination "$GATEWAY":8080 -i "$INTERFACE"
	done
fi

echo $(date -u) "IPTABLES rule created. Sleeping..."
sleep infinity
