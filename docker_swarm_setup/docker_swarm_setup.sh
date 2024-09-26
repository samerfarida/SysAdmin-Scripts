#!/bin/bash

# script description: Script to deploy a cluster of managers and workers on a cluster of servers.

# SSH user
SSH_USER="serveradmin"

# Managers and workers IP addresses
MANAGER_IPS=("192.168.80.248" "192.168.80.136" "192.168.80.123")
WORKER_IPS=("192.168.80.182" "192.168.80.76" "192.168.80.110")

# SSH certificate file
SSH_CERTIFICATE="/root/.ssh/id_rsa"

# Add host keys to known_hosts file
add_host_keys() {
    for ip in "${MANAGER_IPS[@]}" "${WORKER_IPS[@]}"; do
        echo "Adding host key for $ip to known_hosts file..."
        ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts
    done
}

# Install Docker on remote servers
install_docker() {
    for ip in "${MANAGER_IPS[@]}" "${WORKER_IPS[@]}"; do
        echo "Installing Docker on $ip..."
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" 'curl -fsSL https://get.docker.com -o install-docker.sh && sudo sh install-docker.sh'
    done
}

# Function to apply worker labels on the first manager
apply_worker_labels() {
    local first_manager=${MANAGER_IPS[0]}
    local worker_hostnames
    
    echo "Retrieving worker hostnames from the first manager ($first_manager)..."
    worker_hostnames=$(ssh -i $SSH_CERTIFICATE $SSH_USER@"$first_manager" 'sudo docker node ls --filter role=worker --format "{{.Hostname}}"')

    echo "Applying worker labels on the first manager ($first_manager)..."
    while IFS= read -r worker_hostname; do
        echo "Applying worker label to $worker_hostname..."
        ssh -n -i $SSH_CERTIFICATE $SSH_USER@"$first_manager" "sudo docker node update --label-add worker=true $worker_hostname"
    done <<< "$worker_hostnames"
}

# Create Docker Swarm
create_swarm() {
    # Initialize Swarm on the first manager
    FIRST_MANAGER=${MANAGER_IPS[0]}
    echo "Initializing Swarm on $FIRST_MANAGER..."
    ssh -i $SSH_CERTIFICATE $SSH_USER@"$FIRST_MANAGER" "sudo docker swarm init --advertise-addr $FIRST_MANAGER"

    # Get manager join token
    MANAGER_TOKEN=$(ssh -i $SSH_CERTIFICATE $SSH_USER@"$FIRST_MANAGER" 'sudo docker swarm join-token manager -q')

    # Join additional managers to swarm
    for ip in "${MANAGER_IPS[@]:1}"; do
        echo "Joining manager $ip to the swarm..."
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" "sudo docker swarm join --token $MANAGER_TOKEN $FIRST_MANAGER:2377"
    done

    # Get worker join token
    WORKER_TOKEN=$(ssh -i $SSH_CERTIFICATE $SSH_USER@"$FIRST_MANAGER" 'sudo docker swarm join-token worker -q')

    # Join workers to swarm
    for ip in "${WORKER_IPS[@]}"; do
        echo "Joining worker $ip to the swarm..."
        ssh -i $SSH_CERTIFICATE $SSH_USER@"$ip" "sudo docker swarm join --token $WORKER_TOKEN $FIRST_MANAGER:2377"
    done
}

# Display Docker Swarm status
display_swarm_status() {
    echo "Docker Swarm Status:"
    ssh -i $SSH_CERTIFICATE $SSH_USER@"${MANAGER_IPS[0]}" 'sudo docker node ls'
}

# Main script
echo "Add host keys to known_hosts file"
add_host_keys
echo "Install Docker on remote servers"
install_docker
echo "Create Docker Swarm and join nodes"
create_swarm
echo "Apply worker labels on the first manager"
apply_worker_labels
echo "Display Docker Swarm status"
display_swarm_status
