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
function login {
	TOKEN_RESP=$(curl --silent "$WEB_URL/login" -H 'Content-Type: application/json' --data-binary '{"id":"administrator","password":"'$PASSWORD'"}')
	TOKEN=$(echo $TOKEN_RESP | jq -r .token)
	touch $CRED_DIR/login
}

login

if [[ -z $TOKEN ]]; then
	log "Unable to log in using user/password"
	exit 1
fi

# See if profile already exists
EXISTING_RULE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/adminrules/core-user-rule)

if [[ "$EXISTING_RULE" == "200" ]]; then
	log "core-user-rule exists..."
else
	curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d '{"name":"core-user-rule","description": "Core User is Admin of all containers","role":"administrator","resources":{"containers":["*"],"images":["*"],"volumes":["*"],"networks":["*"]},"accessors":{"users":["core"]}}' $WEB_URL/adminrules
fi

IMAGE_ASSURANCE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/image_policy)

if [[ "$IMAGE_ASSURANCE" == "200" ]]; then
	log "image-assurance-rule exists..."
else
	curl --silent -H "$HEADER: Bearer $TOKEN" -X POST -d '{"only_registered_images":true,"daily_scan_enabled":true,"daily_scan_time":{"hour":1,"minute":0,"second":0},"average_score_enabled":false,"average_score":7.5,"maximum_score_enabled":false,"maximum_score":8,"author":"system","cves_black_list_enabled":true,"cves_black_list":["CVE-2014-6271","CVE-2014-0160","CVE-2012-1723","CVE-2013-2465","CVE-2016-2842","CVE-2016-2108","CVE-2016-0705"],"allowed_images":[]}' $WEB_URL/image_policy
fi

EXISTING_LABEL=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/settings/labels/production%20approved)

if [[ "$EXISTING_LABEL" == "200" ]]; then
	log "production approved label exists..."
else
	curl --silent -H "Accept: application/json" -H "Content-type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d '{"name": "production approved", "description": "production approved images"}' $WEB_URL/settings/labels
fi

EXISTING_PROFILE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/securityprofiles/Ethos)

if [[ "$EXISTING_PROFILE" == "200" ]]; then
	log "Ethos profile exists..."
else
	curl --silent -H "Accept: application/json" -H "Content-type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d '{"name": "Ethos", "type": "security.profile", "description": "Ethos Default RunTime Profile", "encrypt_all_envs": true}' $WEB_URL/securityprofiles
fi

if [[ ! -d $CRED_DIR/configs ]]; then
    sudo mkdir $CRED_DIR/configs -p
fi

sudo chmod 0755 $CRED_DIR/configs
sudo chown -R $(whoami):$(whoami) $CRED_DIR/configs

curl --silent -H "$HEADER: Bearer $TOKEN" -X GET $WEB_URL/runtime_policy > $CRED_DIR/configs/threat1_mitigation.json

sudo chmod 0755 $CRED_DIR/configs/threat1_mitigation.json

sudo cat $CRED_DIR/configs/threat1_mitigation.json | jq --arg default_security_profile Ethos '. + {default_security_profile: $default_security_profile}' > $CRED_DIR/configs/threat_mitigation.json

sudo chmod 0755 $CRED_DIR/configs/threat_mitigation.json

curl --silent -H "$HEADER: Bearer $TOKEN" -X PUT -d @$CRED_DIR/configs/threat_mitigation.json $WEB_URL/runtime_policy

sudo rm -rf $CRED_DIR/configs

while [[ "$EXISTING_PROFILE" == "200" && "EXISTING_LABEL" == "200" && "$EXISTING_RULE" == "200" && "$IMAGE_ASSURANCE" == "200" ]]; do
	log "Profile and label and rule are still active..."

	if [[ $(expr $(date +%s) - $(date +%s -r $CRED_DIR/login)) -gt 1800 ]]; then
		login
	fi

	EXISTING_RULE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/adminrules/core-user-rule)
	EXISTING_LABEL=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/settings/labels/production%20approved)
	EXISTING_PROFILE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/securityprofiles/Ethos)
  IMAGE_ASSURANCE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/image_policy)

	if [[ "$EXISTING_RULE" == "200" && "EXISTING_LABEL" == "200" && "$EXISTING_PROFILE" == "200" && "IMAGE_ASSURANCE" == "200" ]]; then
		touch $CRED_DIR/healthcheck
	fi

	# Wait for 5 minutes
	sleep 300
done

log "Profile ($EXISTING_PROFILE) or Label ($EXISTING_LABEL) or rule ($EXISTING_RULE) or image assurance ($IMAGE_ASSURANCE) could not be found in Aqua, restarting to ensure compliance..."
exit 1
