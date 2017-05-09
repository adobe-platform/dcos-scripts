#!/usr/bin/bash

LOCAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$LOCAL_DIR/config.json"

function log {
	echo $(date -u) "$1" >> $LOCAL_DIR/stdout
}

function setup {
	if [[ -z "$WEB_URL" ]]; then log "WEB_URL environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$HC_DIR" ]]; then log "HC_DIR environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$PASSWORD" ]]; then log "PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$FD_PASSWORD" ]]; then log "FD_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ARTIFACTORY_URL" ]]; then log "ARTIFACTORY_URL environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ARTIFACTORY_USERNAME" ]]; then log "ARTIFACTORY_USERNAME environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ARTIFACTORY_PASSWORD" ]]; then log "ARTIFACTORY_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ECR_URL" ]]; then log "ECR_URL environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ECR_USERNAME" ]]; then log "ECR_USERNAME environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ECR_PASSWORD" ]]; then log "ECR_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$QUALYS_USERNAME" ]]; then log "QUALYS_USERNAME environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$QUALYS_PASSWORD" ]]; then log "QUALYS_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ENCRYPT_ENV_VARS" ]]; then log "ENCRYPT_ENV_VARS environment variable required. Exiting..." && exit 1; fi

	if [[ -z "$HEADER" ]]; then
		log "HEADER environment variable not provided. Setting to 'Authorization'."
		HEADER="Authorization"
	fi

	if [[ -z "$DOCKER_ADMINS" ]]; then
		log "DOCKER_ADMINS environment variable not provided. Setting to 'core'"
		DOCKER_ADMINS="\\\\\"core\\\\\""
	else
		REPLACED_ADMINS="${DOCKER_ADMINS//,/\\\\\",\\\\\"}"
		DOCKER_ADMINS="\\\\\"$REPLACED_ADMINS\\\\\""
	fi

	sudo mkdir -p $HC_DIR
	sudo chown -R $(whoami):$(whoami) $HC_DIR

	ARTIFACTORY_PREFIX=$(echo $ARTIFACTORY_URL | cut -f3 -d'/')
	ECR_PREFIX=$(echo $ECR_URL | cut -f3 -d'/')
	ECR_REGION=$(echo $ECR_URL | cut -f4 -d'.')

	log "WEB_URL set to $WEB_URL"
	log "HC_DIR set to $HC_DIR"
	log "HEADER set to $HEADER"
	log "PASSWORD set to ******"
	log "FD_PASSWORD set to ******"
	log "ARTIFACTORY_URL set to $ARTIFACTORY_URL"
	log "ARTIFACTORY_PREFIX set to $ARTIFACTORY_PREFIX"
	log "ARTIFACTORY_USERNAME set to $ARTIFACTORY_USERNAME"
	log "ARTIFACTORY_PASSWORD set to ******"
	log "ECR_URL set to $ECR_URL"
	log "ECR_PREFIX set to $ECR_PREFIX"
	log "ECR_REGION set to $ECR_REGION"
	log "ECR_USERNAME set to $ECR_USERNAME"
	log "ECR_PASSWORD set to ******"
	log "QUALYS_USERNAME set to $QUALYS_USERNAME"
	log "QUALYS_PASSWORD set to ******"
	log "ENCRYPT_ENV_VARS set to $ENCRYPT_ENV_VARS"
	log "APPROVED_IMAGES set to $APPROVED_IMAGES"
	log "DOCKER_ADMINS set to $DOCKER_ADMINS"
}

function waitForWeb {
	# Wait for web ui to be active
	WEB_ACTIVE=$(curl --silent $WEB_URL)

	while [[ -z $WEB_ACTIVE ]]; do
	  log "Waiting for web UI to become active"
	  WEB_ACTIVE=$(curl --silent $WEB_URL)
	  sleep 5;
	done
}

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

	if [[ -z $TOKEN ]]; then
		log "Unable to log in using user/password"
		exit 1
	fi

	sudo touch $LOCAL_DIR/login
}

function makeGet {
	RES_CODE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/$1)
	echo $RES_CODE
}

function getExistingImages {
	EXISTING_IMAGES=$(curl --silent -H "$HEADER: Bearer $TOKEN" "$WEB_URL/settings/export" --data-binary '["images"]')
}

function getFullBackup {
	EXISTING_IMAGES=$(curl --silent -H "$HEADER: Bearer $TOKEN" "$WEB_URL/settings/export" --data-binary '["registries","settings","policy.images_assurance","policy.threat_mitigation","policy.runtime_profile","policy.user_access_control","policy.container_firewall","images","labels","secrets","applications"]')
}

function replaceConfigs {
	log "Replacing ETH configs in $CONFIG_FILE"

	# Note: using "@" instead of "/" as delimiter because some expressions contain slashes (URLs)
	sed -i.bak "s@ETH_ARTIFACTORY_URL@${ARTIFACTORY_URL}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ARTIFACTORY_PREFIX@${ARTIFACTORY_PREFIX}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ARTIFACTORY_USERNAME@${ARTIFACTORY_USERNAME}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ARTIFACTORY_PASSWORD@${ARTIFACTORY_PASSWORD}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_QUALYS_USERNAME@${QUALYS_USERNAME}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_QUALYS_PASSWORD@${QUALYS_PASSWORD}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_DOCKER_ADMINS@${DOCKER_ADMINS}@g" "$CONFIG_FILE"
	
	sed -i.bak "s@ETH_ECR_URL@${ECR_URL}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_PREFIX@${ECR_PREFIX}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_REGION@${ECR_REGION}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_USERNAME@${ECR_USERNAME}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_PASSWORD@${ECR_PASSWORD}@g" "$CONFIG_FILE"

	# Update the encryption mode
	# cat $CONFIG_FILE | jq -r '. | select(policies.security_profiles[].name=="Ethos") | .encrypt_all_envs |= '$ENCRYPT_ENV_VARS''
	cat $CONFIG_FILE | jq '.policies.security_profiles[0].encrypt_all_envs = '$ENCRYPT_ENV_VARS'' > $CONFIG_FILE.bak
	mv $CONFIG_FILE.bak $CONFIG_FILE

	# Empty out the images array in case it already exists
	log "Clearing the old images array"
	cat $CONFIG_FILE | jq '.images |= []' > $CONFIG_FILE.bak
	mv $CONFIG_FILE.bak $CONFIG_FILE

	log "Adding approved images: $APPROVED_IMAGES"
	IFS=',' read -ra ADDR <<< "$APPROVED_IMAGES"
	for IMAGE in "${ADDR[@]}"; do
		if [[ $EXISTING_IMAGES == *"$IMAGE"* ]]; then
			log "Image already exists. Skipping: $IMAGE"
			continue;
		fi

		REPO=$(echo $IMAGE | cut -d':' -f1)

	    cat $CONFIG_FILE | jq '.images |= .+ [{"Name":"'$IMAGE'","Repository":"'$REPO'","PolicyName":"","Registry":"artifactory-admin","Labels":["production approved"]}]' > $CONFIG_FILE.bak
	    mv $CONFIG_FILE.bak $CONFIG_FILE
	done
}

setup
waitForWeb
login
getExistingImages
replaceConfigs

# Import the config file
curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d "@$CONFIG_FILE" "$WEB_URL/settings/import"

# Add Flight Director User
FD_USER=$(makeGet users/flight-director)

if [[ "$FD_USER" == "200" ]]; then
		echo "200"
	else
		curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d '{"id": "flight-director","name": "Flight Director","password": "'$FD_PASSWORD'","email": "","admin":true,"role":"administrator"}' $WEB_URL/users
fi

# HEALTHCHECK
function healthcheck {
	if [[ $(expr $(date +%s) - $(date +%s -r $LOCAL_DIR/login)) -gt 1800 ]]; then
		login
	fi

	EXISTING_RULE=$(makeGet adminrules/ethos)
	EXISTING_PROFILE=$(makeGet securityprofiles/Ethos)
	EXISTING_ARTIFACTORY=$(makeGet "registries/artifactory-admin")

	if [[ "$EXISTING_RULE" == "200" &&
		  "$EXISTING_PROFILE" == "200" &&
		  "$EXISTING_ARTIFACTORY" == "200" ]]; then
		sudo touch $HC_DIR/healthcheck
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

MESSAGE="Profile ($EXISTING_PROFILE) or rule ($EXISTING_RULE) or Artifactory URL ($EXISTING_ARTIFACTORY)"

log "$MESSAGE could not be found in Aqua, restarting in 30 seconds to ensure compliance..."
# Avoids rate limits if the service keeps dying
sleep 30
exit 1
