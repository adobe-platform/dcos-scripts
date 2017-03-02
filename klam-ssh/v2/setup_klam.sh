#!/bin/bash -xe

echo "-------Beginning klam-ssh setup-------"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function usage {
    echo "usage: $0 [options]"
    echo "       -r|--region                 The AWS region"
    echo "       -o|--role-name              The AWS IAM role name"
    echo "       -e|--encryption-id          The encryption ID"
    echo "       -k|--encryption-key         The encryption key"
    echo "       -p|--key-location-prefix    The encryption ID"
    echo "       -i|--image                  The KLAM SSH docker image"
    echo "       -h|--help                Show this message"
    exit 1
}

if [[ "$1" == '--help' || "$1" == '-h' ]]; then
  usage
fi

while [[ $# > 1 ]]
do
key="$1"

case $key in
    -r|--region)
    REGION="$2"
    shift;;
    -o|--role-name)
    ROLE_NAME="$2"
    shift;;
    -e|--encryption-id)
    ENCRYPTION_ID="$2"
    shift;;
    -k|--encryption-key)
    ENCRYPTION_KEY="$2"
    shift;;
    -p|--key-location-prefix)
    KEY_LOCATION_PREFIX="$2"
    shift;;
    -i|--image)
    IMAGE="$2"
    shift;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

if [[ -z $REGION || -z $ROLE_NAME || -z $ENCRYPTION_ID || -z $ENCRYPTION_KEY || -z $KEY_LOCATION_PREFIX || -z $IMAGE ]]; then
  usage
fi

# TODO: add more regions
case $REGION in
  "eu-west-1")
    KEY_LOCATION="-ew1" ;;
  "ap-northeast-1")
    KEY_LOCATION="-an1" ;;
  "us-east-1")
    KEY_LOCATION="-ue1" ;;
  "us-west-1")
    KEY_LOCATION="-uw1" ;;
  "us-west-2")
    KEY_LOCATION="-uw2" ;;
  *)
    echo "An incorrect region value specified"
    exit 1
    ;;
esac

echo "Using key location: $KEY_LOCATION with prefix: $KEY_LOCATION_PREFIX"

# create nsswitch.conf
echo "Creating /home/core/nsswitch.conf..."
cat << EOT > /home/core/nsswitch.conf
#
# /etc/nsswitch.conf
#
passwd:     files usrfiles klam
shadow:     files usrfiles klam
group:      files usrfiles klam
 
hosts:      files usrfiles resolv dns
networks:   files usrfiles dns

services:   files usrfiles
protocols:  files usrfiles
rpc:        files usrfiles

ethers:     files
netmasks:   files
netgroup:   files
bootparams: files
automount:  files 
aliases:    files
EOT

# create klam-ssh.conf
echo "Creating /home/core/klam-ssh.conf..."
cat << EOT > /home/core/klam-ssh.conf
{
    "key_location": "${KEY_LOCATION_PREFIX:-adobe-cloudops-ssh-users}${KEY_LOCATION}",
    "role_name": "${ROLE_NAME}",
    "encryption_id": "${ENCRYPTION_ID}",
    "encryption_key": "${ENCRYPTION_KEY}",
    "resource_location": "amazon",
    "time_skew": "permissive",
    "cache_ttl": 2,
    "ssh_shell": "/bin/bash",
    "s3_region": "${REGION}"
}
EOT

#create profile.d/klam.sh
cat << EOT > /home/core/klam.sh
readonly KLAM_USER=$(who -m | awk '{print $1}')
readonly PROMPT_COMMAND='RETRN_VAL=$?;logger -p local6.debug "$KLAM_USER [$$]: $(history 1 | sed "s/^[ ]*[0-9]\+[ ]*//") [$RETRN_VAL]"'
EOT

# Create directory structure
echo "Making directories: /opt/klam/lib /opt/klam/lib /etc/ld.so.conf.d"
mkdir -p /opt/klam/lib /etc/ld.so.conf.d

# Creating environment file of KLAM values
echo "Creating environment file of KLAM values"
cat << EOT > /opt/klam/environment
REGION=${REGION}
ROLE_NAME=${ROLE_NAME}
ENCRYPTION_ID=${ENCRYPTION_ID}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
KEY_LOCATION_PREFIX=${KEY_LOCATION_PREFIX}
IMAGE=${IMAGE}
EOT

# Klam-ssh requires a shared library to be resident on the host.  These
# steps copy it from the klam-ssh container via a volume mount, then
# remove the container
echo "removing container if it exists"
if docker ps -a | grep klam-ssh;
then
  docker rm $(docker ps -a | grep klam-ssh | awk -F ' ' '{print $1}')
else
  echo "container does not exists"
fi
echo "grabbing latest image"
docker --config=$DIR/.docker/ pull ${IMAGE}
echo "Creating docker klam-ssh"
docker --config=$DIR/.docker/ create --name klam-ssh "${IMAGE}"
echo "Copying files to /opt/klam/lib"
docker cp klam-ssh:/tmp/klam-coreos/opt/klam/lib/libnss_klam.so.2.0 /opt/klam/lib
docker cp klam-ssh:/tmp/klam-coreos/opt/klam/lib/libjansson.a /opt/klam/lib
docker cp klam-ssh:/tmp/klam-coreos/opt/klam/lib/libjansson.la /opt/klam/lib
docker cp klam-ssh:/tmp/klam-coreos/opt/klam/lib/libjansson.so.4.7.0 /opt/klam/lib
docker cp klam-ssh:/tmp/klam-coreos/opt/klam/klam_cmd /opt/klam/lib
ln -sf /opt/klam/lib/libnss_klam.so.2.0 /opt/klam/lib/libnss_klam.so
ln -sf /opt/klam/lib/libnss_klam.so.2.0 /opt/klam/lib/libnss_klam.so.2
ln -sf /opt/klam/lib/libjansson.so.4.7.0 /opt/klam/lib/libnsss_klam.so.4
ln -sf /opt/klam/lib/libjansson.so.4.7.0 /opt/klam/lib/libnsss_klam.so
ln -sf /opt/klam/lib/klam_cmd/klam_cmd /opt/klam/nss_klam_data
echo "Removing docker klam-ssh"
docker rm klam-ssh

# Move the ld.so.conf drop-in file to the correct location so that the new shared
# library is detected, then update the shared library cache
echo "Moving the ld.so.conf file to the correct location"
cat << EOT > /etc/ld.so.conf.d/klam.conf
/opt/klam/lib
/opt/klam/lib/klam_cmd/
EOT
echo "Updating shared library cache"
sudo ldconfig
sudo ldconfig -p | grep klam

# Validate that the files exist in the correct folder
echo "Validating the /opt/klam/lib/libnss_klam.so* file exists in the correct folder"
ls -l /opt/klam/lib/libnss_klam.so*

# Re-link nsswitch.conf
echo "Re-linking nsswitch.conf"
sudo mv -f /home/core/nsswitch.conf /etc/nsswitch.conf
cat /etc/nsswitch.conf

# generate the ATO config
#echo "Generating the ATO config"
#sudo grep klamfed /etc/passwd > /opt/klam/lib/klam-ato.conf

# Validate that the contents of /opt/klam/lib/klam-ato.conf
#echo "Validating the contents of /opt/klam/lib/klam-ato.conf"
#cat /opt/klam/lib/klam-ato.conf

# Move klam-ssh.conf
echo "Moving klam-ssh.conf"
sudo mv -f /home/core/klam-ssh.conf /etc/klam-ssh.conf

#Move klam.sh
echo "Moving klam.sh"
sudo mv -f /home/core/klam.sh /etc/profile.d/klam.sh
cat /etc/profile.d/klam.sh

#  update /etc/ssh/sshd_config if necessary
echo "Updating /etc/ssh/sshd_config"
cat << EOT > sshd_config
# Use most defaults for sshd configuration.
UsePAM yes
UsePrivilegeSeparation sandbox
Subsystem sftp internal-sftp

PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication yes
AuthorizedKeysCommand /opt/klam/lib/authorizedkeys_command.sh
AuthorizedKeysCommandUser root
ClientAliveInterval 900
ClientAliveCountMax 0
EOT
sudo mv -f sshd_config /etc/ssh/sshd_config

cat /etc/ssh/sshd_config

echo "Setting up PAM modules"
cat << EOT > system-login
auth		required        pam_tally2.so file=/var/log/tallylog deny=6 unlock_time=900
auth            required        pam_nologin.so
auth		include         system-auth

account         required        pam_access.so
account         required        pam_nologin.so
account         include         system-auth
account         required        pam_tally2.so onerr=succeed

password        include         system-auth

session         optional        pam_loginuid.so
session         required        pam_env.so
session    	required    	pam_mkhomedir.so
session         optional        pam_lastlog.so
session         include         system-auth
session         optional        pam_motd.so motd=/etc/motd
session         optional        pam_mail.so
EOT
sudo mv -f system-login /etc/pam.d/system-login

echo "Setting Up sudo access: $(echo "${ROLE_NAME}" | awk -F "-" '{print toupper($5)}')"
cat << EOT > ADOBE_PLATFORM_$(echo "${ROLE_NAME}" | awk -F "-" '{print toupper($5)}')_ROLE_ADMIN
%ADOBE_PLATFORM_$(echo "${ROLE_NAME}" | awk -F "-" '{print toupper($5)}')_ROLE_ADMIN ALL=(ALL) NOPASSWD: ALL
EOT
sudo mv -f ADOBE_PLATFORM_$(echo "${ROLE_NAME}" | awk -F "-" '{print toupper($5)}')_ROLE_ADMIN /etc/sudoers.d/
cat << EOT > ADOBE_PLATFORM_AWS_$(echo "${ROLE_NAME}" | awk -F "-" '{print toupper($5)}')_ADMIN
%ADOBE_PLATFORM_AWS_$(echo "${ROLE_NAME}" | awk -F "-" '{print toupper($5)}')_ADMIN ALL=(ALL) NOPASSWD: ALL
EOT
sudo mv -f ADOBE_PLATFORM_AWS_$(echo "${ROLE_NAME}" | awk -F "-" '{print toupper($5)}')_ADMIN /etc/sudoers.d/


# Change ownership of authorizedkeys_command
echo "Changing ownership of authorizedkeys_command to root:root"
sudo chown root:0 $DIR/authorizedkeys_command.sh
chmod +x $DIR/authorizedkeys_command.sh

# Relocate authorizedkeys_command
echo "Relocating authorizedkeys_command to /opt/klam/lib"
mv $DIR/authorizedkeys_command.sh /opt/klam/lib

# Change ownership of download_s3
echo "Changing ownership of download_s3 to root:root"
chown root:0 $DIR/download_s3.sh
chmod +x $DIR/download_s3.sh

# Relocate download_s3.sh have to rename to downloadS3 as reference in python klam lib
echo "Relocating download_s3 to /opt/klam/lib"
mv $DIR/download_s3.sh /opt/klam/lib/downloadS3.sh
if [ -f /opt/klam/downloadS3 ]; then
  echo "downnloadS3 already linked"
else
  ln -s /opt/klam/lib/downloadS3.sh /opt/klam/downloadS3
fi

# Restart SSHD
echo "Restarting SSHD"
sudo systemctl restart sshd.service
echo "-------Done klam-ssh setup-------"

while true; do
  echo "systemctl check"
  cat /etc/ssh/sshd_config 2>&1
  sleep 5
done


