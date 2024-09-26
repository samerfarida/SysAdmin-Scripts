#!/bin/bash

# script description: Script to create cephfs cleint auth file on proxmox and and mount cephfs on a remote server.

# Ceph FS variables
CEPHFS_NAME="cephfs"
CEPHFS_SUBDIRECTORY="docker-shared-prod"
MNT_DIR_NAME="$CEPHFS_NAME/$CEPHFS_SUBDIRECTORY"
CEPH_CONF=""
CLIENT_KEYRING=""
CLIENT_KEY=""
SSH_USER="serveradmin"
SERVERS_IPS=("192.168.80.248" "192.168.80.136" "192.168.80.123" "192.168.80.182" "192.168.80.76" "192.168.80.110")

SSH_CERTIFICATE="/root/.ssh/id_rsa"

# Function to add host keys to known_hosts file
add_host_keys() {
    if [ ! -f ~/.ssh/known_hosts ]; then
        touch ~/.ssh/known_hosts
    fi
    for ip in "${SERVERS_IPS[@]}"; do
        if ! grep -q "$ip" ~/.ssh/known_hosts; then
            echo "Adding host key for $ip to known_hosts file..."
            ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts
        fi
    done
}

# Function to install ceph-common on all servers
install_ceph_common() {
    for ip in "${SERVERS_IPS[@]}"; do
        echo "Installing ceph-common on $ip..."
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo apt install -y ceph-common'
    done
}

# Function to create directories on all servers
create_directories() {
    for ip in "${SERVERS_IPS[@]}"; do
        echo "Creating directories on $ip..."
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo mkdir -p /etc/ceph && sudo mkdir -p /mnt/'"$MNT_DIR_NAME"
    done
}

# Function to generate ceph config file and copy to all servers
generate_ceph_config() {
    CEPH_CONF=$(sudo ceph config generate-minimal-conf)
    for ip in "${SERVERS_IPS[@]}"; do
        echo "Copying ceph config file to $ip..."
        echo "$CEPH_CONF" | ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo tee /etc/ceph/ceph.conf > /dev/null'
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo chmod 644 /etc/ceph/ceph.conf'
    done
}

# Function to authorize client and mount ceph fs on all servers
authorize_and_mount_cephfs() {
    for ip in "${SERVERS_IPS[@]}"; do
        echo "Authorizing client and mounting ceph fs on $ip..."
        SERVERS_HOSTNAME=$(ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" hostname)
        # CLIENT_KEYRING=$(sudo ceph fs authorize $CEPHFS_NAME client.$SERVERS_HOSTNAME /$CEPHFS_SUBDIRECTORY rw)
        CLIENT_KEYRING=$(sudo ceph fs authorize $CEPHFS_NAME client."$SERVERS_HOSTNAME" / rw)
        echo "$CLIENT_KEYRING" | ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo tee /etc/ceph/ceph.client.'"$SERVERS_HOSTNAME"'.keyring > /dev/null'
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo chmod 600 /etc/ceph/ceph.client.'"$SERVERS_HOSTNAME"'.keyring'
        CLIENT_KEY=$(sudo ceph auth get-key client."$SERVERS_HOSTNAME")
        echo "$CLIENT_KEY" | ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo tee /etc/ceph/ceph.client.'"$SERVERS_HOSTNAME"'.key > /dev/null'
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" "sudo chmod 600 /etc/ceph/ceph.client.$SERVERS_HOSTNAME.key"
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" "sudo mount -t ceph $SERVERS_HOSTNAME@.$CEPHFS_NAME=/$CEPHFS_SUBDIRECTORY /mnt/$MNT_DIR_NAME -o secretfile=/etc/ceph/ceph.client.$SERVERS_HOSTNAME.key"
        echo "Setting up persistent mount on $SERVERS_HOSTNAME - $ip..."
        echo "$SERVERS_HOSTNAME@.$CEPHFS_NAME=/$CEPHFS_SUBDIRECTORY /mnt/$MNT_DIR_NAME ceph secretfile=/etc/ceph/ceph.client.$SERVERS_HOSTNAME.key,noatime,_netdev 0 0" | ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'sudo tee -a /etc/fstab > /dev/null'
        echo "Changing ownership /mnt/$MNT_DIR_NAME to root:docker"
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" "sudo chown -R root:docker /mnt/$MNT_DIR_NAME"
        echo "Initiating server reboot on $SERVERS_HOSTNAME - $ip..."
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" "sudo reboot"
    done
}


# Main function
main() {
    #add_host_keys
    install_ceph_common
    create_directories
    generate_ceph_config
    authorize_and_mount_cephfs
}

# Call main function
main
