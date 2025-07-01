#!/usr/bin/env bash

# List of all your Swarm nodes
NODES=(
  "docker-prod-manager1"
  "docker-prod-manager2"
  "docker-prod-manager3"
  "docker-prod-worker1"
  "docker-prod-worker2"
  "docker-prod-worker3"
)

echo "=== Docker Swarm Cluster Cleanup ==="
echo "This script will connect to each node and prune unused images."
echo "-------------------------------------"

# First, show disk usage before cleanup
for NODE in "${NODES[@]}"; do
  echo "---- $NODE: Disk usage before ----"
  ssh serveradmin@$NODE "sudo docker system df"
done

# Then show which images will be removed (manual preview since there's no --dry-run)
for NODE in "${NODES[@]}"; do
  echo "---- $NODE: Dangling images preview ----"
  ssh serveradmin@$NODE "sudo docker images -f 'dangling=true'"
done

read -rp "Proceed to prune unused images on all nodes? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

# Run actual prune
for NODE in "${NODES[@]}"; do
  echo "---- $NODE: Pruning unused images ----"
  ssh serveradmin@$NODE "sudo docker image prune -a -f"
done

# Show disk usage after cleanup
for NODE in "${NODES[@]}"; do
  echo "---- $NODE: Disk usage after ----"
  ssh serveradmin@$NODE "sudo docker system df"
done

echo "✅ Done! All unused images have been cleaned up across the cluster."
