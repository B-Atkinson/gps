#!/usr/bin/env bash
set -euo pipefail

print_header() {
  printf '\n\n'
  printf '%.0s*' {1..50}
  echo -e "\n$1"
  printf '%.0s*' {1..50}
  printf '\n\n'
}

change_timezone() {
  sudo timedatectl set-ntp true
  print_header "Choose timezone for this Raspberry Pi (used to configure the system clock)."

  # Number the timezones for robust selection
  # shellcheck disable=SC2009
  tz_list="$(timedatectl list-timezones)"
  # Print with line numbers
  nl -w3 -s'  ' <<<"$tz_list"

  # Ask for an index and validate
  local count choice zoneName
  count=$(wc -l <<<"$tz_list" | awk '{print $1}')
  while true; do
    read -r -p $"Enter the number of the timezone to use [1-${count}] (or press Enter to cancel): " choice
    [[ -z "${choice}" ]] && { echo "Skipping timezone change."; return 0; }
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      zoneName=$(sed -n "${choice}p" <<<"$tz_list")
      break
    else
      echo "Invalid selection. Try again."
    fi
  done

  echo "Setting timezone to: ${zoneName}"
  sudo timedatectl set-timezone "${zoneName}"
}

ensure_docker() {
  # Install Git
  if ! command -v git >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y git
  fi

  # Install Docker Engine + Compose plugin (Ubuntu repo on ARM)
  if ! command -v docker >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable docker
    sudo usermod -aG docker "$USER" || true
  else
    # Ensure compose plugin exists even if Docker pre-existed
    if ! docker compose version >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y docker-compose-plugin
    fi
  fi
}

build_database_dir() {
  mkdir -p "$HOME/gps/db"
  echo -e "Current memory layout:\n"
  lsblk

  read -r -p $'\nDo you want to create a dedicated partition for database files (loop-backed image)? (y/[n])  ' partitionDatabases
  if [[ "$partitionDatabases" =~ ^([yY])$ ]]; then
    local partitionSize
    while true; do
      read -r -p $'Enter the size in whole gigabytes (e.g., 2, 5, 10), or press Enter to cancel:  ' partitionSize
      [[ -z "${partitionSize}" ]] && { echo "Skipping partition creation."; return 0; }
      if [[ "$partitionSize" =~ ^[0-9]+$ ]] && (( partitionSize > 0 )); then
        break
      else
        echo "Please enter a positive integer (e.g., 2, 5, 10)."
      fi
    done
    # ensure_db_partition.sh must be in the current repo dir ($HOME/gps)
    sudo ./ensure_db_partition.sh "${partitionSize}"
  fi
}

main() {
  # Keep track of original directory; always come back even on error
  local start_dir
  start_dir="$(pwd)"
  trap 'cd "$start_dir"' EXIT

  #### Update and upgrade packages ####
  sudo apt-get update -y && sudo apt-get upgrade -y

  #### Docker (and git) ####
  ensure_docker

  #### Time sync/status ####
  printf "Current system time data:\n"
  timedatectl status || true

  read -r -p $'\nDo you wish to change the timezone (y/[n])?  ' changeTimeZoneSelect
  if [[ "$changeTimeZoneSelect" =~ ^([yY])$ ]]; then
    change_timezone
  fi

  #### Begin the GPS code section ####
  print_header "Update GPS logging software."
  if [[ -d "$HOME/gps" ]]; then
    cd "$HOME/gps"
    # Use sudo to avoid docker-group timing issues during bootstrap
    sudo docker compose down || true
    git pull --ff-only
    build_database_dir
  else
    echo -e "\n\n*************** ERROR ***************\n"
    echo -e "Unable to find software. Please ensure the repository is located at: $HOME/gps"
    exit 1
  fi

  print_header "Restarting container with new update"
  # Use sudo here; user may not have new docker group yet
  sudo docker compose up -d

  echo "Done."
}

main "$@"
