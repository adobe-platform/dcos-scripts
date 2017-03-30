#!/usr/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


function log {
	echo $(date -u) "$1" >> $DIR/aqua_ethos.log
}

if [[ -z "$CRED_DIR" ]]; then
	log "CRED_DIR environment variable required. Exiting..."
	exit 1
fi

if [[ -z "$WEB_URL" ]]; then
	log "WEB_URL environment variable required. Exiting..."
	exit 1
fi

if [[ -z "$PASSWORD" ]]; then
	log "PASSWORD environment variable required. Exiting..."
	exit 1
fi

if [[ ! -z "$ARTIFACTORY_URL" ]]; then
	if [[ -z "$ARTIFACTORY_USERNAME" ]]; then
		log "Artifactory URL set but no ARTIFACTORY_USERNAME provided. Exiting..."
		exit 1
	fi

	if [[ -z "$ARTIFACTORY_PASSWORD" ]]; then
		log "Artifactory URL set but no ARTIFACTORY_PASSWORD provided. Exiting..."
		exit 1
	fi
fi

if [[ ! -z "$QUALYS_URL" ]]; then
	if [[ -z "$QUALYS_USERNAME" ]]; then
		log "Qualys URL set but no QUALYS_USERNAME provided. Exiting..."
		exit 1
	fi

	if [[ -z "$QUALYS_PASSWORD" ]]; then
		log "Qualys URL set but no QUALYS_PASSWORD provided. Exiting..."
		exit 1
	fi
fi

if [[ -z "$HEADER" ]]; then
	log "HEADER environment variable not provided. Setting to 'Authorization'."
	HEADER="Authorization"
fi

if [[ -z "$ENC_ENV_VARS" ]]; then
	log "ENC_ENV_VARS environment variable not provided. Setting to 'true'."
	ENC_ENV_VARS="true"
fi

aquaToken=""
function aqua-curl() {
  # sometimes Aqua just doesn't respond
  tries=1
  maxTries=120
  while [ -z $aquaToken ] && [ $tries -lt $maxTries ]; do
    aquaToken=$(curl -s -H 'Content-Type: application/json' --data-binary '{"id":"administrator","password":"'$PASSWORD'"}' $aquaURL/api/v1/login | jq -r .token)
    tries=$(expr $tries + 1)
    sleep 1
  done

  if [ -z $aquaToken ]; then
    echo "Could not authenticate with Aqua! You can try building again or contact an admin."
    exit 1
  fi

  curl -s -H "aqua-auth: Bearer $aquaToken" $@
}

log "CRED_DIR set to $CRED_DIR"
log "WEB_URL set to $WEB_URL"
log "HEADER set to $HEADER"
log "PASSWORD set to ******"

if [[ ! -z "$ARTIFACTORY_URL" ]]; then
	log "ARTIFACTORY_URL set to $ARTIFACTORY_URL"
	log "ARTIFACTORY_USERNAME set to $ARTIFACTORY_USERNAME"
	log "ARTIFACTORY_PASSWORD set to ******"
fi

if [[ ! -z "$QUALYS_URL" ]]; then
	log "QUALYS_URL set to $QUALYS_URL"
	log "QUALYS_USERNAME set to $QUALYS_USERNAME"
	log "QUALYS_PASSWORD set to ******"
fi

# Create the cred dir
if [[ ! -d $CRED_DIR ]]; then
    sudo mkdir $CRED_DIR -p
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

	if [[ -z "$TOKEN_RESP" || "$?" != "0" ]]; then
		log "$TOKEN_RESP"
		log "Unable to login. Exiting..."
		exit 1
	fi

	TOKEN=$(echo $TOKEN_RESP | jq -r .token)

	if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
		log "Invalid token returned from login. Exiting..."
		exit 1
	fi

	sudo touch $CRED_DIR/login
}

login

if [[ -z $TOKEN ]]; then
	log "Unable to log in using user/password"
	exit 1
fi

function makeGet {
	if [[ "$2" == "body" ]]; then
		RES_BODY=$(curl --silent -H "$HEADER: Bearer $TOKEN" $WEB_URL/$1)
		echo $RES_BODY
	else
		RES_CODE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/$1)
		echo $RES_CODE
	fi
}

function makePost {
	curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d "$2" "$WEB_URL/$1"

	if [[ "$?" != "0" ]]; then
		log "Error sending POST to Aqua"
		exit 1
	fi
}

function makePut {
	curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X PUT -d "$2" "$WEB_URL/$1"

	if [[ "$?" != "0" ]]; then
		log "Error sending PUT to Aqua"
		exit 1
	fi
}

function get_gateway_id {
    GATEWAY=$(curl --silent -H "$HEADER: Bearer $TOKEN" -X GET $WEB_URL/servers| jq "[.[].id]")
}

function create_label_if_does_not_exist {
    CREATE_LABEL=$1
    ENCODED_LABEL=${CREATE_LABEL// /%20}
    JQ_LABEL_FILTER='.[] | select([.name=="'$CREATE_LABEL'"] | any) | .name'
    RESPONSE_LABEL=$(curl --silent -H "$HEADER: Bearer $TOKEN" -X GET $WEB_URL/settings/labels | jq "$JQ_LABEL_FILTER")
    if [ -n "$RESPONSE_LABEL" ]; then
        log "Label \"$CREATE_LABEL\" already exists."
    else
        log "Label \"$CREATE_LABEL\" does not exist, creating it."
        NEW_LABEL=$(curl --silent -H "$HEADER: Bearer $TOKEN" -X POST $WEB_URL/settings/labels -d "{ \"name\": \"$CREATE_LABEL\" }" | jq ".name")
        if [ "$NEW_LABEL"="$CREATE_LABEL" ]; then
            log "Label \"$CREATE_LABEL\" created successfully."
        fi
    fi

}


function token_has_label {
    TOKEN_NAME=$1
    TOKEN_LABEL=$2
    log "Checking whether token with name \"$TOKEN_NAME\" exists and has the label \"$TOKEN_LABEL\"."

    JQ_FILTER+='.[]  | select([.logicalname == "'$TOKEN_NAME'"] | any)| select([.allowed_labels] | any) | select([.allowed_labels[] == "'$TOKEN_LABEL'"] | any) | .command.default '
    BATCH_TOKEN_VALUE=$(curl --silent -H "$HEADER: Bearer $TOKEN" -X GET $WEB_URL/hostsbatch \
      | jq "$JQ_FILTER")

    if [[ -z "$BATCH_TOKEN_VALUE" ]]; then
        log "Token \"$TOKEN_NAME\" does not exist with label \"$TOKEN_LABEL\"."
        return 1
    else
        log "Token \"$TOKEN_NAME\" exists with label \"$TOKEN_LABEL\".  Command for agent installs is \"$BATCH_TOKEN_VALUE\"."
        return 0
    fi
}

function add_batch_install_token_with_label {

    ADD_TOKEN_NAME=$1
    ADD_TOKEN_VALUE=$2
    SET_TOKEN_LABEL=$3

    get_gateway_id

    create_label_if_does_not_exist "$SET_TOKEN_LABEL"

    HOSTBATCH_RULE=$(curl --silent -H "$HEADER: Bearer $TOKEN" -X GET $WEB_URL/hostsbatch | jq ".[] |.command|.default"|grep "production-token-value" && echo "200")
    HOSTBATCH_RULE_FINAL=$(echo "${HOSTBATCH_RULE:(-3)}")

    if !(token_has_label "$ADD_TOKEN_NAME" "$SET_TOKEN_LABEL"); then
        log "Creating token named \"$ADD_TOKEN_NAME\" with label \"$SET_TOKEN_LABEL\" and token \"$ADD_TOKEN_VALUE\"."
        TOKEN_PAYLOAD='{"logicalname":"'$ADD_TOKEN_NAME'","token":"'$ADD_TOKEN_VALUE'","description":"Batch install for production hosts.","enforce":true,"allowed_labels":["'$SET_TOKEN_LABEL'"],"allowed_registries":["Docker Hub"],"gateways":'$GATEWAY'}'
        log "$TOKEN_PAYLOAD"
        BATCH_TOKEN_RESPONSE=$(curl --silent -H "$HEADER: Bearer $TOKEN" -X POST \
           -d "$TOKEN_PAYLOAD" \
            $WEB_URL/hostsbatch)
        log "$BATCH_TOKEN_RESPONSE"
        log "Validating that \"$ADD_TOKEN_NAME\" has been created."
        if !(token_has_label "$ADD_TOKEN_NAME" "$SET_TOKEN_LABEL"); then
            log "Token does not have matching label."
            log "--- Fail ---"
            exit 1
        fi
    fi

}

add_batch_install_token_with_label "production-token" "production-token-value" "production approved"

#scan Admin containers

function url-encode-repo() {
  imageFullname=$1
  echo $imageFullname | sed -e 's|/|%2F|g'
}
image=kran-test-2:bar
    AQUA=$WEB_URL/scanner/registry/adobe-artifactory/image/$(url-encode-repo $image)
    reqRes=$(aqua-curl -X POST "$AQUA/scan")
    if [ "$(echo $reqRes | jq .code)" = "500" ]; then
        echo "Failed to trigger scan! Please contact an admin."
        echo $reqRes | jq .
        exit 1
fi


# See if rule already exists
EXISTING_RULE=$(makeGet adminrules/core-user-rule)

if [[ "$EXISTING_RULE" == "200" ]]; then
	log "core-user-rule exists..."
else
	makePost "adminrules" '{"name":"core-user-rule","description": "Core User is Admin of all containers","role":"administrator","resources":{"containers":["*"],"images":["*"],"volumes":["*"],"networks":["*"]},"accessors":{"users":["core"]}}'
fi

# See if aqua qualys integration already exists
EXISTING_QUALYS=$(makeGet settings/integrations/qualys)

PROFILE_BODY_QUALYS="{\"enabled\": \"true\", \"url\": $QUALYS_URL, \"username\": $QUALYS_USERNAME, \"password\": $QUALYS_PASSWORD}"

if [[ "$EXISTING_QUALYS" == "200" ]]; then
	log "qualys integration exists..."
else
	makePost "$PROFILE_BODY_QUALYS"
fi

# See if profile already exists
EXISTING_PROFILE=$(makeGet securityprofiles/Ethos)

# TODO: check for same env var enc status

PROFILE_BODY="{\"name\": \"Ethos\", \"type\": \"security.profile\", \"description\": \"Ethos Default RunTime Profile\", \"encrypt_all_envs\": $ENC_ENV_VARS}"

if [[ "$EXISTING_PROFILE" == "200" ]]; then
	log "Ethos profile exists..."

	PROFILE_CONTENTS=$(makeGet securityprofiles/Ethos body)

	ENC_ENABLED=$(echo "$PROFILE_CONTENTS" | jq '.encrypt_all_envs')

	if [[ "$ENC_ENABLED" != "$ENC_ENV_VARS" ]]; then
		log "WARNING: Ethos profile does not match ENC_ENV_VARS setting."
		# makePut "securityprofiles" "$PROFILE_BODY"
	else
		log "Ethos profile matches ENC_ENV_VARS setting..."
	fi
else
	makePost "securityprofiles" "$PROFILE_BODY"
fi

# See if artifactory integration already exists
if [[ ! -z "$ARTIFACTORY_URL" ]]; then
	log "ARTIFACTORY_URL set. Checking artifactory configs..."

	EXISTING_ARTIFACTORY=$(makeGet "registries/artifactory-test")

	if [[ "$EXISTING_ARTIFACTORY" == "200" ]]; then
		log "Artifactory integration exists..."
	else
		makePost "registries" '{"prefixes": [], "auto_pull": false, "auto_pull_time": "03:00", "auto_pull_max": 100, "name": "artifactory-test", "type": "ART", "webhook": {"enabled": false, "url": "", "auth_token": ""}, "url": "'$ARTIFACTORY_URL'", "username": "'$ARTIFACTORY_USERNAME'", "password": "'$ARTIFACTORY_PASSWORD'"}'
	fi
fi

if [[ ! -d $CRED_DIR/configs ]]; then
    sudo mkdir $CRED_DIR/configs -p
fi

sudo chmod 0755 $CRED_DIR/configs
sudo chown -R $(whoami):$(whoami) $CRED_DIR/configs

# Obtain the runtime policy and set as ethos default
curl --silent -H "$HEADER: Bearer $TOKEN" -X GET $WEB_URL/runtime_policy > $CRED_DIR/configs/threat1_mitigation.json
sudo chmod 0755 $CRED_DIR/configs/threat1_mitigation.json
sudo cat $CRED_DIR/configs/threat1_mitigation.json | jq --arg default_security_profile Ethos '. + {default_security_profile: $default_security_profile}' > $CRED_DIR/configs/threat_mitigation.json
sudo chmod 0755 $CRED_DIR/configs/threat_mitigation.json
curl --silent -H "$HEADER: Bearer $TOKEN" -X PUT -d @$CRED_DIR/configs/threat_mitigation.json $WEB_URL/runtime_policy
sudo rm -rf $CRED_DIR/configs

# HEALTHCHECK
function healthcheck {
	if [[ $(expr $(date +%s) - $(date +%s -r $CRED_DIR/login)) -gt 1800 ]]; then
		login
	fi

	EXISTING_RULE=$(makeGet adminrules/core-user-rule)
	EXISTING_PROFILE=$(makeGet securityprofiles/Ethos)

	if [[ ! -z "$QUALYS_URL" ]]; then
		EXISTING_QUALYS=$(makeGet settings/integrations/qualys)
	else
		EXISTING_QUALYS="200"	# Force pass test if not using qualys integration
	fi

	if [[ ! -z "$ARTIFACTORY_URL" ]]; then
		EXISTING_ARTIFACTORY=$(makeGet "registries/artifactory-test")
	else
		EXISTING_ARTIFACTORY="200"	# Force pass test if not using artifactory integration
	fi

	if [[ "$EXISTING_RULE" == "200" &&
		  "$EXISTING_PROFILE" == "200" &&
		  "$EXISTING_QUALYS" == "200" &&
		  "$EXISTING_ARTIFACTORY" == "200" ]]; then
		sudo touch $CRED_DIR/healthcheck
		echo "200"
	else
		echo "400"
	fi
}

while [ $(healthcheck) = "200" ]; do
	log "Rules are still active..."

	# Wait for 5 minutes
	sleep 300
done

MESSAGE="Profile ($EXISTING_PROFILE) or rule ($EXISTING_RULE)"

if [[ ! -z "$QUALYS_URL" ]]; then
	MESSAGE="$MESSAGE or Qualys URL ($EXISTING_QUALYS)"
fi

if [[ ! -z "$ARTIFACTORY_URL" ]]; then
	MESSAGE="$MESSAGE or Artifactory URL ($EXISTING_ARTIFACTORY)"
fi

log "$MESSAGE could not be found in Aqua, restarting to ensure compliance..."
exit 1
