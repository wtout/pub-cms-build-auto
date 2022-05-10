# Functions declaration

function create_dir() {
	if [[ ! -d "${1}" ]]
	then
		mkdir -m 775 -p "${1}"
		chown -R "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${1}"
	else
		if [[ ! -w "${1}" ]]
		then
			chmod 775 "${1}"
			chown -R "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${1}"
		fi
	fi
}

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

function check_docker_login() {
	if [[ ! -f ${HOME}/.docker/config.json || "$(grep $(echo ${CONTAINERREPO}|cut -d '/' -f1) ${HOME}/.docker/config.json)" == "" ]]
	then
		if [[ $(check_image; echo "${?}") -ne 0 ]]
		then
			echo "You must login to containers repository to gain access to images before running this automation"
			exit 1
		else
			echo "You must login to containers repository to gain access to automation images"
		fi
	fi
}

function docker_cmd() {
	if [[ -f /etc/systemd/system/docker@.service ]]
	then
		echo "docker -H unix:///var/run/docker-$(whoami).sock"
	else
		echo "docker"
	fi
}

function restart_docker() {
	if [[ -f /etc/systemd/system/docker@.service ]]
	then
		if [[ "$($(docker_cmd) system info 2>/dev/null | grep -i containers | awk '{print $NF}')" == "0" ]]
		then
			sudo systemctl restart docker@$(whoami).service
		fi
	fi
}

function image_prune() {
	local CIID
	local IIDLIST
	CIID=$($(docker_cmd) images | grep -E "${CONTAINERREPO}.*${ANSIBLE_VERSION}" | awk '{print $3}')
	[[ "${CIID}" == "" ]] && IIDLIST=$($(docker_cmd) images -a -q) || IIDLIST=$($(docker_cmd) images -a -q | grep -v ${CIID})
	[[ "${IIDLIST}" != "" ]] && $(docker_cmd) rmi ${IIDLIST}
}

function check_image() {
	$(docker_cmd) images | grep -E "${CONTAINERREPO}.*${ANSIBLE_VERSION}" &>/dev/null
	return ${?}
}

function check_container() {
	$(docker_cmd) ps | grep -w ${CONTAINERNAME} &>/dev/null
	return ${?}
}

function start_container() {
	if [[ $(check_container; echo "${?}") -ne 0 ]]
	then
		sleep 10
		echo "Starting container ${CONTAINERNAME}"
		[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
		if [[ "${ANSIBLE_LOG_PATH}" == "" ]]
		then
			$(docker_cmd) run --rm -e MYPROXY=${PROXY_ADDRESS} -e MYHOME=${HOME} -e MYHOSTNAME=$(hostname) -e MYCONTAINERNAME=${CONTAINERNAME} -e MYIP=$(get_host_ip) --user ansible -w ${CONTAINERWD} -v /data:/data:z -v /tmp:/tmp:z -v ${HOME}/certificates:/home/ansible/certificates:z -v ${PWD}:${CONTAINERWD}:z --name ${CONTAINERNAME} -it -d --entrypoint /bin/bash ${CONTAINERREPO}:${ANSIBLE_VERSION}
		else
			$(docker_cmd) run --rm -e ANSIBLE_LOG_PATH=${ANSIBLE_LOG_PATH} -e MYPROXY=${PROXY_ADDRESS} -e MYHOME=${HOME} -e MYHOSTNAME=$(hostname) -e MYCONTAINERNAME=${CONTAINERNAME} -e MYIP=$(get_host_ip) --user ansible -w ${CONTAINERWD} -v /data:/data:z -v /tmp:/tmp:z -v ${HOME}/certificates:/home/ansible/certificates:z -v ${PWD}:${CONTAINERWD}:z --name ${CONTAINERNAME} -it -d --entrypoint /bin/bash ${CONTAINERREPO}:${ANSIBLE_VERSION}
		fi
		[[ ${debug} == 1 ]] && set -x
		[[ $(check_container; echo "${?}") -ne 0 ]] && echo "Unable to start container ${CONTAINERNAME}" && exit 1
	fi
}

function stop_container() {
	if [[ $(check_container; echo "${?}") -eq 0 ]]
	then
		echo "Stopping container ${CONTAINERNAME}"
		$(docker_cmd) stop ${CONTAINERNAME}
	fi
}

function check_repeat_job() {
	ps aux | grep -w "${ENAME}" | grep -vwE "${PID}|grep"
	return ${?}
}

function check_hosts_limit() {
	local ARG_NAME
	local MYACTION
	local NEWARGS
	[[ "$(echo "${@}" | grep -Ew '\-\-limit')" != "" ]] && [[ "$(echo "${@}" | grep 'vcenter')" == "" ]] && ARG_NAME="--limit" && MYACTION="add"
	[[ "$(echo "${@}" | grep -Ew '\-l')" != "" ]] && [[ "$(echo "${@}" | grep 'vcenter')" == "" ]] && ARG_NAME="-l" && MYACTION="add"
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
		if [[ "$(echo "${MYHOSTS}" | grep 'dr')" == "" ]]
		then
			VCENTERS='vcenter'
		else
			if [[ "$(echo "${MYHOSTS}" | sed "s/,/\n/g" | grep -v 'dr')" == "" ]]
			then
				VCENTERS='drvcenter'
			else
				VCENTERS='vcenter,drvcenter'
			fi
		fi
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
	ps aux | grep "$(basename "${0}")" | grep -vwE "${ENAME}|grep"
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
			get_svc_cred primary user 1>/dev/null && read -r PPUSER <<< "$(get_svc_cred primary user)"
			get_svc_cred primary pass 1>/dev/null && read -r PPPASS <<< "$(get_svc_cred primary pass)"
			get_svc_cred secondary user 1>/dev/null && read -r SPUSER <<< "$(get_svc_cred secondary user)"
			get_svc_cred secondary pass 1>/dev/null && read -r SPPASS <<< "$(get_svc_cred secondary pass)"
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

function add_write_permission() {
	for i in ${*}
	do
		sudo chmod o+w ${i}
	done
}

function get_creds_prefix() {
    local FILETOCHECK
    local DATACENTER
    local CREDS_PREFIX
	[[ -f "${SYS_DEF}" ]] && FILETOCHECK="${SYS_DEF}" || FILETOCHECK="${SYS_ALL}"
	DATACENTER=$(cat "${FILETOCHECK}" | sed "/^$/d" | grep -A32 -P "^datacenter:$" | sed -n "/${1}:/,+2p" | sed -n "/name:/,1p" | awk -F ': ' '{print $NF}')
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

function get_host_ip() {
	ip a show "$(ip link | grep 2: | head -1 | awk '{print $2}')" | grep 'inet ' | cut -d '/' -f1 | awk '{print $2}'
}

function encrypt_vault() {
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && $(docker_cmd) exec -it ${CONTAINERNAME} ansible-vault encrypt "${1}" --vault-password-file "${2}" &>"${ANSIBLE_LOG_LOCATION}"/encrypt_error."${PID}"
	if [[ -s "${ANSIBLE_LOG_LOCATION}/encrypt_error.${PID}" && "$(grep 'successful' "${ANSIBLE_LOG_LOCATION}/encrypt_error.${PID}")" == "" ]]
	then
		cat "${ANSIBLE_LOG_LOCATION}"/encrypt_error."${PID}"
		exit 1
	else
		rm "${ANSIBLE_LOG_LOCATION}"/encrypt_error."${PID}"
	fi
}

function view_vault() {
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && $(docker_cmd) exec -i ${CONTAINERNAME} ansible-vault view "${1}" --vault-password-file "${2}" 2>"${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}"
	[[ $(grep "was not found" "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}") != "" ]] && sed -i "/^vault_password_file.*$/,+d" "${ANSIBLE_CFG}" && $(docker_cmd) exec -i ${CONTAINERNAME} ansible-vault view "${1}" --vault-password-file "${2}" &>/dev/null
	rm -f "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}"
}

function get_repo_creds() {
	[[ -f ${1} ]] && grep 'REPOPASS=' "${1}" 1>/dev/null && rm -f "${1}"
	local REPOUSER
	local REPOPASS
	if [[ -f ${1} ]]
	then
		local i
		local retries
		i=0
		retries=3
		while [[ ${i} -lt ${retries} ]]
		do
			[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			if [[ ${REPOUSER} == "" || ${REPOPASS} == "" ]]
			then
				read -r REPOUSER <<< "$(view_vault "${1}" "${2}" | grep USER | cut -d "'" -f2)"
				read -r REPOPASS <<< "$(view_vault "${1}" "${2}" | grep PASS | cut -d "'" -f2)"
			else
				break
				[[ ${debug} == 1 ]] && set -x
			fi
			i=$((++i))
			[[ ${i} -eq ${retries} ]] && echo "Unable to decrypt Repository password vault. Exiting!" && exit 1
		done
	else
		echo
		read -rp "Enter your Repository username [ENTER]: " REPOUSER
		read -rsp "Enter your Repository password [ENTER]: " REPOPASS
		if [[ ${REPOUSER} != "" && ${REPOPASS} != "" ]]
		then
			[[ -f ${1} ]] && rm -f "${1}"
			[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			printf "REPOUSER='%s'\nREPOPASS='%s'\n" "${REPOUSER}" "${REPOPASS}" > "${1}"
			add_write_permission "${1}"
			encrypt_vault "${1}" "${2}"
			[[ ${debug} == 1 ]] && set -x
			sudo chown "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${1}"
			sudo chmod 644 "${1}"
		fi
		echo
	fi
	if [[ ${REPOUSER} != "" && ${REPOPASS} != "" ]]
	then
		local REPOPWD
		local REMOTEID
		local SET_PROXY
		[[ $(git config --get remote.origin.url | grep "www-github") != "" ]] && [[ ${PROXY_ADDRESS} != "" ]] && SET_PROXY="true"
		for i in {1..3}
		do
			[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			REPOPWD="${REPOPASS//@/%40}"
			REMOTEID=$([[ ${SET_PROXY} ]] && export https_proxy=${PROXY_ADDRESS}; git ls-remote "$(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${REPOPWD}@|")" refs/heads/"$(git branch | grep '*' | awk '{print $NF}')" 2>"${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr | cut -c1-7)
			[[ ${debug} == 1 ]] && set -x
			[[ ${REMOTEID} == "" ]] && sleep 3 || break
		done
		if [[ "${REMOTEID}" == "" ]]
		then
			local REPO_ERR
			REPO_ERR="$(grep -i maintenance "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr)"
			if [[ "${REPO_ERR}" == "" ]]
			then
			 	printf "\nYour Repository credentials are invalid!\n\n" && rm -f "${1}" && rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr && exit 1
			else
			 	printf "\n%s" "${REPO_ERR}" && rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr && exit 1
			fi
		else
			rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr
		fi
	else
		echo "Unable to get repo credentials"
		[[ "$(basename ${0})" == *"deploy"* && "${ENAME}" == *"mdr"* ]] && stop_container && exit 1
	fi
}

function check_updates() {
	if [[ -f ${1} && "$(git config user.name)" != "" ]]
	then
		local localbranch
		local remotebranchlist
		localbranch=$(git branch|grep '^*'|awk '{print $NF}')
		remotebranchlist=$(git branch -r)
		if [[ $(echo ${remotebranchlist}|grep '/'${localbranch}) ]]
		then
			git rev-parse --short HEAD &>/dev/null
			if [[ ${?} -eq 0 ]]
			then
				local REPOPASS
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
						read -r REPOPASS <<< "$(view_vault "${1}" "${2}" | grep PASS | cut -d "'" -f2)"
					else
						break
					fi
					i=$((++i))
					[[ ${i} -eq ${retries} ]] && echo "Unable to decrypt Repository password vault. Exiting!" && exit 1
				done
				local LOCALID
				local REPOPWD
				local REMOTEID
				local SET_PROXY
				LOCALID=$(git rev-parse --short HEAD)
				[[ $(git config --get remote.origin.url | grep "www-github") == "" ]] && [[ ${PROXY_ADDRESS} != "" ]] && SET_PROXY="true"
				for i in {1..3}
				do
					[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
					REPOPWD="${REPOPASS//@/%40}"
					REMOTEID=$([[ ${SET_PROXY} ]] && export https_proxy=${PROXY_ADDRESS}; git ls-remote "$(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${REPOPWD}@|")" refs/heads/"$(git branch | grep '*' | awk '{print $NF}')" 2>"${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr | cut -c1-7)
					[[ ${debug} == 1 ]] && set -x
					[[ ${REMOTEID} == "" ]] && sleep 3 || break
				done
				if [[ "${REMOTEID}" == "" ]]
				then
					echo "Unable to get the remote revision ID"
				else
					rm -f "${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr
				fi
				if [[ "${REMOTEID}" != "" && "${LOCALID}" != "${REMOTEID}" ]]
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
				${EC}
			fi
		fi
	fi
}

function get_hostsinplay() {
	local ENVS
	local HN
	ENVS="$(ps aux | grep -E 'play.*\.sh' | grep envname | grep -vw "${ENAME}" | awk -F 'envname ' '{print $NF}' | cut -d'-' -f1 | sort -u)"
	HN=""
	for env in ${ENVS}
	do
		HN="${HN}$($(docker_cmd) exec -i ${CONTAINERNAME} ansible all -i "${INVENTORY_PATH}"/../${env} --list-hosts | grep -v host | sed -e 's/^\s*\(\w.*\)$/\1/g' | sort)"
	done
	echo "${HN}" | wc -l
}

function get_inventory() {
	sed -i "/^vault_password_file.*$/,+d" "${ANSIBLE_CFG}"
	if [[ -f ${SYS_DEF} ]]
	then
		$(docker_cmd) exec -it ${CONTAINERNAME} ansible-playbook playbooks/getinventory.yml --extra-vars "{SYS_NAME: '${SYS_DEF}'}" -e @"${ANSIBLE_VARS}" -e "{auto_dir: '${CONTAINERWD}'}" $(remove_extra_vars_arg "$(remove_hosts_arg "${@}")") -v
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
}

function get_sleeptime() {
	local HOSTNUM
	HOSTNUM=$(get_hostsinplay)
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
		HOST_LIST=$($(docker_cmd) exec -i ${CONTAINERNAME} ansible all -i "${INVENTORY_PATH}" --list-hosts | grep -v host | sed -e 's/^\s*\(\w.*\)$/\1/g' | sort)
	fi
}

function check_mode() {
	[[ "$(echo "${@}" | grep -Ew '\-\-check')" != "" ]] && echo " in check mode " || echo " "
}

function create_symlink() {
	if [[ ! -d 'Packages' ]]
	then
		if [[ -d '/data/Packages' ]]
		then
			echo "Creating symbolic link to /data/Packages"
			ln -s /data/Packages Packages
			[[ ! -d 'Packages' ]] && echo "Unable to create symbolic link to /data/Packages. Check permissions" && exit 1
		else
			echo "Unable to create symbolic link to /data/Packages as it doesn't exist"
			exit 1
		fi
	fi
}

function enable_logging() {
	LOG=true
	if [[ "${LOG}" == "true" ]]
	then
		LOG_FILE="${ANSIBLE_LOG_LOCATION}/$(basename "${0}" | awk -F '.' '{print $1}').${ENAME}.log"
		[[ "$( grep ^log_path "${ANSIBLE_CFG}" )" != "" ]] && sed -i '/^log_path = .*\$/d' "${ANSIBLE_CFG}"
		export ANSIBLE_LOG_PATH=${LOG_FILE}
		touch "${LOG_FILE}"
		[[ ${?} -ne 0 ]] && echo -e "\nUnable to create ${LOG_FILE}. Aborting run!\n" && exit 1
		chown "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${LOG_FILE}"
		chmod o+rw "${LOG_FILE}"
		if [[ -z ${MYINVOKER+x} ]]
		then
			echo -e "############################################################\nAnsible Control Machine $(hostname) $(get_host_ip) ${CONTAINERNAME}\nThis script was run$(check_mode "${@}")by $(whoami) on $(date)\n############################################################\n\n" > "${LOG_FILE}"
		else
			echo -e "############################################################\nAnsible Control Machine $(hostname) $(get_host_ip) ${CONTAINERNAME}\nThis script was run$(check_mode "${@}")by ${MYINVOKER} on $(date)\n############################################################\n\n" > "${LOG_FILE}"
		fi
	fi
}

function get_bastion_address() {
	$(docker_cmd) exec -i ${CONTAINERNAME} ansible localhost -i "${INVENTORY_PATH}" -m debug -a var=bastion.address | grep address | awk -F ': ' '{print $NF}'
}

function get_credentials() {
	if [[ ${GET_INVENTORY_STATUS} == 0 && $(get_bastion_address) != "[]" && ! -f ${CRVAULT} ]]
	then
		$(docker_cmd) exec -it ${CONTAINERNAME} ansible-playbook playbooks/prompts.yml -i "${INVENTORY_PATH}" --extra-vars "{VFILE: '${CONTAINERWD}/${CRVAULT}'}" $(remove_extra_vars_arg "$(remove_hosts_arg "${@}")") -e @"${ANSIBLE_VARS}" -v
		GET_CREDS_STATUS=${?}
		[[ ${GET_CREDS_STATUS} != 0 ]] && exit 1
		if [[ -f ${REPOVAULT} ]]
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
		$(docker_cmd) exec -it ${CONTAINERNAME} ansible "${HL}" -m debug -a 'msg={{ ansible_ssh_pass }}' &>/dev/null && [[ ${?} == 0 ]] && ASK_PASS=''
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
			$(docker_cmd) exec -it ${CONTAINERNAME} ansible-playbook playbooks/site.yml -i "${INVENTORY_PATH}" --extra-vars "${EVARGS}" ${ASK_PASS} -e @"${PASSVAULT}" -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh ${BCV} -e @"${ANSIBLE_VARS}" -e "{auto_dir: '${CONTAINERWD}'}" ${@} -v 2> "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr
		else
			$(docker_cmd) exec -it ${CONTAINERNAME} ansible-playbook playbooks/site.yml -i "${INVENTORY_PATH}" --extra-vars "${EVARGS}" ${ASK_PASS} -e @"${PASSVAULT}" -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh ${BCV} -e @"${ANSIBLE_VARS}" -e "{auto_dir: '${CONTAINERWD}'}" ${@} -v 2> "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr 1>/dev/null
		fi
		[[ $(grep "no vault secrets were found that could decrypt" "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr | grep  "${PASSVAULT}") != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${PASSVAULT}${NORMAL}" && EC=1
		[[ $(grep "no vault secrets were found that could decrypt" "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr | grep "${CRVAULT}") != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${CRVAULT}${NORMAL}" && rm -f "${CRVAULT}" && EC=1
		[[ $(grep "no vault secrets were found that could decrypt" "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr) == "" ]] && [[ $(grep -i warning "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr) == '' ]] && cat "${ANSIBLE_LOG_LOCATION}"/"${PID}".stderr
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
		echo -e "\nThe log file is ${BOLD}${PWD}/Logs/$(basename ${NEW_LOG_FILE})${NORMAL}\n\n"
	fi
}

function send_notification() {
	if [[ "$(check_mode "${@}")" == " " ]]
	then
		SCRIPT_ARG="${@//-/dash}"
		[ "$(echo "${HOST_LIST}" | wc -w)" -gt 1 ] && HL="${HOST_LIST// /,}" || HL="${HOST_LIST}"
		NUM_HOSTS=$($(docker_cmd) exec -i ${CONTAINERNAME} ansible "${HL}" -i "${INVENTORY_PATH}" -m debug -a msg="{{ ansible_play_hosts }}" | grep -Ev "\[|\]|\{|\}" | sort -u | wc -l)
		if [[ -z ${MYINVOKER+x} ]]
		then
			# Send playbook status notification
			$(docker_cmd) exec -it ${CONTAINERNAME} ansible-playbook playbooks/notify.yml --extra-vars "{SVCFILE: '${CONTAINERWD}/${SVCVAULT}', SNAME: '$(basename "${0}")', SARG: '${SCRIPT_ARG}', LFILE: '${CONTAINERWD}/${NEW_LOG_FILE}', NHOSTS: '${NUM_HOSTS}'}" --tags notify -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh -e @"${ANSIBLE_VARS}" -v &>/dev/null
		else
			local INVOKED
			INVOKED=true
			# Send playbook status notification
			$(docker_cmd) exec -it ${CONTAINERNAME} ansible-playbook playbooks/notify.yml --extra-vars "{SVCFILE: '${CONTAINERWD}/${SVCVAULT}', SNAME: '$(basename "${0}")', SARG: '${SCRIPT_ARG}', LFILE: '${CONTAINERWD}/${NEW_LOG_FILE}', NHOSTS: '${NUM_HOSTS}', INVOKED: ${INVOKED}}" --tags notify -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh -e @"${ANSIBLE_VARS}" -v
		fi
	fi
}

# Parameters definition
ANSIBLE_CFG="ansible.cfg"
ANSIBLE_LOG_LOCATION="Logs"
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
ANSIBLE_VERSION='4.10.0'
ANSIBLE_VARS="vars/datacenters.yml"
PASSVAULT="vars/passwords.yml"
REPOVAULT="vars/.repovault.yml"
CONTAINERWD="/home/ansible/cmsp-auto-deploy"
CONTAINERREPO="containers.cisco.com/watout/ansible"
MDR_AUTO_LOCATION="imp_auto"
SECON=true

# Main
PID="${$}"
create_dir "${ANSIBLE_LOG_LOCATION}"
[[ "$(basename ${0})" == *"deploy"* && "${ENAME}" == *"mdr"* ]] && create_dir "${MDR_AUTO_LOCATION}"
check_arguments "${@}"
check_docker_login
restart_docker
NEW_ARGS=$(check_hosts_limit "${@}")
set -- && set -- "${@}" "${NEW_ARGS}"
ORIG_ARGS="${@}"
ENAME=$(get_envname "${ORIG_ARGS}")
check_repeat_job && echo -e "\nRunning multiple instances of ${BOLD}$(basename "${0}")${NORMAL} is prohibited. Aborting!\n\n" && exit 1
CC=$(check_concurrency)
INVENTORY_PATH="inventories/${ENAME}"
CRVAULT="${INVENTORY_PATH}/group_vars/vault.yml"
SYS_DEF="Definitions/${ENAME}.yml"
SYS_ALL="${INVENTORY_PATH}/group_vars/all.yml"
SVCVAULT="vars/.svc_acct_creds_${ENAME}.yml"
CONTAINERNAME="$(whoami | cut -d '@' -f1)_ansible_${ANSIBLE_VERSION}_${ENAME}"
NEW_ARGS=$(clean_arguments "${ENAME}" "${@}")
set -- && set -- "${@}" "${NEW_ARGS}"
[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
PROXY_ADDRESS=$(get_proxy) || PA=${?}
[[ ${PA} -eq 1 ]] && echo -e "\n${PROXY_ADDRESS}\n" && exit ${PA}
[[ ${debug} == 1 ]] && set -x
git_config
add_write_permission ${PWD}/vars
stop_container
image_prune
start_container
get_repo_creds "${REPOVAULT}" Bash/get_repo_vault_pass.sh
check_updates "${REPOVAULT}" Bash/get_repo_vault_pass.sh
[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
get_svc_cred primary user 1>/dev/null && echo "PSVC_USER: '$(get_svc_cred primary user)'" > "${SVCVAULT}"
get_svc_cred primary pass 1>/dev/null && echo "PSVC_PASS: '$(get_svc_cred primary pass)'" >> "${SVCVAULT}"
get_svc_cred secondary user 1>/dev/null && echo "SSVC_USER: '$(get_svc_cred secondary user)'" >> "${SVCVAULT}"
get_svc_cred secondary pass 1>/dev/null && echo "SSVC_PASS: '$(get_svc_cred secondary pass)'" >> "${SVCVAULT}"
[[ ${debug} == 1 ]] && set -x
add_write_permission "${SVCVAULT}"
encrypt_vault "${SVCVAULT}" Bash/get_common_vault_pass.sh
sudo chown "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${SVCVAULT}"
sudo chmod 644 "${SVCVAULT}"
get_inventory "${@}"
[[ "${CC}" != "" ]] && SLEEPTIME=$(get_sleeptime) && [[ ${SLEEPTIME} != 0 ]] && echo "Sleeping for ${SLEEPTIME}" && sleep "${SLEEPTIME}"
get_hosts "${@}"
get_credentials "${@}"
stop_container
create_symlink
add_write_permission "${PWD}/roles"
add_write_permission "${PWD}/roles/*"
add_write_permission "${PWD}/roles/*/files"
enable_logging "${@}"
start_container
run_playbook "${@}"
stop_container
disable_logging
start_container
send_notification "${ORIG_ARGS}"
stop_container
