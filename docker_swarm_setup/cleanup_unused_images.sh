#!/usr/bin/env bash
set -euo pipefail

# ================================
# Docker Swarm Cluster Cleanup Script
# ================================
# Features:
#   --dry-run        Preview cleanup (default if no flag is provided)
#   --live           Actually prune images
#   --dangling-only  Remove ONLY dangling (<none>) images
#   --all            Remove ALL unused images (default for live)
#   --confirm CLEAN  Skip interactive confirmation (cron-friendly)
#
# Usage examples:
#   ./cleanup_unused_images.sh --dry-run
#   ./cleanup_unused_images.sh --live --dangling-only
#   ./cleanup_unused_images.sh --live --all --confirm CLEAN
# =================================

# List of all your Swarm nodes
NODES=(
  "docker-prod-manager1"
  "docker-prod-manager2"
  "docker-prod-manager3"
  "docker-prod-worker1"
  "docker-prod-worker2"
  "docker-prod-worker3"
)

MODE="dry-run"
PRUNE_TYPE="all"
CONFIRM_INPUT=""

# ===== Parse Flags =====
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --live) MODE="live" ;;
    --dangling-only) PRUNE_TYPE="dangling" ;;
    --all) PRUNE_TYPE="all" ;;
    --confirm) CONFIRM_INPUT="${2:-}"; shift ;;
    *) echo "❌ Unknown option: $1"; exit 1 ;;
  esac
  shift
done

LOGFILE="./docker_cleanup_$(date +%F).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Docker Swarm Cluster Cleanup ==="
echo "Mode: $MODE"
echo "Prune type: $PRUNE_TYPE"
echo "Nodes: ${#NODES[@]}"
echo "Logs: $LOGFILE"
echo "-------------------------------------"

# Pick correct prune command
if [[ "$PRUNE_TYPE" == "dangling" ]]; then
  PRUNE_CMD="sudo docker image prune -f"
else
  PRUNE_CMD="sudo docker image prune -a -f"
fi

# Step 1: Show disk usage before cleanup
for NODE in "${NODES[@]}"; do
  echo "---- $NODE: Disk usage before ----"
  ssh -o BatchMode=yes serveradmin@"$NODE" "sudo docker system df || true"
done

# Step 2: Preview images that *would* be removed
echo "---- DRY-RUN PREVIEW ----"
for NODE in "${NODES[@]}"; do
  echo "Node: $NODE"
  ssh -o BatchMode=yes serveradmin@"$NODE" "
    echo 'Dangling Images:' &&
    sudo docker images -f 'dangling=true' --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' || true
    echo '---'
    if [[ \"$PRUNE_TYPE\" == \"all\" ]]; then
      echo 'Unused Tagged Images:' &&
      sudo docker images --filter 'dangling=false' --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' |
      grep -v '<none>' || echo 'None'
    else
      echo '(Skipping unused tagged images: dangling-only mode)'
    fi
  "
done

# If dry-run, exit safely
if [[ "$MODE" == "dry-run" ]]; then
  echo "✅ Dry-run complete. No images were deleted."
  exit 0
fi

# Step 3: If live mode, require confirmation
if [[ "$CONFIRM_INPUT" != "CLEAN" ]]; then
  read -rp "⚠️ Type CLEAN to prune images across ALL nodes: " CONFIRM_INPUT
  [[ "$CONFIRM_INPUT" != "CLEAN" ]] && echo "Aborted." && exit 1
fi

# Step 4: Run prune command on all nodes
for NODE in "${NODES[@]}"; do
  echo "---- $NODE: Pruning images ----"
  ssh -o BatchMode=yes serveradmin@"$NODE" "$PRUNE_CMD || true"
done

# Step 5: Show disk usage after cleanup
for NODE in "${NODES[@]}"; do
  echo "---- $NODE: Disk usage after ----"
  ssh -o BatchMode=yes serveradmin@"$NODE" "sudo docker system df || true"
done

echo "✅ Done! Cleanup complete. Logs saved to $LOGFILE"