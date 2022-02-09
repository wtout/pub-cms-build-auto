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

function get_inventory() {
	sed -i "/^vault_password_file.*$/,+d" "${ANSIBLE_CFG}"
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
}

function encrypt_vault() {
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && ansible-vault encrypt "${1}" --vault-password-file "${2}" &>/dev/null
}

function view_vault() {
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && ansible-vault view "${1}" --vault-password-file "${2}" 2> "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}"
	[[ $(grep "was not found" "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}") != "" ]] && sed -i "/^vault_password_file.*$/,+d" "${ANSIBLE_CFG}" && ansible-vault view "${1}" --vault-password-file "${2}" &>/dev/null
	rm -f "${ANSIBLE_LOG_LOCATION}"/decrypt_error."${PID}"
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

function get_repo_creds() {
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
			if [[ ${REPOUSER} == "" || ${REPOPASS} == "" ]]
			then
				[[ ${debug} == 1 ]] && set -x
				read -r REPOUSER <<< "$(view_vault "${1}" "${2}" | grep USER | cut -d "'" -f2)"
				read -r REPOPASS <<< "$(view_vault "${1}" "${2}" | grep PASS | cut -d "'" -f2)"
			else
				break
			fi
			i=$((++i))
			[[ ${i} -eq ${retries} ]] && echo "Unable to decrypt Repository password vault. Exiting!" && exit 1
		done
	else
		local REPOUSER
		local REPOPASS
		echo
		read -rp "Enter your Repository username [ENTER]: " REPOUSER
		read -rsp "Enter your Repository password [ENTER]: " REPOPASS
		[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
		[[ -f ${1} ]] && rm -f "${1}"
		printf "REPOUSER='%s'\nREPOPASS='%s'\n" "${REPOUSER}" "${REPOPASS}" > "${1}"
		encrypt_vault "${1}" "${2}"
		[[ ${debug} == 1 ]] && set -x
		echo
	fi
	if [[ ${REPOUSER} != "" && ${REPOPASS} != "" ]]
	then
		local REPOPWD
		local REMOTEID
		[[ $(git config --get remote.origin.url | grep "www-github") != "" ]] && [[ ${MYPROXY} != "" ]] && SET_PROXY="true"
		for i in {1..3}
		do
			[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
			REPOPWD="${REPOPASS//@/%40}"
			REMOTEID=$([[ ${SET_PROXY} ]] && export https_proxy=${MYPROXY}; git ls-remote "$(git config --get remote.origin.url | sed -e "s|://|://${REPOUSER}:${REPOPWD}@|")" refs/heads/"$(git branch | grep '*' | awk '{print $NF}')" 2>"${ANSIBLE_LOG_LOCATION}"/"${PID}"-remoteid.stderr | cut -c1-7)
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
	else
		echo "Unable to get repo credentials"
		exit 1
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
			[[ ${?} -ne 0 ]] && echo -e "\nUnable to create ${LOG_FILE}. Aborting run!\n" && exit 1
			chown "$(stat -c '%U' "$(pwd)")":"$(stat -c '%G' "$(pwd)")" "${LOG_FILE}"
		fi
		if [[ -z ${MYINVOKER+x} ]]
		then
			echo -e "############################################################\nAnsible Control Machine ${MYHOSTNAME} ${MYIP} ${MYCONTAINERNAME}\nThis script was run$(check_mode "${@}")by $(basename ${MYHOME}) on $(date)\n############################################################\n\n" > "${LOG_FILE}"
		else
			echo -e "############################################################\nAnsible Control Machine ${MYHOSTNAME} ${MYIP} ${MYCONTAINERNAME}\nThis script was run$(check_mode "${@}")by ${MYINVOKER} on $(date)\n############################################################\n\n" > "${LOG_FILE}"
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
		echo -e "\nThe log file is ${BOLD}${MYHOME}/Ansible_Logs/$(basename ${NEW_LOG_FILE})${NORMAL}\n\n"
	fi
}

function send_notification() {
	if [[ "$(check_mode "${@}")" == " " ]]
	then
		SCRIPT_ARG="${@//-/dash}"
		[ "$(echo "${HOST_LIST}" | wc -w)" -gt 1 ] && HL="${HOST_LIST// /,}" || HL="${HOST_LIST}"
		NUM_HOSTS=$(ansible "${HL}" -i "${INVENTORY_PATH}" -m debug -a 'msg="{{ ansible_play_hosts }}"' | grep -Ev "\[|\]|\{|\}" | sort -u | wc -l)
		if [[ -z ${MYINVOKER+x} ]]
		then
			# Send playbook status notification
			ansible-playbook playbooks/notify.yml --extra-vars "{SVCFILE: '${SVCVAULT}', SNAME: '$(basename "${0}")', SARG: '${SCRIPT_ARG}', LFILE: '${NEW_LOG_FILE}', NHOSTS: '${NUM_HOSTS}'}" --tags notify -e @"${SVCVAULT}" --vault-password-file Bash/get_common_vault_pass.sh -e @"${ANSIBLE_VARS}" -v &>/dev/null 
		else
			local INVOKED
			INVOKED=true
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
[[ "$(basename ${0})" == *"deploy"* ]] && [[ "${ENAME}" == *"mdr"* ]] && get_repo_creds ${REPOVAULT} Bash/get_repo_vault_pass.sh
[[ $- =~ x ]] && debug=1 && [[ "${SECON}" == "true" ]] && set +x
get_svc_cred primary user 1>/dev/null && echo "PSVC_USER: '$(get_svc_cred primary user)'" > "${SVCVAULT}"
get_svc_cred primary pass 1>/dev/null && echo "PSVC_PASS: '$(get_svc_cred primary pass)'" >> "${SVCVAULT}"
get_svc_cred secondary user 1>/dev/null && echo "SSVC_USER: '$(get_svc_cred secondary user)'" >> "${SVCVAULT}"
get_svc_cred secondary pass 1>/dev/null && echo "SSVC_PASS: '$(get_svc_cred secondary pass)'" >> "${SVCVAULT}"
[[ ${debug} == 1 ]] && set -x
encrypt_vault "${SVCVAULT}" Bash/get_common_vault_pass.sh
get_inventory "${@}"
[[ "${CC}" != "" ]] && SLEEPTIME=$(get_sleeptime) && [[ ${SLEEPTIME} != 0 ]] && echo "Sleeping for ${SLEEPTIME}" && sleep "${SLEEPTIME}"
get_hosts "${@}"
get_credentials "${@}"
enable_logging "${@}"
run_playbook "${@}"
disable_logging
send_notification "${ORIG_ARGS}"
