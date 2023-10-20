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

VERBOSE=true

readonly SYSCTL_PATH="/etc/sysctl.conf"
readonly PYTHON_CMD_SUFFIX="-m pip install \
                            --timeout=360 \
                            --no-cache-dir \
                            --disable-pip-version-check \
                            --upgrade"
readonly PYTHON3_CMD="/srv/ansible/venv/bin/python3 $PYTHON_CMD_SUFFIX"
readonly ANSIBLE=">=7.0.0,<8.0.0"

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
# Main
################################

$VERBOSE || exec &>/dev/null

## IPv6
if [ -f "$SYSCTL_PATH" ]; then
    ## Remove 'Disable IPv6' entries from sysctl
    sed -i -e '/^net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_PATH" \
        || error "Failed to modify $SYSCTL_PATH (1)"
    sed -i -e '/^net.ipv6.conf.default.disable_ipv6/d' "$SYSCTL_PATH" \
        || error "Failed to modify $SYSCTL_PATH (2)"
    sed -i -e '/^net.ipv6.conf.lo.disable_ipv6/d' "$SYSCTL_PATH" \
        || error "Failed to modify $SYSCTL_PATH (3)"
    sysctl -p || error "Failed to apply sysctl settings"
fi

## Environmental Variables
export DEBIAN_FRONTEND=noninteractive

## Install Pre-Dependencies
apt-get install -y \
    software-properties-common \
    apt-transport-https \
    || error "Failed to install pre-dependencies"
apt-get update || error "Failed to update apt-get repositories"

## Add apt repos
add-apt-repository main || error "Failed to add main repository"
add-apt-repository universe || error "Failed to add universe repository"
add-apt-repository restricted || error "Failed to add restricted repository"
add-apt-repository multiverse || error "Failed to add multiverse repository"
apt-get update || error "Failed to update apt-get repositories"

## Install apt Dependencies
apt-get install -y \
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
    python3-virtualenv \
    python3-venv \
    || error "Failed to install apt dependencies"

# Generate en_US.UTF-8 locale if it doesn't already exist
if ! locale -a | grep -q "^en_US.UTF-8"; then
    locale-gen en_US.UTF-8 || error "Failed to generate locale, attempting to continue..."
fi

# Update locale
update-locale LC_ALL=en_US.UTF-8 || error "Failed to update locale, attempting to continue..."

# Export the locale for the current script
export LC_ALL=en_US.UTF-8

# Check if the correct locale is active; if not, try reconfiguring locales
if [ "$(locale | grep 'LC_ALL' | cut -d= -f2 | tr -d '"')" != "en_US.UTF-8" ]; then
    echo "Locale en_US.UTF-8 is not set, trying to reconfigure locales..."
    dpkg-reconfigure locales

    # Check again if the correct locale is active
    if [ "$(locale | grep 'LC_ALL' | cut -d= -f2 | tr -d '"')" != "en_US.UTF-8" ]; then
        error "Locale en_US.UTF-8 still not set."
    fi
fi

echo "Locale set to en_US.UTF-8"

cd /srv/ansible || error "Failed to change directory to /srv/ansible"

# Check for supported Ubuntu Releases
release=$(lsb_release -cs) || error "Failed to determine Ubuntu release"

if [[ $release =~ (focal)$ ]]; then
    echo "Focal, deploying venv with Python3.10."
    add-apt-repository ppa:deadsnakes/ppa --yes \
        || error "Failed to add deadsnakes repository"
    apt install python3.10 python3.10-dev python3.10-distutils python3.10-venv -y \
        || error "Failed to install Python 3.10"
    add-apt-repository ppa:deadsnakes/ppa -r --yes \
        || error "Failed to remove deadsnakes repository"
    rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list \
        || error "Failed to remove repository list file"
    rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list.save \
        || error "Failed to remove repository list save file"
    python3.10 -m ensurepip \
        || error "Failed to ensure pip for Python 3.10"
    python3.10 -m venv venv \
        || error "Failed to create venv using Python 3.10"

elif [[ $release =~ (jammy)$ ]]; then
    echo "Jammy, deploying venv with Python3."
    python3 -m venv venv || error "Failed to create venv using Python 3"

else
    error "Unsupported Distro, exiting."
fi

## Install pip3
cd /tmp || error "Failed to change directory to /tmp"
curl -sLO https://bootstrap.pypa.io/get-pip.py \
    || error "Failed to download get-pip.py"
python3 get-pip.py || error "Failed to install pip3"

## Install pip3 Dependencies
$PYTHON3_CMD \
    pip setuptools wheel \
    || error "Failed to install pip setuptools and wheel with $PYTHON3_CMD"
$PYTHON3_CMD \
    pyOpenSSL requests netaddr \
    jmespath jinja2 docker \
    ruamel.yaml tld argon2_cffi \
    ndg-httpsclient dnspython lxml \
    jmespath passlib PyMySQL \
    ansible$ANSIBLE \
    || error "Failed to install pip3 dependencies with $PYTHON3_CMD"

cp /srv/ansible/venv/bin/ansible* /usr/local/bin/ \
    || error "Failed to copy ansible binaries to /usr/local/bin"

## Copy /usr/local/bin/pip to /usr/bin/pip
if [ -f /usr/local/bin/pip3 ]; then
    cp /usr/local/bin/pip3 /usr/bin/pip3 || error "Failed to copy pip3 to /usr/bin"
else
    error "/usr/local/bin/pip3 not found"
fi

