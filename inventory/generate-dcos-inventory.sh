#!/bin/bash

inventory_file=$1

query_nodes() {
	local dcos_url auth_token
	dcos_url=$(dcos config show core.dcos_url)
	auth_token=$(dcos config show core.dcos_acs_token)
	http GET "${dcos_url}/system/health/v1/nodes" "Authorization:token=$auth_token"
}

filter_nodes_by_role() {
	nodes=$1
	role=$2
	echo "$nodes" | jq -r '.nodes[] | select(.role == "'"$role"'").host_ip'
}

nodes=$(query_nodes)
masters=$(filter_nodes_by_role "$nodes" "master")
agents=$(filter_nodes_by_role "$nodes" "agent")

cat <<- EOF > "$inventory_file"
	[cluster:children]
	masters
	agents

	[masters]
	$masters

	[agents]
	$agents
EOF
