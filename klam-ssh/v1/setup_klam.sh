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
passwd:     files usrfiles ato
shadow:     files usrfiles ato
group:      files usrfiles ato

hosts:      files usrfiles dns
networks:   files usrfiles dns

services:   files usrfiles
protocols:  files usrfiles
rpc:        files usrfiles

ethers:     files
netmasks:   files
netgroup:   nisplus
bootparams: files
automount:  files nisplus
aliases:    files nisplus
EOT

# create klam-ssh.conf
echo "Creating /home/core/klam-ssh.conf..."
cat << EOT > /home/core/klam-ssh.conf
{
    key_location: ${KEY_LOCATION_PREFIX:-adobe-cloudops-ssh-users}${KEY_LOCATION},
    role_name: ${ROLE_NAME},
    encryption_id: ${ENCRYPTION_ID},
    encryption_key: ${ENCRYPTION_KEY},
    resource_location: amazon,
    time_skew: permissive,
    s3_region: ${REGION}
}
EOT

# Create directory structure
echo "Making directories: /opt/klam/lib /opt/klam/lib64 /etc/ld.so.conf.d"
mkdir -p /opt/klam/lib /opt/klam/lib64 /etc/ld.so.conf.d

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
echo "Creating docker klam-ssh"
docker --config=$DIR/.docker/ create --name klam-ssh "${IMAGE}"
echo "Copying /tmp/klam-build/coreos/libnss_ato.so.2 file to /opt/klam/lib64"
docker cp klam-ssh:/tmp/klam-build/coreos/libnss_ato.so.2 /opt/klam/lib64
ln -sf /opt/klam/lib64/libnss_ato.so.2 /opt/klam/lib64/libnss_ato.so
echo "Removing docker klam-ssh"
docker rm klam-ssh

# Move the ld.so.conf drop-in file to the correct location so that the new shared
# library is detected, then update the shared library cache
echo "Moving the ld.so.conf file to the correct location"
echo "/opt/klam/lib64" > /etc/ld.so.conf.d/klam.conf
echo "Updating shared library cache"
sudo ldconfig
sudo ldconfig -p | grep klam

# Validate that the files exist in the correct folder
echo "Validating the /opt/klam/lib64/libnss_ato.so* file exists in the correct folder"
ls -l /opt/klam/lib64/libnss_ato.so*

# Create the klamfed home directory
echo "Creating the klamfed user and home directory"
sudo useradd -p "*" -U -G sudo -u 5000 -m klamfed -s /bin/bash || :
mkdir -p /home/klamfed
sudo usermod -p "*" klamfed
sudo usermod -U klamfed
sudo update-ssh-keys -u klamfed || :

# Add klamfed to wheel
echo "Adding klamfed to wheel group"
sudo usermod -a -G wheel klamfed

# Add klamfed to sudo
echo "Adding klamfed to sudo group"
sudo usermod -a -G sudo klamfed

# Add passwordless sudo to klamfed
echo "Adding passwordless sudo for klamfed"
sudo echo "klamfed ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/klamfed

# Validate that the klamfed user has the correct uid value (5000) and home directory
echo "Validating the klamfed user uid and home directory"
id klamfed
ls -ld /home/klamfed

# Re-link nsswitch.conf
echo "Re-linking nsswitch.conf"
sudo mv -f /home/core/nsswitch.conf /etc/nsswitch.conf
cat /etc/nsswitch.conf

# generate the ATO config
echo "Generating the ATO config"
sudo grep klamfed /etc/passwd > /opt/klam/lib/klam-ato.conf

# Validate that the contents of /opt/klam/lib/klam-ato.conf
echo "Validating the contents of /opt/klam/lib/klam-ato.conf"
cat /opt/klam/lib/klam-ato.conf

# Move klam-ssh.conf
echo "Moving klam-ssh.conf"
sudo mv -f /home/core/klam-ssh.conf /opt/klam/lib/klam-ssh.conf
cat /opt/klam/lib/klam-ssh.conf

#  update /etc/ssh/sshd_config if necessary
echo "Updating /etc/ssh/sshd_config if necessary"
if ! grep /opt/klam/lib/authorizedkeys_command.sh /etc/ssh/sshd_config; then
  sudo cp /etc/ssh/sshd_config sshd_config
  echo -e '\nAuthorizedKeysCommand /opt/klam/lib/authorizedkeys_command.sh' >> sshd_config
  echo 'AuthorizedKeysCommandUser root' >> sshd_config
  sudo mv -f sshd_config /etc/ssh/sshd_config
fi
cat /etc/ssh/sshd_config

# Change ownership of authorizedkeys_command
echo "Changing ownership of authorizedkeys_command to root:root"
sudo chown root:root $DIR/authorizedkeys_command.sh

# Relocate authorizedkeys_command
echo "Relocating authorizedkeys_command to /opt/klam/lib"
mv $DIR/authorizedkeys_command.sh /opt/klam/lib

# Change ownership of download_s3
echo "Changing ownership of download_s3 to root:root"
chown root:root $DIR/download_s3.sh
chmod +x /opt/klam/lib/download_s3.sh

# Relocate download_s3.sh have to rename to downloadS3 as reference in python klam lib
echo "Relocating download_s3 to /opt/klam/lib"
mv $DIR/download_s3.sh /opt/klam/lib/downloadS3.sh

# Restart SSHD
echo "Restarting SSHD"
sudo systemctl restart sshd.service

echo "-------Done klam-ssh setup-------"

sleep infinity
