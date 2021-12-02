# Functions declaration

function get_envname() {
	[[ "$(echo "${@}" | grep -Ew '\-\-envname')" != "" ]] && envname="$(echo "${@}" | awk -F 'envname ' '{print $NF}' | cut -d'-' -f1 | xargs)"
	echo "${envname}"
}

function check_arguments() {
	if [[ "$(echo "${@}" | grep -Ew '\-\-envname')" == "" ]]
	then
		printf "\nEnvironment name is required!\nRe-run the script with %s--envname%s <environment name as defined under Inventories>\n\n" "${BOLD}" "${NORMAL}"
		exit 1
	else
		[[ $(wc -w <<< "$(get_envname "${@}")") -ge 2 ]] && printf "\nYou can deploy only one environment at a time. Aborting!\n\n" && exit 1
		[[ $(wc -w <<< "$(get_envname "${@}")") -lt 1 ]] && printf "\nYou need to specify at least one environment. Aborting!\n\n" && exit 1
	fi
}

function check_repeat_job() {
	repeat_job="$( pgrep "${ENAME}" | grep "$(basename "${0}" | awk -F '.' '{print $1}')" | grep -v "${PID}" )"
}

function check_hosts_limit() {
	local ARG_NAME
	local MYACTION
	local NEWARGS
	[[ "$(echo "${@}" | grep -Ew '\-\-limit')" != "" ]] && [[ "$(echo "${@}" | grep -w 'vcenter')" == "" ]] && ARG_NAME="--limit" && MYACTION="add"
	[[ "$(echo "${@}" | grep -Ew '\-l')" != "" ]] && [[ "$(echo "${@}" | grep -w 'vcenter')" == "" ]] && ARG_NAME="-l" && MYACTION="add"
	if [[ ${MYACTION} == "add" ]]
	then
		local MYHOSTS
		local MYTAGS
		local UPDATE_ARGS
		local VCENTERS
		MYHOSTS=$(echo "${@}" | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}')
		[[ "$(echo "${@}" | grep -Ew '\-\-tags')" != "" ]] && MYTAGS=$(echo "${@}" | awk -F '--tags ' '{print $NF}' | awk -F ' -' '{print $1}')
		[[ "${MYTAGS}" == "" ]] && UPDATE_ARGS=1
		[[ "$(echo "${MYTAGS}" | grep -Ew 'vm_creation|capcheck|infra_configure')" != "" ]] && UPDATE_ARGS=1
		[[ "$(echo "${MYTAGS}" | grep -Ew 'infra_build_nodes')" != "" ]] && UPDATE_ARGS=2
		[[ "$(echo "${MYHOSTS}" | grep 'dr')" != "" ]] && VCENTERS='vcenter,drvcenter' || VCENTERS='vcenter'
		if [[ ${UPDATE_ARGS} -eq 1 ]]
		then
			NEWARGS=$(echo "${@}" | sed "s/${MYHOSTS}/${MYHOSTS},${VCENTERS}/")
		elif [[ ${UPDATE_ARGS} -eq 2 ]]
		then
			NEWARGS=$(echo "${@}" | sed "s/${MYHOSTS}/${MYHOSTS},${VCENTERS},nexus/")
		else
			NEWARGS="${@}"
		fi
	else
		NEWARGS="${@}"
	fi
	echo "${NEWARGS}"
}

function check_concurrency() {
	pgrep "$(basename "${0}")" | grep -v "${PID}"
}

function clean_arguments() {
	# Remove --envname argument from script arguments
	local OPTION_NAME
	local ENVNAME
	local NEWARGS
	OPTION_NAME="--envname"
	ENVNAME="${1}"
	if [[ "$(echo "${@}" | grep -Ew '\-\-envname')" != "" ]]
	then
		shift
		NEWARGS=$(echo "${@}" | sed "s/${OPTION_NAME} ${ENVNAME}//")
	else
		NEWARGS="${@}"
	fi
	echo "${NEWARGS}"
}

function git_config() {
	if [[ "$(which git 2>/dev/null)" != "" ]]
	then
		git config remote.origin.url &>/dev/null || echo "You are not authorized to use this automation. Aborting!"
		git config remote.origin.url &>/dev/null || exit 1
		if [[ "$(git config user.name)" == "" ]]
		then
			if [[ "$(git config remote.origin.url | grep "\/\/.*@")" == "" ]]
			then
				IFS=' ' read -rp "Enter your full name [ENTER]: " NAME SURNAME && git config user.name "${NAME} ${SURNAME}" || EC=1
			else
				IFS=' ' read -rp "Enter your full name [ENTER]: " NAME SURNAME && [[ "${SURNAME}" != "" ]] && [[ "$(git config remote.origin.url | sed -e 's/.*\/\/\(.*\)@.*/\1/')" == *"$(echo ${SURNAME:0:5} | tr '[:upper:]' '[:lower:]')"* ]] && git config user.name "${NAME} ${SURNAME}" || EC=1
			fi
		fi
		[[ ${EC} -eq 1 ]] && echo "Invalid full name. Aborting!" && exit ${EC}
		if [[ "$(git config user.email)" == "" ]]
		then
			NAME=$(git config user.name | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
			SURNAME=$(git config user.name | awk '{print $NF}' | tr '[:upper:]' '[:lower:]')
			if [[ "$(git config remote.origin.url | grep "\/\/.*@")" == "" ]]
			then
				read -rp "Enter your email address [ENTER]: " GIT_EMAIL_ADDRESS && [[ "${GIT_EMAIL_ADDRESS}" != "" ]] && [[ "$(echo "${GIT_EMAIL_ADDRESS}" | cut -d '@' -f1)" == *"$(echo ${NAME:0:2} | tr '[:upper:]' '[:lower:]')"* ]] && [[ "$(echo "${GIT_EMAIL_ADDRESS}" | cut -d '@' -f1)" == *"$(echo ${SURNAME:0:5} | tr '[:upper:]' '[:lower:]')"* ]] && git config user.email "${GIT_EMAIL_ADDRESS}" && git config remote.origin.url "$(git config remote.origin.url | sed -e "s|//\(\w\)|//$(echo "${GIT_EMAIL_ADDRESS}" | cut -d '@' -f1)@\1|")" || EC=1
			else
				read -rp "Enter your email address [ENTER]: " GIT_EMAIL_ADDRESS && [[ "${GIT_EMAIL_ADDRESS}" != "" ]] && [[ "$(echo "${GIT_EMAIL_ADDRESS}" | cut -d '@' -f1)" == *"$(echo ${NAME:0:2} | tr '[:upper:]' '[:lower:]')"* ]] && [[ "$(echo "${GIT_EMAIL_ADDRESS}" | cut -d '@' -f1)" == *"$(echo ${SURNAME:0:5} | tr '[:upper:]' '[:lower:]')"* ]] && [[ "$(git config remote.origin.url)" == *"$(echo "${GIT_EMAIL_ADDRESS}" | cut -d '@' -f1)"* ]] && git config user.email "${GIT_EMAIL_ADDRESS}" || EC=1
			fi
		else
			if [[ "$(git config remote.origin.url | grep "\/\/.*@")" == "" ]]
			then
				git config remote.origin.url "$(git config remote.origin.url | sed -e "s|//\(\w\)|//$(git config user.email | cut -d '@' -f1)@\1|")"
			fi
		fi
		[[ ${EC} -eq 1 ]] && echo "Invalid email address. Aborting!" && exit ${EC}
	else
		echo "Please ensure git is installed on this machine before running script. Aborting!" && exit 1
	fi
}

function get_sudopass() {
	read -rsp "Enter localhost's sudo password and press [ENTER]: " SP
	sudo -S echo "Thanks" &>/dev/null <<< "${SP}"
	if [[ "${?}" == "0" ]]
	then
		echo "${SP}"
		return 0
	else
		echo "Password is incorrect. Aborting!"
		return 1
	fi
}

function get_centos_release() {
	cat /etc/centos-release | sed 's/^.*\([0-9]\{1,\}\)\.[0-9]\{1,\}\.[0-9]\{1,\}.*$/\1/'
}

function get_creds_prefix() {
    local FILETOCHECK
    local DATACENTER
    local CREDS_PREFIX
	[[ -f "${SYS_DEF}" ]] && FILETOCHECK="${SYS_DEF}" || FILETOCHECK="${SYS_ALL}"
	DATACENTER=$(cat "${FILETOCHECK}" | sed "/^$/d" | grep -A14 -P "^datacenter:$" | sed -n "/${1}:/,+2p" | sed -n "/name:/,1p" | awk -F ': ' '{print $NF}')
	if [[ "${?}" == "0" ]] && [[ "${DATACENTER}" != "" ]] && [[ "${DATACENTER}" != "''" ]]
	then
		case ${DATACENTER} in
			Alln1 | RTP5 | *Build*)
				CREDS_PREFIX='PROD_'
				;;
			RTP-Staging)
				CREDS_PREFIX='STG_'
				;;
			PAE-External)
				CREDS_PREFIX='PAEEXT_'
				;;
			*)
				CREDS_PREFIX='PAETEST_'
				;;
		esac
		echo ${CREDS_PREFIX}
		return 0
	else
		return 1
	fi
}

function get_svc_cred() {
	if [[ $(get_creds_prefix ${1}) ]]
	then
		view_vault vars/passwords.yml Bash/get_common_vault_pass.sh  | grep ^$(get_creds_prefix ${1})SVC_${2^^} | cut -d "'" -f2
		return 0
	else
		return 1
	fi
}

function get_proxy() {
	local MYPROXY
	local PUBLIC_ADDRESS
	chmod +x Bash/get*
	grep '^proxy.*:.*@*' /etc/environment /etc/profile ~/.bashrc ~/.bash_profile &>/dev/null && [[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
	MYPROXY=$(grep -r "^proxy.*=.*" /etc/environment /etc/profile ~/.bashrc ~/.bash_profile | cut -d '"' -f2 | uniq)
	[[ "${MYPROXY}" != "" ]] && [[ "$(echo "${MYPROXY}" | grep http)" == "" ]] && MYPROXY=http://${MYPROXY}
	PUBLIC_ADDRESS="https://time.google.com"
	if [[ "${MYPROXY}" == "" ]]
	then
		curl ${PUBLIC_ADDRESS} &>/dev/null
		if [[ ${?} -eq 0 ]]
		then
			echo "${MYPROXY}"
			return 0
		else
			echo -e "Unable to find proxy configuration in /etc/environment /etc/profile ~/.bashrc ~/.bash_profile. Aborting!\n"
			return 1
		fi
	else
		curl --proxy "${MYPROXY}" "${PUBLIC_ADDRESS}" &>/dev/null
		if [[ ${?} -eq 0 ]]
		then
			echo "${MYPROXY}"
			return 0
		else
			[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			if [[ "$(which ansible 2>/dev/null)" == "" ]]
			then
				read -rp "Enter a valid proxy username and press [ENTER]: " PPUSER
				read -rsp "Enter a valid proxy password and press [ENTER]: " PPPASS
			else
				get_svc_cred primary user 1>/dev/null && read -r PPUSER <<< "$(get_svc_cred primary user)"
				get_svc_cred primary pass 1>/dev/null && read -r PPPASS <<< "$(get_svc_cred primary pass)"
				get_svc_cred secondary user 1>/dev/null && read -r SPUSER <<< "$(get_svc_cred secondary user)"
				get_svc_cred secondary pass 1>/dev/null && read -r SPPASS <<< "$(get_svc_cred secondary pass)"
			fi
			MYPROXY=$(echo "${MYPROXY}" | sed -e "s|//.*@|//|g" -e "s|//|//${PPUSER}:${PPPASS}@|g")
			curl --proxy "${MYPROXY}" "${PUBLIC_ADDRESS}" &>/dev/null
			if [[ ${?} -eq 0 ]]
			then
				echo "${MYPROXY}"
				return 0
			else
				if [[ -n "${SPUSER+x}" ]] && [[ -n "${SPPASS+x}" ]]
				then
					MYPROXY=$(echo "${MYPROXY}" | sed -e "s|//.*@|//|g" -e "s|//|//${SPUSER}:${SPPASS}@|g")
					curl --proxy "${MYPROXY}" "${PUBLIC_ADDRESS}" &>/dev/null
					if [[ ${?} -eq 0 ]]
					then
						echo "${MYPROXY}"
						return 0
					else
						[[ ${debug} == 1 ]] && debug=0 && set -x
						echo -e "Proxy credentials are not valid. Aborting!\n"
						return 1
					fi
				fi
			fi
		fi
	fi
}

function add_proxy_yum() {
	[[ ${#} -ne 2 ]] && echo -e "\nFunction add_proxy_yum requires 2 arguments\n" && exit 1
	if [[ "${1}" != "" ]]
	then
		if [[ "${2}" != "" ]]
		then
			[[ "$(echo "${1}" | grep ':.*@' &>/dev/null;echo ${?})" -eq 0 ]] && [[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			grep '^proxy' /etc/yum.conf &>/dev/null || sudo -S sed -i "s|^\(\[main\]\)$|\1\nproxy=${1}|" /etc/yum.conf <<< "${2}"
			[[ ${debug} == 1 ]] && debug=0 && set -x
		else
			echo -e "\nUnable to edit /etc/yum.conf without sudo password. Aborting!\n"
			exit 1
		fi
	fi
}

function remove_proxy_yum() {
	if [[ "${1}" != "" ]]
	then
		grep proxy /etc/yum.conf &>/dev/null && sudo -S sed -i '/^proxy=.*$/,+d' /etc/yum.conf <<< "${1}"
	else
		echo -e "\nUnable to edit /etc/yum.conf without sudo password. Aborting!\n"
		exit 1
	fi
}

function install_packages() {
	[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
	[[ "$(echo "${PROXY_ADDRESS}" | grep ':.*@' &>/dev/null;echo ${?})" -ne 0 ]] && [[ ${debug} == 1 ]] && debug=0 && set -x
	local OS_VERSION
	OS_VERSION=$(get_centos_release)
	for pkg in ${PKG_LIST}
	do
		[[ ${OS_VERSION} -eq 8 && "$(echo "${pkg}" | grep python3)" != "" ]] && continue
		if [[ "$(yum list installed "${pkg}" &>/dev/null;echo ${?})" == "1" ]]
		then
			if [[ "${SUDO_PASS}" == "" ]]
			then
				echo
				SUDO_PASS=$(get_sudopass) || FS=${?}
				[[ "${FS}" == 1 ]] && echo -e "\n${SUDO_PASS}\n" && exit ${FS}
			fi
			add_proxy_yum "${PROXY_ADDRESS}" "${SUDO_PASS}"
			[[ "${pkg}" == "packer" ]] && sudo -S yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo <<< "${SUDO_PASS}" || EC=1
			[[ "${EC}" == 1 ]] && echo -e "\nUnable to add Packer repo. Aborting!\n" && exit ${EC}
			PKG_ARR=("${PKG_LIST}")
			[[ ${pkg} == "${PKG_ARR[0]}" ]] && printf "\n\nInstalling %s on localhost ..." "${pkg}" || printf "\nInstalling %s on localhost ..." "${pkg}"
			sudo -S yum install -y "${pkg}" --quiet <<< "${SUDO_PASS}" 2>/dev/null
			remove_proxy_yum "${SUDO_PASS}"
			[[ ${?} == 0 ]] && printf " Installed version %s\n" "$(yum list installed "${pkg}" | tail -1 | awk '{print $2}')" || exit 1
		fi
	done
	if [[ "$(python3 -m pip show pip | grep ^Version | awk -F ': ' '{print $NF}')" == "9.0.3" ]]
	then
		printf "\nUpgrading PIP to the latest version ..."
		python3 -m pip install --user --no-cache-dir --quiet -U pip --proxy="${PROXY_ADDRESS}"
		[[ ${?} == 0 ]] && printf " Installed version %s\n" "$(python3 -m pip show pip | grep ^Version | awk -F ': ' '{print $NF}')" || exit 1
	fi
	if [[ "$(ansible --version &>/dev/null; echo ${?})" != "0" ]]
	then
		printf "\nInstalling Ansible on localhost ..."
		[[ "$(echo "${PROXY_ADDRESS}" | grep ':.*@' &>/dev/null;echo ${?})" -eq 0 ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
		python3 -m pip install --user --no-cache-dir --quiet -I ansible=="${ANSIBLE_VERSION}" --proxy="${PROXY_ADDRESS}"
		[[ ${?} == 0 ]] && printf " Installed version %s\n" "${ANSIBLE_VERSION}" || exit 1
		[[ ${debug} == 1 ]] && debug=0 && set -x
	else
		if [[ "$(python3 -m pip show ansible | grep ^Version | awk -F ': ' '{print $NF}')" != "${ANSIBLE_VERSION}" ]]
		then
			python3 -m pip uninstall -y ansible
			find ~/.local -maxdepth 4 -name "ansible*" -exec rm -rf {} \;
			[[ "$(echo "${PROXY_ADDRESS}" | grep ':.*@' &>/dev/null;echo ${?})" -eq 0 ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			printf "\nInstalling Ansible on localhost ..."
			python3 -m pip install --user --no-cache-dir --quiet -I ansible=="${ANSIBLE_VERSION}" --proxy="${PROXY_ADDRESS}"
			[[ ${?} == 0 ]] && printf " Installed version %s\n" "${ANSIBLE_VERSION}" || exit 1
			[[ ${debug} == 1 ]] && debug=0 && set -x
		fi
	fi
}

function remove_hosts_arg() {
	# Remove --limit or -l argument from script arguments
	local ARG_NAME
	local MYACTION
	local NEWARGS
	[[ "$(echo "${@}" | grep -Ew '\-\-limit')" != "" ]] && ARG_NAME="--limit" && MYACTION="clean"
	[[ "$(echo "${@}" | grep -Ew '\-l')" != "" ]] && ARG_NAME="-l" && MYACTION="clean"
	if [[ ${MYACTION} == "clean" ]]
	then
        	local MYARGS
		MYARGS=$(echo "${@}" | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}')
		NEWARGS=$(echo "${@}" | sed "s/${ARG_NAME} ${MYARGS}//")
	else
		NEWARGS="${@}"
	fi
	echo "${NEWARGS}"
}

function remove_extra_vars_arg() {
	local ARG_NAME
	local MYACTION
	local NEWARGS
	# Remove --extra-vars or -e argument from script arguments
	[[ "$(echo "${@}" | grep -Ew '\-\-extra\-vars')" != "" ]] && ARG_NAME="--extra-vars" && MYACTION="clean"
	[[ "$(echo "${@}" | grep -Ew '\-e')" != "" ]] && ARG_NAME="-e" && MYACTION="clean"
	if [[ ${MYACTION} == "clean" ]]
	then
		local MYARGS
		MYARGS=$(echo "${@}" | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}')
		NEWARGS=$(echo "${@}" | sed "s|${ARG_NAME} ${MYARGS}||")
	else
		NEWARGS="${@}"
	fi
	echo "${NEWARGS}"
}

function install_pypkgs() {
	ansible-playbook playbooks/pypkgs.yml --extra-vars "{SYS_NAME: '${SYS_DEF}'}" $(remove_extra_vars_arg "$(remove_hosts_arg "${@}")") -e @"${ANSIBLE_VARS}" -v -e @"${PASSVAULT}" -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh
	INSTALL_PYPKGS_STATUS=${?}
	[[ ${INSTALL_PYPKGS_STATUS} != 0 ]] && echo -e "\n${BOLD}Unable to install Python packages successfully. Aborting!${NORMAL}" && exit 1
}

function get_inventory() {
	sed -i "/^vault_password_file.*$/,+d" "${ANSIBLE_CFG}"
	if [[ ${INSTALL_PYPKGS_STATUS} == 0 || "$(pwd | grep -i 'cdra')" != "" ]]
	then
		if [[ -f ${SYS_DEF} ]]
		then
			ansible-playbook playbooks/getinventory.yml --extra-vars "{SYS_NAME: '${SYS_DEF}'}" $(remove_extra_vars_arg "$(remove_hosts_arg "${@}")") -e @"${ANSIBLE_VARS}" -v
			GET_INVENTORY_STATUS=${?}
			[[ ${GET_INVENTORY_STATUS} != 0 ]] && exit 1
		elif [[ $(echo "${ENAME}" | grep -i mdr) != '' ]]
		then
			[[ -d ${INVENTORY_PATH} ]] && GET_INVENTORY_STATUS=0 || GET_INVENTORY_STATUS=1
			[[ ${GET_INVENTORY_STATUS} -ne 0 ]] && echo -e "\nInventory for ${BOLD}${ENAME}${NORMAL} system is not found. Aborting!" && exit 1
		else
			echo -e "\n${BOLD}Stack definition file for ${ENAME} cannot be found. Aborting!${NORMAL}"
			exit 1
		fi
	fi
}

function encrypt_vault() {
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && ansible-vault encrypt "${1}" --vault-password-file "${2}" &>/dev/null
}

function view_vault() {
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && ansible-vault view "${1}" --vault-password-file "${2}" 2> "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}"
	[[ $(grep "was not found" "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}") != "" ]] && sed -i "/^vault_password_file.*$/,+d" "${ANSIBLE_CFG}" && ansible-vault view "${1}" --vault-password-file "${2}" &>/dev/null
	rm -f "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}"
}

function check_updates() {
	[[ "$(echo "${PROXY_ADDRESS}" | grep ':.*@' &>/dev/null;echo ${?})" -ne 0 ]] && [[ ${debug} == 1 ]] && debug=0 && set -x
	if [[ "x$(git config user.name)" != "x" ]]
	then
		local localbranch
		local remotebranchlist
		localbranch=$(git branch|grep '*'|awk '{print $NF}')
		remotebranchlist=$(git branch -r)
		if [[ $(echo ${remotebranchlist}|grep '/'${localbranch}) ]]
		then
			[[ -f ${1} ]] && grep 'REPOPASS=' "${1}" 1>/dev/null && rm -f "${1}"
			if [[ -f ${1} ]]
			then
				local i
				local retries
				i=0
				retries=3
				while [[ ${i} -lt ${retries} ]]
				do
					[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
					if [[ ${REPOPASS} == "" ]]
					then
						[[ ${debug} == 1 ]] && set -x
						read -r REPOPASS <<< "$(view_vault "${1}" "${2}" | cut -d "'" -f2)"
					else
						break
					fi
					i=$((++i))
					[[ ${i} -eq ${retries} ]] && echo "Unable to decrypt Repository password vault. Exiting!" && exit 1
				done
			else
				echo
				read -rsp "Enter your Repository password [ENTER]: " REPOPASS
				[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
				[[ -f ${1} ]] && rm -f "${1}"
				printf "REPOPASS='%s'\n" "${REPOPASS}" > "${1}"
				encrypt_vault "${1}" "${2}"
				[[ ${debug} == 1 ]] && set -x
				echo
			fi
			git rev-parse --short HEAD &>/dev/null
			if [[ ${?} -eq 0 ]]
			then
				local LOCALID
				local REPOPWD
				local REMOTEID
				LOCALID=$(git rev-parse --short HEAD)
				[[ $(git config --get remote.origin.url | grep "www-github") == "" ]] && [[ ${http_proxy} != "" ]] && RESET_PROXY="true"
				for i in {1..3}
				do
					[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
					REPOPWD="${REPOPASS//@/%40}"
					REMOTEID=$([[ ${RESET_PROXY} ]] && unset https_proxy || git config http.proxy "${PROXY_ADDRESS}"; git ls-remote "$(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${REPOPWD}@|")" refs/heads/"$(git branch | grep '*' | awk '{print $NF}')" 2>"${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr | cut -c1-7)
					[[ ${debug} == 1 ]] && set -x
					[[ ${REMOTEID} == "" ]] && sleep 3 || break
				done
				if [[ "${REMOTEID}" == "" ]]
				then
					local REPO_ERR
					REPO_ERR="$(grep -i maintenance "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr)"
					if [[ "${REPO_ERR}" == "" ]]
					then
					 	printf "\nYour Repository credentials are invalid!\n\n" && rm -f "${1}" && rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr && exit
					else
					 	printf "\n%s" "${REPO_ERR}" && rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr && exit
					fi
				else
					rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr
				fi
				if [[ "${LOCALID}" != "${REMOTEID}" ]]
				then
					echo
					read -rp "Your installation package is not up to date. Updating it will overwrite any changes to tracked files. Do you want to update? ${BOLD}(y/n)${NORMAL}: " ANSWER
					echo ""
					if [[ "${ANSWER,,}" == "y" ]]
					then
						git reset -q --hard origin/"$(git branch | awk '{print $NF}')"
						git pull "$(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${REPOPASS}@|")" &>"${PWD}"/.pullerr && sed -i "s|${REPOPASS}|xxxxx|" "${PWD}"/.pullerr
						[[ ${?} == 0 ]] && echo -e "\nThe installation package has been updated. ${BOLD}Please re-run the script for the updates to take effect${NORMAL}\n\n"
						[[ ${?} != 0 ]] && echo -e "\nThe installation package update has failed with the following error:\n\n${BOLD}$(cat "${PWD}"/.pullerr)${NORMAL}\n\n"
						rm -f "${PWD}"/.pullerr
						EC='exit'
					else
						EC='continue'
					fi
				fi
				git config --get http.proxy 1>/dev/null && git config --remove-section http
				[[ ${RESET_PROXY} == "true" ]] && source ~/.bashrc /etc/profile /etc/environment
				${EC}
			fi
		fi
	fi
}

function get_hostsinplay() {
	local ENVS
	local HN
	ENVS="$(pgrep play.sh | grep envname | grep -v "${ENAME}" | awk -F 'envname ' '{print $NF}' | cut -d'-' -f1 | sort -u)"
	HN=""
	for env in ${ENVS}
	do
		HN="${HN}$(cat "${INVENTORY_PATH}"/hosts | awk '{print $1}' | grep -Ev '\[|=' | sed '/^$/d')"
	done
	echo "${HN}"
}

function get_sleeptime() {
	local HN
	local HOSTNUM
	HN=$(get_hostsinplay)
	HN=( "${HN}" )
	HOSTNUM=${#HN[@]}
	echo $((HOSTNUM + HOSTNUM / 4))
}

function get_hosts() {
	local ARG_NAME
	local MYACTION
	[[ "$(echo "${@}" | grep -Ew '\-\-limit')" != "" ]] && ARG_NAME="--limit" && MYACTION="get"
	[[ "$(echo "${@}" | grep -Ew '\-l')" != "" ]] && ARG_NAME="-l" && MYACTION="get"
	if [[ ${MYACTION} == "get" ]]
	then
		HOST_LIST=$(echo "${@}" | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}' | sed -e 's/,/ /g')
	else
		HOST_LIST=$(ansible all -i "${INVENTORY_PATH}" --list-hosts | grep -v host | sed -e 's/^\s*\(\w.*\)$/\1/g' | sort)
	fi
}

function check_mode() {
	[[ "$(echo "${@}" | grep -Ew '\-\-check')" != "" ]] && echo " in check mode " || echo " "
}

function create_log_dir() {
	if [[ ! -d "${ANSIBLE_LOG_LOCATION}" ]]
	then
		mkdir -m 775 -p "${ANSIBLE_LOG_LOCATION}"
		chown -R "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${ANSIBLE_LOG_LOCATION}"
	else
		if [[ ! -w "${ANSIBLE_LOG_LOCATION}" ]]
		then
			chmod 775 "${ANSIBLE_LOG_LOCATION}"
			chown -R "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${ANSIBLE_LOG_LOCATION}"
		fi
	fi
}

function enable_logging() {
	LOG=true
	if [[ "${LOG}" == "true" ]]
	then
		LOG_FILE="${ANSIBLE_LOG_LOCATION}/$(basename "${0}" | awk -F '.' '{print $1}').${ENAME}.log"
		[[ "$( grep ^log_path "${ANSIBLE_CFG}" )" != "" ]] && sed -i '/^log_path = .*\$/d' "${ANSIBLE_CFG}"
		if [[ -f ${LOG_FILE} ]] && [[ "${repeat_job}" != "" ]]
		then
			echo -e "\nRunning multiple instances of ${BOLD}$(basename "${0}")${NORMAL} is prohibited. Aborting!\n\n" && exit 1
		else
			export ANSIBLE_LOG_PATH=${LOG_FILE}
			touch "${LOG_FILE}"
			chown "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${LOG_FILE}"
		fi
		if [[ "$(pwd | grep -i 'cdra')" == "" ]]
		then
			echo -e "############################################################\nAnsible Control Machine $(hostname) $(ip a show "$(ip link | grep 2: | head -1 | awk '{print $2}')" | grep 'inet ' | cut -d '/' -f1 | awk '{print $2}')\nThis script was run$(check_mode "${@}")by $(git config user.name) ($(git config remote.origin.url | sed -e 's|.*\/\/\(.*\)@.*|\1|')) on $(date)\n############################################################\n\n" > "${LOG_FILE}"
		else
			echo -e "############################################################\nAnsible Control Machine $(hostname) $(ip a show "$(ip link | grep 2: | head -1 | awk '{print $2}')" | grep 'inet ' | cut -d '/' -f1 | awk '{print $2}')\nThis script was run$(check_mode "${@}")by $([[ -n ${MYINVOKER+x} ]] && echo "${MYINVOKER}" || whoami) on $(date)\n############################################################\n\n" > "${LOG_FILE}"
		fi
	fi
}

function get_bastion_address() {
	ansible localhost -i "${INVENTORY_PATH}" -m debug -a var=bastion.address | grep address | awk -F ': ' '{print $NF}'
}

function get_credentials() {
	if [[ ${GET_INVENTORY_STATUS} == 0 && $(get_bastion_address) != '[]' && ! -f ${CRVAULT} ]]
	then
		ansible-playbook playbooks/prompts.yml -i "${INVENTORY_PATH}" --extra-vars "{VFILE: '${CRVAULT}'}" $(remove_extra_vars_arg "$(remove_hosts_arg "${@}")") -e @"${ANSIBLE_VARS}" -v
		GET_CREDS_STATUS=${?}
		[[ ${GET_CREDS_STATUS} != 0 ]] && exit 1
		if [[ ${REPOPASS} != "" ]]
		then
			[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			encrypt_vault "${CRVAULT}" Bash/get_creds_vault_pass.sh
			[[ ${debug} == 1 ]] && set -x
		else
			echo -e "\n${BOLD}Repository password is not defined. Aborting!${NORMAL}"
			exit 1
		fi
	fi
}

function run_playbook() {
	if [[ ${GET_INVENTORY_STATUS} == 0 && (( $(get_bastion_address) != '[]' && (${GET_CREDS_STATUS} == 0 || -f ${CRVAULT}) ) || $(get_bastion_address) == '[]' ) ]]
	then
		### Begin: Determine if ASK_PASS is required
		[ "$(echo "${HOST_LIST}" | wc -w)" -gt 1 ] && HL="${HOST_LIST// /,}" || HL="${HOST_LIST}"
		ansible "${HL}" -m debug -a 'msg={{ansible_ssh_pass}}' &>/dev/null && [[ ${?} == 0 ]] && ASK_PASS=''
		### End
		### Begin: Define the extra-vars argument list and bastion credentials vault name and password file
		if [[ $(get_bastion_address) == '[]' ]]
		then
			local EVARGS
			local BCV
			EVARGS="{SVCFILE: '${SVCVAULT}', $(echo "${0}" | sed -e 's/.*play_\(.*\)\.sh/\1/'): true}"
			BCV=""
		else
			EVARGS="{SVCFILE: '${SVCVAULT}', VFILE: '${CRVAULT}', SCRTFILE: 'Bash/get_creds_vault_pass.sh', $(echo "${0}" | sed -e 's/.*play_\(.*\)\.sh/\1/'): true}"
			BCV="-e @${CRVAULT} --vault-password-file Bash/get_creds_vault_pass.sh"
		fi
		### End
		if [[ -z ${MYINVOKER+x} ]]
		then
			ansible-playbook playbooks/site.yml -i "${INVENTORY_PATH}" --extra-vars "${EVARGS}" ${ASK_PASS} -e @"${PASSVAULT}" -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh ${BCV} -e @"${ANSIBLE_VARS}" ${@} -v 2> "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr
		else
			ansible-playbook playbooks/site.yml -i "${INVENTORY_PATH}" --extra-vars "${EVARGS}" ${ASK_PASS} -e @"${PASSVAULT}" -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh ${BCV} -e @"${ANSIBLE_VARS}" ${@} -v 2> "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr 1>/dev/null
		fi
		[[ $(grep "no vault secrets were found that could decrypt" "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr | grep  "${PASSVAULT}") != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${PASSVAULT}${NORMAL}" && EC=1
		[[ $(grep "no vault secrets were found that could decrypt" "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr | grep "${CRVAULT}") != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${CRVAULT}${NORMAL}" && rm -f "${CRVAULT}" && EC=1
		[[ $(grep "no vault secrets were found that could decrypt" "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr) == "" ]] && [[ $(grep -iv warning "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr) != '' ]] && cat "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr && EC=1
		rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr
		[[ ${EC} == 1 ]] && exit 1
	fi
}

function disable_logging() {
	if [[ "${LOG}" == "true" ]] && [[ -f "${LOG_FILE}" ]]
	then
		unset ANSIBLE_LOG_PATH
		NEW_LOG_FILE=${LOG_FILE}.$(ls --full-time "${LOG_FILE}" | awk '{print $6"-"$7}')
		chmod 444 "${LOG_FILE}"
		mv -f "${LOG_FILE}" "${NEW_LOG_FILE}"
		echo -e "\nThe log file is ${BOLD}${NEW_LOG_FILE}${NORMAL}\n\n"
	fi
}

function send_notification() {
	if [[ "$(check_mode "${@}")" == " " ]]
	then
		SCRIPT_ARG="${@//-/dash}"
		[ "$(echo "${HOST_LIST}" | wc -w)" -gt 1 ] && HL="${HOST_LIST// /,}" || HL="${HOST_LIST}"
		NUM_HOSTS=$(ansible "${HL}" -i "${INVENTORY_PATH}" -m debug -a 'msg="{{ ansible_play_hosts }}"' | grep -Ev "\[|\]|\{|\}" | sort -u | wc -l)
		if [[ "$(pwd | grep -i 'cdra')" == "" ]]
		then
			# Send playbook status notification
			ansible-playbook playbooks/notify.yml --extra-vars "{SVCFILE: '${SVCVAULT}', SNAME: '$(basename "${0}")', SARG: '${SCRIPT_ARG}', LFILE: '${NEW_LOG_FILE}', NHOSTS: '${NUM_HOSTS}'}" --tags notify -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh -e @"${ANSIBLE_VARS}" -v &>/dev/null &
		else
			[[ -z ${MYINVOKER+x} ]] && local INVOKED=false || local INVOKED=true
			# Send playbook status notification
			ansible-playbook playbooks/notify.yml --extra-vars "{SVCFILE: '${SVCVAULT}', SNAME: '$(basename "${0}")', SARG: '${SCRIPT_ARG}', LFILE: '${NEW_LOG_FILE}', NHOSTS: '${NUM_HOSTS}', INVOKED: ${INVOKED}}" --tags notify -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh -e @"${ANSIBLE_VARS}" -v
		fi
	fi
}

# Parameters definition
ANSIBLE_CFG="${PWD}/ansible.cfg"
ANSIBLE_LOG_LOCATION="${PWD}/Logs"
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
PKG_LIST="epel-release sshpass python3 libselinux-python3 python3-pip yum-utils packer"
ANSIBLE_VERSION='2.10.7'
ANSIBLE_VARS="${PWD}/vars/datacenters.yml"
PASSVAULT="${PWD}/vars/passwords.yml"
REPOVAULT="${PWD}/.repovault.yml"
SECON=true

# Main
create_log_dir
PID="${$}"
check_arguments "${@}"
NEW_ARGS=$(check_hosts_limit "${@}")
set -- && set -- "${@}" "${NEW_ARGS}"
CC=$(check_concurrency)
ORIG_ARGS="${@}"
ENAME=$(get_envname "${ORIG_ARGS}")
INVENTORY_PATH="${PWD}/inventories/${ENAME}"
CRVAULT="${INVENTORY_PATH}/group_vars/vault.yml"
SYS_DEF="${PWD}/Definitions/${ENAME}.yml"
SYS_ALL="${INVENTORY_PATH}/group_vars/all.yml"
SVCVAULT="${PWD}/.svc_acct_creds_${ENAME}.yml"
check_repeat_job
NEW_ARGS=$(clean_arguments "${ENAME}" "${@}")
set -- && set -- "${@}" "${NEW_ARGS}"
if [[ "$(pwd | grep -i 'cdra')" == "" ]]
then
	git_config
	PROXY_ADDRESS=$(get_proxy) || PA=${?}
	[[ ${PA} -eq 1 ]] && echo -e "\n${PROXY_ADDRESS}\n" && exit ${PA}
	install_packages
	check_updates "${REPOVAULT}" Bash/get_repo_vault_pass.sh
fi
[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
get_svc_cred primary user 1>/dev/null && echo "PSVC_USER: '$(get_svc_cred primary user)'" > "${SVCVAULT}"
get_svc_cred primary pass 1>/dev/null && echo "PSVC_PASS: '$(get_svc_cred primary pass)'" >> "${SVCVAULT}"
get_svc_cred secondary user 1>/dev/null && echo "SSVC_USER: '$(get_svc_cred secondary user)'" >> "${SVCVAULT}"
get_svc_cred secondary pass 1>/dev/null && echo "SSVC_PASS: '$(get_svc_cred secondary pass)'" >> "${SVCVAULT}"
[[ ${debug} == 1 ]] && set -x
encrypt_vault "${SVCVAULT}" Bash/get_common_vault_pass.sh
install_pypkgs "${@}"
get_inventory "${@}"
[[ "${CC}" != "" ]] && SLEEPTIME=$(get_sleeptime) && [[ ${SLEEPTIME} != 0 ]] && echo "Sleeping for ${SLEEPTIME}" && sleep "${SLEEPTIME}"
get_hosts "${@}"
get_credentials "${@}"
enable_logging "${@}"
run_playbook "${@}"
disable_logging
send_notification "${ORIG_ARGS}"
