#!/bin/bash
#################################################################################
# Title:         Saltbox: Dependencies Installer                                #
# Author(s):     L3uddz, Desimaniac, EnorMOZ, salty                             #
# URL:           https://github.com/saltyorg/sb                                 #
# Description:   Installs dependencies needed for Saltbox.                      #
# --                                                                            #
#################################################################################
#                     GNU General Public License v3.0                           #
#################################################################################

set -e
set -o pipefail

################################
# Error Handling
################################

error() {
    echo "Error: $1"
    exit 1
}

################################
# Privilege Escalation
################################

if [ "$EUID" != 0 ]; then
    sudo "$0" "$@"
    exit $?
fi

################################
# Variables
################################

VERBOSE=false

readonly SYSCTL_PATH="/etc/sysctl.conf"
readonly PYTHON_CMD_SUFFIX="-m pip install \
                            --timeout=360 \
                            --no-cache-dir \
                            --disable-pip-version-check \
                            --upgrade"
readonly PYTHON3_CMD="/srv/ansible/venv/bin/python3 $PYTHON_CMD_SUFFIX"

################################
# Argument Parser
################################

while getopts 'v' f; do
    case $f in
    v) VERBOSE=true;;
    *) error "Invalid option";;
    esac
done

################################
# Functions
################################

run_cmd() {
    if $VERBOSE; then
        "$@"
    else
        "$@" &>/dev/null
    fi
}

install_pip() {
  cd /tmp || error "Failed to change directory to /tmp"
  run_cmd curl -sLO https://bootstrap.pypa.io/get-pip.py \
      || error "Failed to download get-pip.py"
  run_cmd python3 get-pip.py || error "Failed to install pip3."
}

################################
# Main
################################

## IPv6
if [ -f "$SYSCTL_PATH" ]; then
    ## Remove 'Disable IPv6' entries from sysctl
    run_cmd sed -i -e '/^net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_PATH" \
        || error "Failed to modify $SYSCTL_PATH (1)"
    run_cmd sed -i -e '/^net.ipv6.conf.default.disable_ipv6/d' "$SYSCTL_PATH" \
        || error "Failed to modify $SYSCTL_PATH (2)"
    run_cmd sed -i -e '/^net.ipv6.conf.lo.disable_ipv6/d' "$SYSCTL_PATH" \
        || error "Failed to modify $SYSCTL_PATH (3)"
    run_cmd sysctl -p || error "Failed to apply sysctl settings"
fi

## Environmental Variables
export DEBIAN_FRONTEND=noninteractive

## Install Pre-Dependencies
run_cmd run_cmd apt-get install -y \
    software-properties-common \
    apt-transport-https \
    || error "Failed to install pre-dependencies"
run_cmd run_cmd apt-get update || error "Failed to update apt-get repositories"

# Check for supported Ubuntu Releases
release=$(lsb_release -cs) || error "Failed to determine Ubuntu release"

## Add apt repos
if [[ $release =~ (focal|jammy)$ ]]; then
    run_cmd add-apt-repository main -y || error "Failed to add main repository"
    run_cmd add-apt-repository universe -y || error "Failed to add universe repository"
    run_cmd add-apt-repository restricted -y || error "Failed to add restricted repository"
    run_cmd add-apt-repository multiverse -y || error "Failed to add multiverse repository"
    run_cmd apt-get update || error "Failed to update apt-get repositories"

elif [[ $release =~ (noble)$ ]]; then
  echo " " > /etc/apt/sources.list
  run_cmd add-apt-repository -n -y "deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main restricted universe multiverse" || error "Failed to add $(lsb_release -sc) repositoríes"
  run_cmd add-apt-repository -n -y "deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates main restricted universe multiverse" || error "Failed to add $(lsb_release -sc)-updates repositoríes"
  run_cmd add-apt-repository -n -y "deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-backports main restricted universe multiverse" || error "Failed to add $(lsb_release -sc)-backports repositoríes"
  run_cmd add-apt-repository -n -y "deb http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted universe multiverse" || error "Failed to add $(lsb_release -sc)-security repositoríes"
  run_cmd apt update

else
    error "Unsupported Distro, exiting."
fi

## Install apt Dependencies
run_cmd apt-get install -y \
    locales \
    nano \
    git \
    curl \
    jq \
    gpg-agent \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    python3-testresources \
    python3-apt \
    python3-venv \
    || error "Failed to install apt dependencies"

# Generate en_US.UTF-8 locale if it doesn't already exist
if ! locale -a | grep -q "^en_US.UTF-8"; then
    run_cmd locale-gen en_US.UTF-8 || error "Failed to generate locale."
fi

# Update locale
run_cmd update-locale LC_ALL=en_US.UTF-8 || error "Failed to update locale."

# Export the locale for the current script
export LC_ALL=en_US.UTF-8

# Check if the correct locale is active; if not, try reconfiguring locales
if [ "$(locale | grep 'LC_ALL' | cut -d= -f2 | tr -d '"')" != "en_US.UTF-8" ]; then
    echo "Locale en_US.UTF-8 is not set, trying to reconfigure locales..."
    run_cmd dpkg-reconfigure locales

    # Check again if the correct locale is active
    if [ "$(locale | grep 'LC_ALL' | cut -d= -f2 | tr -d '"')" != "en_US.UTF-8" ]; then
        error "Locale en_US.UTF-8 still not set."
    fi
fi

echo "Locale set to en_US.UTF-8"

cd /srv/ansible || error "Failed to change directory to /srv/ansible"

if [[ $release =~ (focal|jammy)$ ]]; then
    echo "${release^}, deploying venv with Python 3.12."
    run_cmd add-apt-repository ppa:deadsnakes/ppa --yes \
        || error "Failed to add deadsnakes repository"
    run_cmd apt install python3.12 python3.12-dev python3.12-distutils python3.12-venv -y \
        || error "Failed to install Python 3.12"
    install_pip
    run_cmd python3.12 -m venv venv \
        || error "Failed to create venv using Python 3.12"

elif [[ $release =~ (noble)$ ]]; then
    echo "Noble, deploying venv with Python 3.12."
    # Cannot use pypa install method with Noble due to PEP 668
    run_cmd apt-get install -y python3-pip
    run_cmd python3.12 -m venv venv || error "Failed to create venv using Python 3."

else
    error "Unsupported Distro, exiting."
fi

## Install pip3 Dependencies
run_cmd $PYTHON3_CMD \
    pip setuptools wheel \
    || error "Failed to install pip setuptools and wheel with $PYTHON3_CMD"
run_cmd $PYTHON3_CMD \
    --requirement /srv/git/sb/requirements-saltbox.txt \
    || error "Failed to install pip3 dependencies with $PYTHON3_CMD"

run_cmd cp /srv/ansible/venv/bin/ansible* /usr/local/bin/ \
    || error "Failed to copy ansible binaries to /usr/local/bin"
