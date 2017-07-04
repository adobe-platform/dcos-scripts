# DC/OS Ansible Dynamic Inventory

Generates an inventory file for a DC/OS cluster.

## Usage

```bash
brew install httpie
dcos config set core.dcos_url https://your.dcos.cluster.url
dcos auth login
./generate-dcos-inventory.sh inventory.ini
ANSIBLE_HOST_KEY_CHECKING=False ansible cluster -u core -i inventory.ini -b -m raw -a 'hostname'
```

## Groups

- `cluster`: All nodes in DC/OS cluster
- `masters`: Mesos masters
- `agents`: Mesos agents
