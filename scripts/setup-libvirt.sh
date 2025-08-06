#!/bin/bash

set -e

YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Install prerequisites
echo -e "${YELLOW}[+] Installing prerequisites...${NC}"
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager

# 2. Create and start the default storage pool if it doesn't exist
POOL_NAME="default"
POOL_PATH="/var/lib/libvirt/images/default"

echo -e "${YELLOW}[+] Checking if storage pool '$POOL_NAME' exists...${NC}"
if ! virsh pool-list --all | grep -q "$POOL_NAME"; then
  echo -e "${YELLOW}[+] Creating storage pool '$POOL_NAME' at $POOL_PATH...${NC}"
  sudo mkdir -p "$POOL_PATH"
  virsh pool-define-as "$POOL_NAME" dir - - - - "$POOL_PATH"
  virsh pool-build "$POOL_NAME"
  virsh pool-start "$POOL_NAME"
  virsh pool-autostart "$POOL_NAME"
else
  echo -e "${YELLOW}[+] Storage pool '$POOL_NAME' already exists.${NC}"
fi

# 3. Set proper permissions for the storage pool path
echo -e "${YELLOW}[+] Setting permissions for $POOL_PATH...${NC}"
sudo chown libvirt-qemu:libvirt-qemu "$POOL_PATH"
sudo chmod 755 "$POOL_PATH"

# 4. Restart libvirtd service
echo -e "${YELLOW}[+] Restarting libvirtd service...${NC}"
sudo systemctl restart libvirtd

# 5. Add current user to the libvirt group
USER_NAME=$(whoami)
echo -e "${YELLOW}[+] Adding user '$USER_NAME' to 'libvirt' group...${NC}"
sudo usermod -aG libvirt "$USER_NAME"

# 6. Download Ubuntu Cloud image if not already downloaded or if corrupted
IMG_NAME="jammy-server-cloudimg-amd64.img"
IMG_URL="https://cloud-images.ubuntu.com/jammy/current/$IMG_NAME"
MIN_SIZE_MB=500

DOWNLOAD_IMAGE() {
  echo -e "${YELLOW}[+] Downloading Ubuntu image...${NC}"
  wget -O "$IMG_NAME" "$IMG_URL"
}

if [ -f "$IMG_NAME" ]; then
  SIZE_MB=$(du -m "$IMG_NAME" | cut -f1)
  if [ "$SIZE_MB" -lt "$MIN_SIZE_MB" ]; then
    echo -e "${YELLOW}[!] Image exists but is too small (${SIZE_MB}MB). Re-downloading...${NC}"
    rm -f "$IMG_NAME"
    DOWNLOAD_IMAGE
  else
    echo -e "${YELLOW}[+] Image '$IMG_NAME' already exists and looks valid (${SIZE_MB}MB).${NC}"
  fi
else
  DOWNLOAD_IMAGE
fi

# 7. Resize the image by +50G
echo -e "${YELLOW}[+] Resizing image '$IMG_NAME' by +50G...${NC}"
qemu-img resize "$IMG_NAME" +50G

# 8. Show absolute path to use in Terraform variables
ABSOLUTE_PATH=$(readlink -f "$IMG_NAME")
echo -e "${YELLOW}[+] Use this absolute path in your Terraform 'variables.tf':${NC}"
echo "  $ABSOLUTE_PATH"

echo -e "${YELLOW}[+] Done. Please log out and log back in for group membership changes to take effect.${NC}"
