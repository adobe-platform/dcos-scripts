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
	if [[ -z "$AUDITOR_PASSWORD" ]]; then log "AUDITOR_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$SCANNER_PASSWORD" ]]; then log "SCANNER_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ARTIFACTORY_URL" ]]; then log "ARTIFACTORY_URL environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ARTIFACTORY_USERNAME" ]]; then log "ARTIFACTORY_USERNAME environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ARTIFACTORY_PASSWORD" ]]; then log "ARTIFACTORY_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ECR_URL" ]]; then log "ECR_URL environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ECR_USERNAME" ]]; then log "ECR_USERNAME environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ECR_PASSWORD" ]]; then log "ECR_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$QUALYS_USERNAME" ]]; then log "QUALYS_USERNAME environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$QUALYS_PASSWORD" ]]; then log "QUALYS_PASSWORD environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$SPLUNK_URL" ]]; then log "SPLUNK_URL environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$SPLUNK_INDEX" ]]; then log "SPLUNK_INDEX environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$SPLUNK_TOKEN" ]]; then log "SPLUNK_TOKEN environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$ENCRYPT_ENV_VARS" ]]; then log "ENCRYPT_ENV_VARS environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$STATIC_BINARIES_PROTECTION" ]]; then log "STATIC_BINARIES_PROTECTION environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$DAILY_SCAN_ENABLED" ]]; then log "DAILY_SCAN_ENABLED environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$FORK_GUARD_LIMIT" ]]; then log "FORK_GUARD_LIMIT environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$CLUSTER_NAME" ]]; then log "CLUSTER_NAME environment variable required. Exiting..." && exit 1; fi
	if [[ -z "$AQUA_WEBHOOK_ENDPOINT" ]]; then log "AQUA_WEBHOOK_ENDPOINT variable not provided. No webhook will be configured in aqua for daily CVEs"; fi


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

	mkdir -p $HC_DIR
	chown -R $(whoami):$(whoami) $HC_DIR

	ARTIFACTORY_PREFIX=$(echo $ARTIFACTORY_URL | cut -f3 -d'/')
	ECR_PREFIX=$(echo $ECR_URL | cut -f3 -d'/')
	ECR_REGION=$(echo $ECR_URL | cut -f4 -d'.')

	# Check for the optional MC Artifactory URL
	if [[ ! -z "$ARTIFACTORY_URL_MC" ]]; then
		if [[ -z "$ARTIFACTORY_USERNAME_MC" ]]; then log "ARTIFACTORY_USERNAME_MC environment variable required when using ARTIFACTORY_URL_MC. Exiting..." && exit 1; fi
		if [[ -z "$ARTIFACTORY_PASSWORD_MC" ]]; then log "ARTIFACTORY_PASSWORD_MC environment variable required when using ARTIFACTORY_URL_MC. Exiting..." && exit 1; fi

		ARTIFACTORY_PREFIX_MC=$(echo $ARTIFACTORY_URL_MC | cut -f3 -d'/')
	fi

	# Set KMS configs to empty strings if not set
	if [[ -z "$KMS_USERNAME" ]]; then KMS_USERNAME=""; fi
	if [[ -z "$KMS_PASSWORD" ]]; then KMS_PASSWORD=""; fi

	log "WEB_URL set to $WEB_URL"
	log "HC_DIR set to $HC_DIR"
	log "HEADER set to $HEADER"
	log "PASSWORD set to ******"
	log "FD_PASSWORD set to ******"
	if [[ ! -z "$DATADOG_PASSWORD" ]]; then log "DATADOG_PASSWORD set to ******"; fi
	log "AUDITOR_PASSWORD set to ******"
	log "SCANNER_PASSWORD set to ******"
	log "ARTIFACTORY_URL set to $ARTIFACTORY_URL"
	log "ARTIFACTORY_PREFIX set to $ARTIFACTORY_PREFIX"
	log "ARTIFACTORY_USERNAME set to $ARTIFACTORY_USERNAME"
	log "ARTIFACTORY_PASSWORD set to ******"
	log "ECR_URL set to $ECR_URL"
	log "ECR_PREFIX set to $ECR_PREFIX"
	log "ECR_REGION set to $ECR_REGION"
	log "ECR_USERNAME set to $ECR_USERNAME"
	log "ECR_PASSWORD set to ******"
	log "KMS_USERNAME set to $KMS_USERNAME"
	log "KMS_PASSWORD set to ******"
	log "QUALYS_USERNAME set to $QUALYS_USERNAME"
	log "QUALYS_PASSWORD set to ******"
	log "SPLUNK_URL set to $SPLUNK_URL"
	log "SPLUNK_INDEX set to $SPLUNK_INDEX"
	log "SPLUNK_TOKEN set to ******"
	log "ENCRYPT_ENV_VARS set to $ENCRYPT_ENV_VARS"
	log "DAILY_SCAN_ENABLED set to $DAILY_SCAN_ENABLED"
	log "FORK_GUARD_LIMIT set to $FORK_GUARD_LIMIT"
	log "CLUSTER_NAME set to $CLUSTER_NAME"
	log "APPROVED_IMAGES set to $APPROVED_IMAGES"
	log "DOCKER_ADMINS set to $DOCKER_ADMINS"
	log "AQUA_WEBHOOK_ENDPOINT set to $AQUA_WEBHOOK_ENDPOINT"

	if [[ ! -z "$ARTIFACTORY_URL_MC" ]]; then
		log "ARTIFACTORY_URL_MC set to $ARTIFACTORY_URL_MC"
		log "ARTIFACTORY_PREFIX_MC set to $ARTIFACTORY_PREFIX_MC"
		log "ARTIFACTORY_USERNAME_MC set to $ARTIFACTORY_USERNAME_MC"
		log "ARTIFACTORY_PASSWORD_MC set to ******"
	fi

	if [[ ! -z "$DELETE_DOCKER_HUB" ]]; then
		log "DELETE_DOCKER_HUB set to $DELETE_DOCKER_HUB"
	fi

	if [[ ! -z "$ECR_URL_DEV" ]]; then
		log "ECR_URL_DEV set to $ECR_URL_DEV"
		log "ECR_USERNAME_DEV set to $ECR_USERNAME_DEV"
	fi
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

	touch $LOCAL_DIR/login
}

function makeGet {
	RES_CODE=$(curl --write-out %{http_code} --silent --output /dev/null -H "$HEADER: Bearer $TOKEN" $WEB_URL/$1)
	echo $RES_CODE
}

function makePost {
	curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d "$2" "$WEB_URL/$1"

	if [[ "$?" != "0" ]]; then
		log "Error sending POST to Aqua"
		exit 1
	fi
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
	sed -i.bak "s@ETH_SPLUNK_URL@${SPLUNK_URL}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_SPLUNK_INDEX@${SPLUNK_INDEX}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_SPLUNK_TOKEN@${SPLUNK_TOKEN}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_DOCKER_ADMINS@${DOCKER_ADMINS}@g" "$CONFIG_FILE"

	sed -i.bak "s@ETH_ECR_URL@${ECR_URL}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_PREFIX@${ECR_PREFIX}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_REGION@${ECR_REGION}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_USERNAME@${ECR_USERNAME}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_ECR_PASSWORD@${ECR_PASSWORD}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_KMS_USERNAME@${KMS_USERNAME}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_KMS_PASSWORD@${KMS_PASSWORD}@g" "$CONFIG_FILE"

	if [[ ! -z "$AQUA_WEBHOOK_ENDPOINT" ]]; then
		AQUA_WEBHOOK_ENDPOINT_PROVIDED=true
		WEBHOOK_URL="$AQUA_WEBHOOK_ENDPOINT?token=$SPLUNK_TOKEN\&index=ethos_aqua\&cluster=$CLUSTER_NAME"
	else
		AQUA_WEBHOOK_ENDPOINT_PROVIDED=false
		WEBHOOK_URL=""
	fi

	sed -i.bak "s@ETH_AQUA_WEBHOOK_ENDPOINT_PROVIDED@${AQUA_WEBHOOK_ENDPOINT_PROVIDED}@g" "$CONFIG_FILE"
	sed -i.bak "s@ETH_AQUA_WEBHOOK_ENDPOINT@${WEBHOOK_URL}@g" "$CONFIG_FILE"


	PREFIXES_EXTRA=""

	if [[ ! -z "$ARTIFACTORY_URL_MC" ]]; then
		# Add the new artifactory to the whitelist
		PREFIXES_EXTRA=",\\\\\"$ARTIFACTORY_PREFIX_MC\\\\\""

		sed -i.bak "s@ETH_MC_ARTIFACTORY_URL@${ARTIFACTORY_URL_MC}@g" "$CONFIG_FILE"
		sed -i.bak "s@ETH_MC_ARTIFACTORY_PREFIX@${ARTIFACTORY_PREFIX_MC}@g" "$CONFIG_FILE"
		sed -i.bak "s@ETH_MC_ARTIFACTORY_USERNAME@${ARTIFACTORY_USERNAME_MC}@g" "$CONFIG_FILE"
		sed -i.bak "s@ETH_MC_ARTIFACTORY_PASSWORD@${ARTIFACTORY_PASSWORD_MC}@g" "$CONFIG_FILE"
	else
		# Remove the MC artifactory section
		cat $CONFIG_FILE | jq 'del(.integration.registries[3])' > $CONFIG_FILE.bak
		mv $CONFIG_FILE.bak $CONFIG_FILE
	fi

	# Update or remove the DEV ECR
	if [[ ! -z "$ECR_URL_DEV" && ! -z "$ECR_USERNAME_DEV" && ! -z "$ECR_PASSWORD_DEV" ]]; then
		ECR_PREFIX_DEV=$(echo $ECR_URL_DEV | cut -f3 -d'/')
		ECR_REGION_DEV=$(echo $ECR_URL_DEV | cut -f4 -d'.')

		sed -i.bak "s@ETH_ECR_DEV_URL@${ECR_URL_DEV}@g" "$CONFIG_FILE"
		sed -i.bak "s@ETH_ECR_DEV_PREFIX@${ECR_PREFIX_DEV}@g" "$CONFIG_FILE"
		sed -i.bak "s@ETH_ECR_DEV_REGION@${ECR_REGION_DEV}@g" "$CONFIG_FILE"
		sed -i.bak "s@ETH_ECR_DEV_USERNAME@${ECR_USERNAME_DEV}@g" "$CONFIG_FILE"
		sed -i.bak "s@ETH_ECR_DEV_PASSWORD@${ECR_PASSWORD_DEV}@g" "$CONFIG_FILE"
	else
		cat $CONFIG_FILE | jq 'del(.integration.registries[2])' > $CONFIG_FILE.bak
		mv $CONFIG_FILE.bak $CONFIG_FILE
	fi

	if [[ "$DELETE_DOCKER_HUB" == true ]]; then
		# Remove the Docker Hub section
		curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X DELETE $WEB_URL/registries/Docker%20Hub
		curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X DELETE $WEB_URL/registries/hub.docker.io
	else
		#Add DockerHub Prefix
		PREFIXES_EXTRA="$PREFIXES_EXTRA,\\\\\"adobeplatform\\\\\",\\\\\"behance\\\\\",\\\\\"index.docker.io\\\\\""
	fi

	# Add the extra prefixes if any
	sed -i.bak "s@ETH_PREFIXES_EXTRA@${PREFIXES_EXTRA}@g" "$CONFIG_FILE"

	# Update the encryption mode
	# cat $CONFIG_FILE | jq -r '. | select(policies.security_profiles[].name=="Ethos") | .encrypt_all_envs |= '$ENCRYPT_ENV_VARS''
	cat $CONFIG_FILE | jq '.policies.security_profiles[0].encrypt_all_envs = '$ENCRYPT_ENV_VARS'' > $CONFIG_FILE.bak
	mv $CONFIG_FILE.bak $CONFIG_FILE
	cat $CONFIG_FILE | jq '.policies.security_profiles[1].encrypt_all_envs = '$ENCRYPT_ENV_VARS'' > $CONFIG_FILE.bak
	mv $CONFIG_FILE.bak $CONFIG_FILE
	cat $CONFIG_FILE | jq '.policies.security_profiles[0].static_binaries_protection = '$STATIC_BINARIES_PROTECTION'' > $CONFIG_FILE.bak
	mv $CONFIG_FILE.bak $CONFIG_FILE

	# Update the daily scan
	sed -i.bak "s@ETH_DAILY_SCAN@${DAILY_SCAN_ENABLED}@g" "$CONFIG_FILE"
	
    # Update the fork guard limit process
	sed -i.bak "s@ETH_FORK_GUARD_LIMIT@${FORK_GUARD_LIMIT}@g" "$CONFIG_FILE"

	cat $CONFIG_FILE | jq '.policies.threat_mitigation[0].fork_guard_process_limit = '$FORK_GUARD_LIMIT'' > $CONFIG_FILE.bak
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

	    cat $CONFIG_FILE | jq '.images |= .+ [{"Name":"'$IMAGE'","Repository":"'$REPO'","PolicyName":"","Registry":"$ARTIFACTORY_PREFIX","Labels":["production_approved"]}]' > $CONFIG_FILE.bak
	    mv $CONFIG_FILE.bak $CONFIG_FILE
	done

	if [[ "$DISABLE_NET_RAW" == true ]]; then
		cat $CONFIG_FILE | jq '.policies.security_profiles[0].drop_capabilities = ["NET_RAW"]' > $CONFIG_FILE.bak
		mv $CONFIG_FILE.bak $CONFIG_FILE
	fi
}

setup
waitForWeb
login
getExistingImages
replaceConfigs

# Import the config file
curl --silent -H "Content-Type: application/json" -H "$HEADER: Bearer $TOKEN" -X POST -d "@$CONFIG_FILE" "$WEB_URL/settings/import"

# Add Aqua UI Users
createUser()
{

AQUA_USER=$1
AQUA_ID=$2
AQUA_NAME=$3
AQUA_PASSWORD=$4
AQUA_ROLE=$5
USER=$(makeGet users/$AQUA_USER)

if [[ "$USER" == "200" ]]; then
   echo "200"
 else
   makePost "users" '{"id": "'$AQUA_ID'","name": "'$AQUA_NAME'","password": "'$AQUA_PASSWORD'","email": "","admin":true,"role":"'$AQUA_ROLE'"}'
fi

}

if [[ ! -z "$DATADOG_PASSWORD" ]]; then
	createUser "datadog" "datadog" "Datadog" "$DATADOG_PASSWORD" "administrator"
fi
createUser "auditor" "auditor" "Auditor" "$AUDITOR_PASSWORD" "auditor"
createUser "flight-director" "flight-director" "FlightDirector" "$FD_PASSWORD" "administrator"
createUser "scanner" "scanner" "Scanner" "$SCANNER_PASSWORD" "scanner"

# HEALTHCHECK
function healthcheck {
	if [[ $(expr $(date +%s) - $(date +%s -r $LOCAL_DIR/login)) -gt 1800 ]]; then
		login
	fi

	EXISTING_RULE=$(makeGet adminrules/ethos)
	EXISTING_PROFILE=$(makeGet securityprofiles/Ethos)
	EXISTING_ARTIFACTORY=$(makeGet "registries/$ARTIFACTORY_PREFIX")

	if [[ "$EXISTING_RULE" == "200" &&
		  "$EXISTING_PROFILE" == "200" &&
		  "$EXISTING_ARTIFACTORY" == "200" ]]; then
		touch $HC_DIR/healthcheck
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
