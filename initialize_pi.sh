#!/bin/bash

function print_header {
  printf '\n\n'
  printf '%.0s*' {1..50}
  echo -e "\n$1"
  printf '%.0s*' {1..50}
  printf '\n\n'
}

function change_timezone {
  sudo timedatectl set-ntp true
  print_header "Please enter the name of the timezone to utilize for this Raspberry Pi. This is used to configure the system clock."
  let i=1
  for zone in $(timedatectl list-timezones); do
    printf "%d - %s\n" $i "$zone"
    ((i++))
  done

  read -n 4 -p "Time zone number to use (as shown in the printed menu): " zoneNumber
  let j=1
  let zoneName="NONE"
  for zone in $(timedatectl list-timezones); do
   if [[ "$zoneNumber" == "$j" ]]
     then {
       zoneName="$zone";
       break;
     }
   fi
   ((j++))
  done

  sudo timedatectl set-timezone "$zoneName"
}

#### Update and upgrade packages ####

sudo apt-get update -y && sudo apt-get upgrade -y
if [ ! -x "$(command -v git)" ]; then
  sudo apt-get install git -y
fi

if [ ! -x "$(command -v docker)" ]; then
  sudo apt-get install ca-certificates curl -y
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  userName="$USER"
  sudo usermod -aG docker "$userName"
fi

#### Time sync ####

printf "Current system time data:\n"
timedatectl status

read -r -p $'\n\nDo you wish to change the timezone (y/[n])?  ' changeTimeZoneSelect
if [[ "$changeTimeZoneSelect" =~ ^([yY]{1}) ]]; then
  change_timezone
fi

#### Begin the GPS code section ####

print_header "Update GPS logging software."
if [ -d "$HOME/gps" ]; then
  curDir=$(pwd)
  cd "$HOME/gps"
  git pull

  else
    echo -e "\n\n*************** ERROR ***************\n"
    echo -e "Unable to find software. Please ensure the repository is located at: $HOME/gps"
    exit 1
fi
mkdir -p "$HOME/gps/db"

print_header "Restarting container with new update"
docker compose down
docker compose up -d

exit 0



