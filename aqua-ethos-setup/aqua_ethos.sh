#!/usr/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function log {
	echo $(date -u) "$1" >> $DIR/aqua_ethos.log
}

log "CRED_DIR set to $CRED_DIR"
log "WEB_URL set to $WEB_URL"
log "HEADER set to $HEADER"

if [[ ! -z "$PASSWORD" ]]; then
	log "PASSWORD set to ******"
fi

# Wait for web ui to be active
WEB_ACTIVE=$(curl --silent $WEB_URL)

while [[ -z $WEB_ACTIVE ]]; do
  log "Waiting for web UI to become active"
  WEB_ACTIVE=$(curl --silent $WEB_URL)
  sleep 5;
done

# Get a token from user/pass
TOKEN_RESP=$(curl --silent "$WEB_URL/v1/login" -H 'Content-Type: application/json' --data-binary '{"id":"administrator","password":"'$PASSWORD'"}')
TOKEN=$(echo $TOKEN_RESP | jq -r .token)

if [[ -z $TOKEN ]]; then
	log "Unable to log in using user/password"
	exit 1
fi

# See if profile already exists
EXISTING_RULE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/v1/adminrules/core-user-rule)

if [[ "$EXISTING_RULE" == "200" ]]; then
	log "core-user-rule exists..."
else
	curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d '{"name":"core-user-rule","description": "Core User is Admin of all containers","role":"administrator","resources":{"containers":["*"],"images":["*"],"volumes":["*"],"networks":["*"]},"accessors":{"users":["core"]}}' $WEB_URL/v1/adminrules
fi

EXISTING_PROFILE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/v1/securityprofiles/Ethos)

if [[ "$EXISTING_PROFILE" == "200" ]]; then
	log "Ethos profile exists..."
else
	curl --silent -H "Accept: application/json" -H "Content-type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d '{"name": "Ethos", "type": "security.profile", "description": "Ethos Default RunTime Profile", "encrypt_all_envs": true}' $WEB_URL/v1/securityprofiles
fi

if [[ ! -d $CRED_DIR ]]; then
    sudo mkdir $CRED_DIR -p
fi

sudo chmod 0755 $CRED_DIR
sudo chown -R $(whoami):$(whoami) $CRED_DIR

curl --silent -H "$HEADER: Bearer $TOKEN" -X GET $WEB_URL/v1/runtime_policy > $CRED_DIR/threat1_mitigation.json

sudo chmod 0755 $CRED_DIR/threat1_mitigation.json

sudo cat $CRED_DIR/threat1_mitigation.json | jq --arg default_security_profile Ethos '. + {default_security_profile: $default_security_profile}' > $CRED_DIR/threat_mitigation.json

sudo chmod 0755 $CRED_DIR/threat_mitigation.json

curl --silent -H "$HEADER: Bearer $TOKEN" -X PUT -d @$CRED_DIR/threat_mitigation.json $WEB_URL/v1/runtime_policy

sudo rm $CRED_DIR/*

while [[ "$EXISTING_PROFILE" == "200" && "$EXISTING_RULE" == "200" ]]; do
	log "Profile and rule are still active..."
	TOKEN_RESP=$(curl --silent "$WEB_URL/v1/login" -H 'Content-Type: application/json' --data-binary '{"id":"administrator","password":"'$PASSWORD'"}')
	TOKEN=$(echo $TOKEN_RESP | jq -r .token)

	EXISTING_RULE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/v1/adminrules/core-user-rule)
	EXISTING_PROFILE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/v1/securityprofiles/Ethos)
	
	if [[ "$EXISTING_RULE" == "200" && "$EXISTING_PROFILE" == "200" ]]; then
		touch $CRED_DIR/healthcheck
	fi

	sleep 60
done

log "Profile ($EXISTING_PROFILE) or rule ($EXISTING_RULE) could not be found in Aqua, restarting to ensure compliance..."
exit 1
