#!/bin/bash
#########################################################################
# Title:         Saltbox: SB Script                                     #
# Author(s):     desimaniac, chazlarson, salty                          #
# URL:           https://github.com/saltyorg/sb                         #
# --                                                                    #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Privilege Escalation
################################

# Restart script in SUDO
# https://unix.stackexchange.com/a/28793

if [ $EUID != 0 ]; then
  sudo "$0" "$@"
  exit $?
fi

################################
# Scripts
################################

source /srv/git/sb/yaml.sh
create_variables /srv/git/saltbox/accounts.yml

################################
# Variables
################################

# Ansible
ANSIBLE_PLAYBOOK_BINARY_PATH="/usr/local/bin/ansible-playbook"

# Saltbox
SALTBOX_REPO_PATH="/srv/git/saltbox"
SALTBOX_PLAYBOOK_PATH="$SALTBOX_REPO_PATH/saltbox.yml"

# Sandbox
SANDBOX_REPO_PATH="/opt/sandbox"
SANDBOX_PLAYBOOK_PATH="$SANDBOX_REPO_PATH/sandbox.yml"

# Saltbox_mod
SALTBOXMOD_REPO_PATH="/opt/saltbox_mod"
SALTBOXMOD_PLAYBOOK_PATH="$SALTBOXMOD_REPO_PATH/saltbox_mod.yml"

# SB
SB_REPO_PATH="/srv/git/sb"

readonly PYTHON_CMD_SUFFIX="-m pip install \
                              --timeout=360 \
                              --no-cache-dir \
                              --disable-pip-version-check \
                              --upgrade"
readonly PYTHON3_CMD="/srv/ansible/venv/bin/python3 $PYTHON_CMD_SUFFIX"

################################
# Functions
################################

git_fetch_and_reset () {
  git fetch --quiet >/dev/null
  git clean --quiet -df >/dev/null
  git reset --quiet --hard "@{u}" >/dev/null
  git checkout --quiet "${SALTBOX_BRANCH:-master}" >/dev/null
  git clean --quiet -df >/dev/null
  git reset --quiet --hard "@{u}" >/dev/null
  git submodule update --init --recursive
  chmod 664 "${SALTBOX_REPO_PATH}/ansible.cfg"
  # shellcheck disable=SC2154
  chown -R "${user_name}":"${user_name}" "${SALTBOX_REPO_PATH}"
}

git_fetch_and_reset_sandbox () {
  git fetch --quiet >/dev/null
  git clean --quiet -df >/dev/null
  git reset --quiet --hard "@{u}" >/dev/null
  git checkout --quiet "${SANDBOX_BRANCH:-master}" >/dev/null
  git clean --quiet -df >/dev/null
  git reset --quiet --hard "@{u}" >/dev/null
  git submodule update --init --recursive

  if [[ ! -f "${SANDBOX_REPO_PATH}/ansible.cfg" ]]
  then
    cp "${SANDBOX_REPO_PATH}/defaults/ansible.cfg.default" "${SANDBOX_REPO_PATH}/ansible.cfg"
  fi

  chmod 664 "${SANDBOX_REPO_PATH}/ansible.cfg"
  chown -R "${user_name}":"${user_name}" "${SANDBOX_REPO_PATH}"
}

git_fetch_and_reset_sb () {
  git fetch --quiet >/dev/null
  git clean --quiet -df >/dev/null
  git reset --quiet --hard "@{u}" >/dev/null
  git checkout --quiet master >/dev/null
  git clean --quiet -df >/dev/null
  git reset --quiet --hard "@{u}" >/dev/null
  git submodule update --init --recursive
  chmod 775 "${SB_REPO_PATH}/sb.sh"
}

run_playbook_sb () {
  local arguments=$*

  cd "${SALTBOX_REPO_PATH}" || exit

  # shellcheck disable=SC2086
  "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
    "${SALTBOX_PLAYBOOK_PATH}" \
    --become \
    ${arguments}

  local return_code=$?

  cd - >/dev/null || exit

  if [ $return_code -ne 0 ]; then
    echo "========================="
    echo ""
    if [ $return_code -eq 99 ]; then
      echo "Error: Playbook run was aborted by the user."
    else
      echo "Error: Playbook run failed, scroll up to the failed task to review."
    fi
    echo ""
    exit
  fi
}

run_playbook_sandbox () {
  local arguments=$*

  cd "${SANDBOX_REPO_PATH}" || exit

  # shellcheck disable=SC2086
  "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
    "${SANDBOX_PLAYBOOK_PATH}" \
    --become \
    ${arguments}

  local return_code=$?

  cd - >/dev/null || exit

  if [ $return_code -ne 0 ]; then
    echo "========================="
    echo ""
    if [ $return_code -eq 99 ]; then
      echo "Error: Playbook run was aborted by the user."
    else
      echo "Error: Playbook run failed, scroll up to the failed task to review."
    fi
    echo ""
    exit
  fi
}

run_playbook_saltboxmod () {
  local arguments=$*

  cd "${SALTBOXMOD_REPO_PATH}" || exit

  # shellcheck disable=SC2086
  "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
    "${SALTBOXMOD_PLAYBOOK_PATH}" \
    --become \
    ${arguments}

  local return_code=$?

  cd - >/dev/null || exit

  if [ $return_code -ne 0 ]; then
    echo "========================="
    echo ""
    if [ $return_code -eq 99 ]; then
      echo "Error: Playbook run was aborted by the user."
    else
      echo "Error: Playbook run failed, scroll up to the failed task to review."
    fi
    echo ""
    exit
  fi
}

install () {
  local arg=("$@")

  if [ -z "$arg" ]
  then
    echo -e "No install tag was provided.\n"
    usage
    exit 1
  fi

  # Remove space after comma
  # shellcheck disable=SC2128,SC2001
  local arg_clean
  arg_clean=${arg//, /,}

  # Split tags from extra arguments
  # https://stackoverflow.com/a/10520842
  local re="^(\S+)\s+(-.*)?$"
  if [[ "$arg_clean" =~ $re ]]; then
    local tags_arg="${BASH_REMATCH[1]}"
    local extra_arg="${BASH_REMATCH[2]}"
  else
      tags_arg="$arg_clean"
  fi

  # Save tags into 'tags' array
  # shellcheck disable=SC2206
  local tags_tmp=(${tags_arg//,/ })

  # Remove duplicate entries from array
  # https://stackoverflow.com/a/31736999
  local tags=()
  readarray -t tags < <(printf '%s\n' "${tags_tmp[@]}" | awk '!x[$0]++')

  # Build SB/Sandbox/Saltbox-mod tag arrays
  local tags_sb
  local tags_sandbox
  local tags_saltboxmod

  for i in "${!tags[@]}"
  do
    if [[ ${tags[i]} == sandbox-* ]]; then
      tags_sandbox="${tags_sandbox}${tags_sandbox:+,}${tags[i]##sandbox-}"
    elif [[ ${tags[i]} == mod-* ]]; then
      tags_saltboxmod="${tags_saltboxmod}${tags_saltboxmod:+,}${tags[i]##mod-}"
    else
      tags_sb="${tags_sb}${tags_sb:+,}${tags[i]}"
    fi
  done

  # Saltbox Ansible Playbook
  if [[ -n "$tags_sb" ]]; then
    # Build arguments
    local arguments_sb="--tags $tags_sb"

    if [[ -n "$extra_arg" ]]; then
      arguments_sb="${arguments_sb} ${extra_arg}"
    fi

    # Run playbook
    echo ""
    echo "Running Saltbox Tags: ${tags_sb//,/,  }"
    echo ""
    run_playbook_sb "$arguments_sb"
    echo ""
  fi

  # Sandbox Ansible Playbook
  if [[ -n "$tags_sandbox" ]]; then
    # Build arguments
    local arguments_sandbox="--tags $tags_sandbox"

    if [[ -n "$extra_arg" ]]; then
      arguments_sandbox="${arguments_sandbox} ${extra_arg}"
    fi

    # Run playbook
    echo "========================="
    echo ""
    echo "Running Sandbox Tags: ${tags_sandbox//,/,  }"
    echo ""
    run_playbook_sandbox "$arguments_sandbox"
    echo ""
  fi

  # Saltbox_mod Ansible Playbook
  if [[ -n "$tags_saltboxmod" ]]; then
    # Build arguments
    local arguments_saltboxmod="--tags $tags_saltboxmod"

    if [[ -n "$extra_arg" ]]; then
        arguments_saltboxmod="${arguments_saltboxmod} ${extra_arg}"
    fi

    # Run playbook
    echo "========================="
    echo ""
    echo "Running Saltbox_mod Tags: ${tags_saltboxmod//,/,  }"
    echo ""
    run_playbook_saltboxmod "$arguments_saltboxmod"
    echo ""
  fi
}

update () {
  deploy_ansible_venv

  if [[ -d "${SALTBOX_REPO_PATH}" ]]
  then
    echo -e "Updating Saltbox...\n"

    cd "${SALTBOX_REPO_PATH}" || exit

    git_fetch_and_reset

    bash /srv/git/saltbox/scripts/update.sh

    local returnValue=$?

    if [ $returnValue -ne 0 ]; then
      exit $returnValue
    fi

    cp /srv/ansible/venv/bin/ansible* /usr/local/bin/
    sed -i 's/\/usr\/bin\/python3/\/srv\/ansible\/venv\/bin\/python3/g' /srv/git/saltbox/ansible.cfg

    run_playbook_sb "--tags settings" && echo -e '\n'

    echo -e "Update Completed."
  else
    echo -e "Saltbox folder not present."
  fi
}

sandbox-update () {
  if [[ -d "${SANDBOX_REPO_PATH}" ]]
  then
    echo -e "Updating Sandbox...\n"

    cd "${SANDBOX_REPO_PATH}" || exit

    git_fetch_and_reset_sandbox

    sed -i 's/\/usr\/bin\/python3/\/srv\/ansible\/venv\/bin\/python3/g' /opt/sandbox/ansible.cfg

    run_playbook_sandbox "--tags settings" && echo -e '\n'

    echo -e "Update Completed."
  fi
}

sb-update () {
  echo -e "Updating sb...\n"

  cd "${SB_REPO_PATH}" || exit

  git_fetch_and_reset_sb

  echo -e "Update Completed."
}

sb-list ()  {
  if [[ -d "${SALTBOX_REPO_PATH}" ]]
  then
    echo -e "Saltbox tags:\n"

    cd "${SALTBOX_REPO_PATH}" || exit

    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
      "${SALTBOX_PLAYBOOK_PATH}" \
      --become \
      --list-tags --skip-tags "always" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | sed 's/[][]//g' | cut -c2- | sed 's/, /\n/g' | column

    echo -e "\n"

    cd - >/dev/null || exit
  else
    echo -e "Saltbox folder not present.\n"
  fi
}

sandbox-list () {
  if [[ -d "${SANDBOX_REPO_PATH}" ]]
  then
    echo -e "Sandbox tags (prepend sandbox-):\n"

    cd "${SANDBOX_REPO_PATH}" || exit
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
      "${SANDBOX_PLAYBOOK_PATH}" \
      --become \
      --list-tags --skip-tags "always,sanity_check" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | sed 's/[][]//g' | cut -c2- | sed 's/, /\n/g' | column

    echo -e "\n"

    cd - >/dev/null || exit
  fi
}

saltboxmod-list () {
  if [[ -d "${SALTBOXMOD_REPO_PATH}" ]]
  then
    echo -e "Saltbox_mod tags (prepend mod-):\n"

    cd "${SALTBOXMOD_REPO_PATH}" || exit
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
      "${SALTBOXMOD_PLAYBOOK_PATH}" \
      --become \
      --list-tags --skip-tags "always,sanity_check" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | sed 's/[][]//g' | cut -c2- | sed 's/, /\n/g' | column

    echo -e "\n"

    cd - >/dev/null || exit
    fi
}

saltbox-branch () {
  deploy_ansible_venv

  if [[ -d "${SALTBOX_REPO_PATH}" ]]
  then
    echo -e "Changing Saltbox branch to $1...\n"

    cd "${SALTBOX_REPO_PATH}" || exit

    SALTBOX_BRANCH=$1

    git_fetch_and_reset

    bash /srv/git/saltbox/scripts/update.sh

    local returnValue=$?

    if [ $returnValue -ne 0 ]; then
      exit $returnValue
    fi

    cp /srv/ansible/venv/bin/ansible* /usr/local/bin/
    sed -i 's/\/usr\/bin\/python3/\/srv\/ansible\/venv\/bin\/python3/g' /srv/git/saltbox/ansible.cfg

    run_playbook_sb "--tags settings" && echo -e '\n'

    echo "Branch change and update completed."
  else
    echo "Saltbox folder not present."
  fi
}

sandbox-branch () {
  if [[ -d "${SANDBOX_REPO_PATH}" ]]
  then
    echo -e "Changing Sandbox branch to $1...\n"

    cd "${SANDBOX_REPO_PATH}" || exit

    SANDBOX_BRANCH=$1

    git_fetch_and_reset_sandbox

    run_playbook_sandbox "--tags settings" && echo -e '\n'

    echo "Branch change and update completed."
  fi
}

bench () {
  wget -qO- bench.sh | bash
}

deploy_ansible_venv () {
  if [[ ! -d "/srv/ansible" ]]
  then
    mkdir -p /srv/ansible
    cd /srv/ansible || exit
    release=$(lsb_release -cs)

    if [[ $release =~ (focal)$ ]]; then
      echo "Focal, deploying venv with Python3.10."
      add-apt-repository ppa:deadsnakes/ppa --yes
      apt install python3.10 python3.10-dev python3.10-distutils python3.10-venv -y
      add-apt-repository ppa:deadsnakes/ppa -r --yes
      rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list
      rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list.save
      python3.10 -m venv venv
    elif [[ $release =~ (jammy)$ ]]; then
      echo "Jammy, deploying venv with Python3."
      python3 -m venv venv
    else
      echo "Unsupported Distro, defaulting to Python3."
      python3 -m venv venv
    fi
  else
    /srv/ansible/venv/bin/python3 --version | grep -q '^Python 3\.10.'
    local python_version_valid=$?

    if [ $python_version_valid -eq 0 ]; then
      echo "Python venv is running with Python 3.10."
    else
      echo "Python venv is not running with Python 3.10. Recreating."
      recreate-venv
    fi
  fi

  ## Install pip3
  cd /tmp || exit
  curl -sLO https://bootstrap.pypa.io/get-pip.py
  python3 get-pip.py

  $PYTHON3_CMD \
    tld argon2_cffi ndg-httpsclient \
    dnspython lxml jmespath \
    passlib PyMySQL docker \
    pyOpenSSL requests netaddr \
    jinja2

  chown -R "${user_name}":"${user_name}" "/srv/ansible"
}

list () {
  sb-list
  sandbox-list
  saltboxmod-list
}

update-ansible () {
  bash "/srv/git/saltbox/scripts/update.sh"
}

recreate-venv () {
  echo "Recreating the Ansible venv."

  # Check for supported Ubuntu Releases
  release=$(lsb_release -cs)

  rm -rf /srv/ansible

  if [[ $release =~ (focal)$ ]]; then
    sudo add-apt-repository ppa:deadsnakes/ppa --yes
    sudo apt install python3.10 python3.10-dev python3.10-distutils python3.10-venv -y
    sudo add-apt-repository ppa:deadsnakes/ppa -r --yes
    sudo rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list
    sudo rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list.save
    python3.10 -m ensurepip

    mkdir -p /srv/ansible
    cd /srv/ansible || exit
    python3.10 -m venv venv
  elif [[ $release =~ (jammy)$ ]]; then
    mkdir -p /srv/ansible
    cd /srv/ansible || exit
    python3 -m venv venv
  fi

  bash /srv/git/saltbox/scripts/update.sh

  local returnValue=$?

  if [ $returnValue -ne 0 ]; then
    exit $returnValue
  fi

  cp /srv/ansible/venv/bin/ansible* /usr/local/bin/
  echo "Done recreating the Ansible venv."

  ## Install pip3
  cd /tmp || exit
  curl -sLO https://bootstrap.pypa.io/get-pip.py
  python3 get-pip.py

  $PYTHON3_CMD \
    tld argon2_cffi ndg-httpsclient \
    dnspython lxml jmespath \
    passlib PyMySQL docker \
    pyOpenSSL requests netaddr \
    jinja2

  chown -R "${user_name}":"${user_name}" "/srv/ansible"
}

inventory () {
  local file_path="/srv/git/saltbox/inventories/host_vars/localhost.yml"
  local default_editor="nano"
  local approved_editors=("nano" "vim" "vi" "emacs" "gedit" "code")

  # Check if file exists
  if [[ ! -f "$file_path" ]]; then
      echo "Error: The inventory file 'localhost.yml' does not yet exist."
      return 1
  fi

  # Check if EDITOR is in the approved list
  local is_approved=0
  for editor in "${approved_editors[@]}"; do
    if [[ "${EDITOR}" == "$editor" ]]; then
      is_approved=1
      break
    fi
  done

  if [[ "$is_approved" -eq 0 ]]; then
    if [[ -z "${EDITOR}" ]]; then
      # Use default if EDITOR is not set
      $default_editor "$file_path"
    else
      # Prompt for confirmation if EDITOR is not in approved list
      echo "The EDITOR variable is set to an unrecognized value: $EDITOR"
      read -p "Are you sure you want to use it to edit the file? (y/N) " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        ${EDITOR} "$file_path"
      else
        echo "Using default editor: $default_editor"
        $default_editor "$file_path"
      fi
    fi
  else
    ${EDITOR:-$default_editor} "$file_path"
  fi
}

usage () {
  echo "Usage:"
  echo "    sb update                     Updates Saltbox (resets the branch to master)."
  echo "    sb list                       List Saltbox tags."
  echo "    sb install <tag>              Install <tag>."
  echo "    sb bench                      Run bench.sh"
  echo "    sb recreate-venv              Re-create Ansible venv."
  echo "    sb inventory                  Opens the 'localhost.yml' inventory file."
  echo "    sb branch <branch>            Changes and updates the Saltbox branch."
  echo "    sb sandbox-branch <branch>    Changes and updates the Sandbox branch."
}

################################
# Update check
################################

cd "${SB_REPO_PATH}" || exit

git fetch
HEADHASH=$(git rev-parse HEAD)
UPSTREAMHASH=$(git rev-parse "master@{upstream}")

if [ "$HEADHASH" != "$UPSTREAMHASH" ]
then
  echo "Not up to date with origin. Updating."
  sb-update
  echo "Relaunching with previous arguments."
  sudo "$0" "$@"
  exit 0
fi

################################
# Argument Parser
################################

# https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/

roles=""  # Default to empty role

# Parse options
while getopts ":h" opt; do
  case ${opt} in
    h)
      usage
      exit 0
      ;;
   \?)
      echo "Invalid Option: -$OPTARG" 1>&2
      echo ""
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Parse commands
subcommand=$1; shift  # Remove 'sb' from the argument list
case "$subcommand" in

# Parse options to the various sub commands
  list)
    list
    ;;
  update)
    update
    sandbox-update
    ;;
  install)
    roles=${*}
    install "${roles}"
    ;;
  branch)
    saltbox-branch "${*}"
    ;;
  sandbox-branch)
    sandbox-branch "${*}"
    ;;
  recreate-venv)
    recreate-venv
    ;;
  bench)
    bench
    ;;
  inventory)
    inventory
    ;;
  "") echo "A command is required."
    echo ""
    usage
    exit 1
    ;;
  *)
    echo "Invalid Command: $subcommand"
    echo ""
    usage
    exit 1
    ;;
esac
