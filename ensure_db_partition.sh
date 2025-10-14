#!/usr/bin/env bash
set -euo pipefail

# Ensure a dedicated filesystem is mounted at /home/crusader/gps/db.
# If not mounted, create an ext4 loop-backed image of SIZE_GB and mount it there.
# Usage: sudo ./ensure_db_partition.sh <SIZE_GB>
#
# Notes:
# - Uses /var/lib/gps_storage/gps_db.img to store the backing file (outside the mountpoint).
# - Safe/idempotent: if already mounted, exits 0. If image exists with different size, refuses to overwrite.

MOUNTPOINT="/home/crusader/gps/db"
IMG_DIR="/var/lib/gps_storage"
IMG_PATH="${IMG_DIR}/gps_db.img"

# ---- Parse & validate args ----
if [[ $# -ne 1 ]]; then
  echo "Usage: sudo $0 <SIZE_GB>"
  exit 1
fi
SIZE_GB="$1"
if ! [[ "$SIZE_GB" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SIZE_GB must be an integer number of gigabytes."
  exit 1
fi

# ---- Require root ----
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must run as root (use sudo)."
  exit 1
fi

# ---- Quick idempotency check: already mounted? ----
if findmnt -rno SOURCE,TARGET "$MOUNTPOINT" >/dev/null 2>&1; then
  echo "Mountpoint '$MOUNTPOINT' is already mounted. Nothing to do."
  exit 0
fi

# ---- Ensure tools present (Ubuntu default installs usually have these) ----
for bin in fallocate losetup mkfs.ext4 tune2fs mount grep sed stat; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing tool: $bin"; exit 1; }
done

# ---- Prepare directories ----
mkdir -p "$MOUNTPOINT"
mkdir -p "$IMG_DIR"

# ---- If image exists, verify its size matches the request ----
if [[ -f "$IMG_PATH" ]]; then
  current_bytes=$(stat -c %s "$IMG_PATH")
  requested_bytes=$(( SIZE_GB * 1024 * 1024 * 1024 ))
  if (( current_bytes != requested_bytes )); then
    echo "ERROR: Existing image $IMG_PATH is size $current_bytes bytes, not ${requested_bytes}."
    echo "Refusing to overwrite existing image. Move or remove it if you want a new size."
    exit 1
  else
    echo "Reusing existing image $IMG_PATH (${SIZE_GB}G)."
  fi
else
  echo "Creating sparse image ${IMG_PATH} of size ${SIZE_GB}G ..."
  fallocate -l "${SIZE_GB}G" "$IMG_PATH"
  echo "Formatting image as ext4 ..."
  mkfs.ext4 -F "$IMG_PATH"
  # Set reserved blocks to 0% (data-only volume)
  LOOP_DEV="$(losetup -f)"
  losetup "$LOOP_DEV" "$IMG_PATH"
  tune2fs -m 0 "$LOOP_DEV" || true
  losetup -d "$LOOP_DEV"
fi

# ---- Add /etc/fstab entry if missing ----
FSTAB_LINE="$(printf '%s\t%s\text4\tloop,defaults,noatime\t0\t2\n' "$IMG_PATH" "$MOUNTPOINT")"
if grep -E "^[^#]*[[:space:]]${MOUNTPOINT}[[:space:]]" /etc/fstab | grep -q "$IMG_PATH"; then
  echo "fstab entry already present."
else
  echo -n "Adding fstab entry ... "
  echo -e "$FSTAB_LINE" >> /etc/fstab
  echo "done."
fi

# ---- Mount it ----
echo "Mounting $MOUNTPOINT ..."
mount "$MOUNTPOINT"

# ---- Optional: set ownership to match parent directory owner if 'crusader' exists ----
if id crusader >/dev/null 2>&1; then
  chown crusader:crusader "$MOUNTPOINT"
fi
chmod 0755 "$MOUNTPOINT"

echo "Success. Mounted $(findmnt -rno SOURCE "$MOUNTPOINT") at $MOUNTPOINT"
df -h "$MOUNTPOINT" || true
