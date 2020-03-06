# Functions declaration

function check_arguments() {
	if [[ "x$(echo ${@} | egrep -w '\-\-envname')" == "x" ]]
		then
			printf "\nEnvironment name is required!\nRe-run the script with ${BOLD}--envname${NORMAL} <environment name as defined under Inventories>\n\n"
			exit 1
		fi
}

function check_repeat_job() {
	repeat_job=$( ps -ef | grep ${ENAME} | grep $(basename ${0} | awk -F '.' '{print $1}') | grep -v ${PID} )
}

function check_hosts_limit() {
	if [[ "x$(echo ${@} | egrep -w '\-\-limit')" != "x" ]] && [[ "x$(echo ${@} | egrep -w 'vcenter')" == "x" ]]
	then
		local MYHOSTS=$(echo ${@} | awk -F '--limit ' '{print $NF}' | awk -F ' -' '{print $1}')
		[[ "x$(echo ${@} | egrep -w '\-\-tags')" != "x" ]] && local MYTAGS=$(echo ${@} | awk -F '--tags ' '{print $NF}' | awk -F ' -' '{print $1}')
		[[ "x$(echo ${MYTAGS})" == "x" ]] && local update_args=1
		[[ "x$(echo ${MYTAGS} | egrep -w 'vm_creation')" != "x" ]] && local update_args=1
		if [[ ${update_args} -eq 1 ]]
		then
			local ARG_NAME="--limit"
			for arg
			do
				shift
				[[ "${arg}" == "${MYHOSTS}" ]] && set -- ${@} "${MYHOSTS},vcenter" || set -- ${@} ${arg}
			done
		fi
	fi
	echo ${@}
}

function check_concurrency() {
	ps -ef | grep $(basename ${0}) | grep -v grep | grep -v ${PID}
}

function get_envname() {
	[[ "$(echo ${@} | egrep -w '\-\-envname')" != "" ]] && envname=$(echo ${@} | awk -F 'envname ' '{print $NF}' | cut -d'-' -f1)
	echo ${envname}
}

function clean_arguments() {
	# Remove --envname argument from script arguments
	local OPTION_NAME="--envname"
	local ENVNAME=${1}
	for arg
	do
		shift
		[[ ${arg} == ${OPTION_NAME} || ${ENVNAME} == ${arg} ]] && continue
		set -- ${@} ${arg}
	done
	echo ${@}
}

function git_config() {
	if [[ "x$(which git 2>/dev/null)" != "x" ]]
	then
		if [[ "x$(git config user.name)" == "x" ]]
		then
			if [[ "$(git config remote.origin.url)" == "" ]]
			then
				read -p "Enter your full name [ENTER]: " NAME SURNAME && git config user.name "${NAME} ${SURNAME}" || EC=1
			else
				read -p "Enter your full name [ENTER]: " NAME SURNAME && [[ "${SURNAME}" != "" && "$(git config remote.origin.url | sed -e 's/.*\/\/\(.*\)@.*/\1/')" == *$(echo ${SURNAME:0:5} | tr '[A-Z]' '[a-z]')* ]] && git config user.name "${NAME} ${SURNAME}" || EC=1
			fi
		fi
		[[ ${EC} -eq 1 ]] && echo "Invalid ID. Aborting!" && exit ${EC}
		if [[ "x$(git config user.email)" == "x" ]]
		then
			NAME=$(git config user.name | awk '{print $1}' | tr '[A-Z]' '[a-z]')
			SURNAME=$(git config user.name | awk '{print $NF}' | tr '[A-Z]' '[a-z]')
			if [[ "$(git config remote.origin.url)" == "" ]]
			then
				read -p "Enter your email address [ENTER]: " GIT_EMAIL_ADDRESS && [[ "${GIT_EMAIL_ADDRESS}" != "" && ("$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${NAME:0:2}* && "$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${SURNAME:0:5}*) ]] && git config user.email ${GIT_EMAIL_ADDRESS} || EC=1
			else
				read -p "Enter your email address [ENTER]: " GIT_EMAIL_ADDRESS && [[ "${GIT_EMAIL_ADDRESS}" != "" && ("$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${NAME:0:2}* && "$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${SURNAME:0:5}*) && "$(git config remote.origin.url)" == *$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/^.*@\(.*\)\..*$/\1/')* ]] && git config user.email ${GIT_EMAIL_ADDRESS} || EC=1
			fi
		fi
		[[ ${EC} -eq 1 ]] && echo "Invalid email address. Aborting!" && exit ${EC}
	else
		echo "Please ensure git is installed on this machine before running script. Aborting!" && exit 1
	fi
}

function get_sudopass() {
	read -s -p "Enter localhost's sudo password and press [ENTER]: " SP
	sudo -S echo "Thanks" &>/dev/null <<< ${SP}
	if [[ "${?}" == 0 ]]
	then
		echo ${SP}
		return 0
	else
		echo "Password is incorrect. Aborting!"
		return 1
	fi
}

function install_packages() {
	for pkg in ${PKG_LIST}
	do
		if [ "x$(yum list installed ${pkg} &>/dev/null;echo ${?})" == "x1" ]
		then
			if [[ "x${SUDO_PASS}" == "x" ]]
			then
				echo
				SUDO_PASS=$(get_sudopass) || FS=${?}
				[[ "${FS}" == 1 ]] && echo -e "\n${SUDO_PASS}\n" && exit ${FS}
			fi
			PKG_ARR=(${PKG_LIST})
			[[ ${pkg} == ${PKG_ARR[0]} ]] && printf "\n\nInstalling ${pkg} on localhost ..." || \
			printf "\nInstalling ${pkg} on localhost ..."
			sudo -S yum install -y ${pkg} --quiet <<< ${SUDO_PASS} 2>/dev/null
			[[ ${?} == 0 ]] && printf " Installed version $(yum list ${pkg} | tail -1 | awk '{print $2}')\n" || exit 1
		fi
	done
	if [ "x$(which ansible 2>/dev/null)" == "x" ]
	then
		printf "\nInstalling ansible on localhost ..."
		pip install --user --no-cache-dir --quiet -I ansible==${ANSIBLE_VERSION}
		[[ ${?} == 0 ]] && printf " Installed version ${ANSIBLE_VERSION}\n" || exit 1
	else
		if [ "$(printf '%s\n' $(ansible --version | grep ^ansible | awk -F 'ansible ' '{print $NF}') ${ANSIBLE_VERSION} | sort -V | head -1)" != "${ANSIBLE_VERSION}" ]
		then
			printf "\nUpgrading Ansible from version $(ansible --version | grep '^ansible' | cut -d ' ' -f2)"
			pip install --user --no-cache-dir --quiet --upgrade -I ansible==${ANSIBLE_VERSION}
			[[ ${?} == 0 ]] && printf " to version ${ANSIBLE_VERSION}\n" || exit 1
		fi
	fi
}

function get_inventory() {
	sed -i "/^vault_password_file.*$/,+d" ${ANSIBLE_CFG}
	sed -i "s|\(^inventory =\).*$|\1 inventories|" ${ANSIBLE_CFG}
	if [[ -f ${SYS_DEF} ]]
	then
		if [[ "x$(echo ${@} | egrep -w '\-\-limit')" != "x" ]]
		then
			local MYHOSTS=$(echo ${@} | awk -F '--limit ' '{print $NF}' | awk -F ' -' '{print $1}')
			local ARG_NAME="--limit"
			for arg
			do
				shift
				[[ ${arg} == ${ARG_NAME} || ${arg} == ${MYHOSTS} ]] && continue
				set -- ${@} ${arg}
			done
		fi
		ansible-playbook playbooks/getinventory.yml --extra-vars "{SYS_NAME: '${SYS_DEF}'}" ${@} -e @${ANSIBLE_VARS} -v
		GET_INVENTORY_STATUS=${?}
		[[ ${GET_INVENTORY_STATUS} != 0 ]] && exit 1
	else
		echo -e "\nStack definition file for ${ENAME} cannot be found. Aborting!"
		exit 1
	fi
}

function encrypt_vault() {
	echo ${3} > ${2}
	[[ -f ${1} ]] && ansible-vault encrypt --vault-password-file ${2} ${1} &>/dev/null
	rm -f ${2}
}

function decrypt_vault() {
	echo ${3} > ${2}
	[[ -f ${1} ]] && ansible-vault decrypt --vault-password-file ${2} ${1} 2> /tmp/decrypt_error.${PID}
	[[ $(grep "was not found" /tmp/decrypt_error.${PID}) != "" ]] && sed -i "/^vault_password_file.*$/,+d" ${ANSIBLE_CFG} && ansible-vault decrypt --vault-password-file ${2} ${1} &>/dev/null
	rm -f ${2} /tmp/decrypt_error.${PID}
}

function check_updates() {
	if [[ "x$(git config user.name)" != "x" ]]
	then
		if [[ -f ${1} ]]
		then
			cp ${1} ${1}.${ENAME}
			[[ $- =~ x ]] && debug=1 && set +x
			[[ ! -f ${2} ]] && printf "$(git config remote.origin.url | cut -d '/' -f3 | cut -d '@' -f1)" > ${2}
			i=0
			retries=3
			while [ ${i} -lt ${retries} ]
			do
				[[ $(grep "ANSIBLE_VAULT" ${1}.${ENAME}) != "" ]] && decrypt_vault ${1}.${ENAME} ${2} $(git config user.email | cut -d'@' -f1) || break
				i=$((++i))
				[[ ${i} -eq ${retries} ]] && echo "Unable to decrypt Repository password vault. Exiting!" && exit 1
			done
			source ${1}.${ENAME}
			[[ ${debug} == 1 ]] && set -x
			rm ${1}.${ENAME}
		else
			echo
			read -sp "Enter your Repository password [ENTER]: " REPOPASS
			[[ $- =~ x ]] && debug=1 && set +x
			[[ -f ${1} ]] && rm -f ${1}
			[[ -f ${2} ]] && rm -f ${2}
			printf "REPOPASS='${REPOPASS}'\n" > ${1}
			printf "$(git config remote.origin.url | cut -d '/' -f3 | cut -d '@' -f1)" > ${2}
			encrypt_vault ${1} ${2} $(git config user.email | cut -d'@' -f1)
			[[ ${debug} == 1 ]] && set -x
			echo
		fi
		git rev-parse --short HEAD &>/dev/null
		if [ ${?} -eq 0 ]
		then
			local LOCALID=$(git rev-parse --short HEAD)
			[[ $(git config --get remote.origin.url | grep "www-github") == "" ]] && [[ "x$(echo ${http_proxy})" != "x" ]] && reset_proxy="true"
			for i in {1..3}
			do
				[[ $- =~ x ]] && debug=1 && set +x
				local REPOPWD=$(echo ${REPOPASS} | sed -e 's/@/%40/g')
				local REMOTEID=$([[ ${reset_proxy} ]] && unset https_proxy; git ls-remote $(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${REPOPWD}@|") refs/heads/$(git branch | awk '{print $NF}') 2>/dev/null | cut -c1-7)
				[[ ${debug} == 1 ]] && set -x
				[[ ${REMOTEID} == "" ]] && sleep 3 || break
			done
			[[ "${REMOTEID}" == "" ]] && printf "\nYour Repository credentials are invalid!\n\n" && rm -f ${1} && exit
			if [[ "${LOCALID}" != "${REMOTEID}" ]]
			then
				echo
				read -p "Your installation package is not up to date. Updating it will overwrite any changes to tracked files. Do you want to update? ${BOLD}(y/n)${NORMAL}: " ANSWER
				echo ""
				if [[ "$(echo ${ANSWER} | tr [A-Z] [a-z])" == "y" ]]
				then
					git reset -q --hard origin/$(git branch | awk '{print $NF}')
					git pull $(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${REPOPASS}@|") &>${PWD}/.pullerr && sed -i "s|${REPOPASS}|xxxxx|" ${PWD}/.pullerr
					[[ ${?} == 0 ]] && printf "\nThe installation package has been updated. ${BOLD}Please re-run the script for the updates to take effect${NORMAL}\n\n"
					[[ ${?} != 0 ]] && printf "\nThe installation package update has failed with the following error:\n\n${BOLD}$(cat ${PWD}/.pullerr)${NORMAL}\n\n"
					rm -f ${PWD}/.pullerr
					EC='exit'
				else
					EC='continue'
				fi
			fi
			[[ ${reset_proxy} == "true" ]] && source ~/.bashrc /etc/profile /etc/environment
			${EC}
		fi
	fi
}

function get_hostsinplay() {
	local ENVS=$(ps -ef | grep play.sh | grep envname | grep -v grep | grep -v ${ENAME} | awk -F 'envname ' '{print $NF}' | cut -d'-' -f1 | sort -u)
	local HN=""
	for env in ${ENVS}
	do
		HN="${HN}$(cat inventories/${env}/hosts | awk '{print $1}' | egrep -v '\[|=' | sed '/^$/d')"
	done
	echo ${HN}
}

function get_sleeptime() {
	local HN=$(get_hostsinplay)
	local HN=( ${HN} )
	local HOSTNUM=${#HN[@]}
	echo $((${HOSTNUM} + ${HOSTNUM} / 4))
}

function update_inventory() {
	if [[ "${ENAME}" != "" ]]
	then
		if [[ "$(echo ${ENAME} | awk -F ' ' '{print $2}')" == "" ]]
		then
			sed -i "s|\(^inventory =\).*$|\1 inventories/${ENAME}|" ${ANSIBLE_CFG}
		else
			printf "\nYou can install only one Environment at a time!\nRe-run the script with --envname <environment name as defined under Inventories>\n\n" && exit 1
		fi
	else
		printf "\nEnvironment name is required!\nRe-run the script with --envname <environment name as defined under Inventories>\n\n" && exit 1
	fi
}

function get_hosts() {
	if [ "x$(echo ${@} | egrep -w '\-\-limit')" != "x" ]
	then
		HOST_LIST=$(echo ${@} | awk -F '--limit ' '{print $NF}' | awk -F ' -' '{print $1}' | sed -e 's/,/ /g')
	else
		HOST_LIST=$(ansible all -m debug -a var=ansible_play_hosts | grep '[0-9]\{2\}"' | sort -u | sed -e 's/^.*"\(.*[0-9]\{2\}\)".*$/\1/g')
	fi
}

function check_mode() {
	[[ "$(echo ${@} | egrep -w '\-\-check')" != "" ]] && echo " in check mode " || echo " "
}

function enable_logging() {
	LOG=true
	if [ "${LOG}" == "true" ]
	then
		if [[ ! -d "${ANSIBLE_LOG_LOCATION}" ]]
		then
			if [[ "x${SUDO_PASS}" == "x" ]]
			then
				echo
				SUDO_PASS=$(get_sudopass) || FS=${?}
				[[ "${FS}" == 1 ]] && echo -e "\n${SUDO_PASS}\n" && exit ${FS}
			fi
			sudo -S mkdir -m 777 -p ${ANSIBLE_LOG_LOCATION} <<< ${SUDO_PASS}
		else
			if [[ ! -w "${ANSIBLE_LOG_LOCATION}" ]]
			then
				if [[ "x${SUDO_PASS}" == "x" ]]
				then
					echo
					SUDO_PASS=$(get_sudopass) || FS=${?}
					[[ "${FS}" == 1 ]] && echo -e "\n${SUDO_PASS}\n" && exit ${FS}
				fi
				sudo -S chmod 777 ${ANSIBLE_LOG_LOCATION} <<< ${SUDO_PASS}
			fi
 		fi
		LOG_FILE="${ANSIBLE_LOG_LOCATION}/$(basename ${0} | awk -F '.' '{print $1}').${ENAME}.log"
		[[ "$( grep ^log_path ${ANSIBLE_CFG} )" != "" ]] && sed -i '/^log_path = .*\$/d' ${ANSIBLE_CFG}
		if [[ -f ${LOG_FILE} ]] && [[ "${repeat_job}" != "" ]]
		then
			printf "\nRunning multiple instances of ${BOLD}$(basename ${0})${NORMAL} is prohibited. Aborting!\n\n" && exit 1
		else
			export ANSIBLE_LOG_PATH=${LOG_FILE}
		fi
		printf "############################################################\nAnsible Control Machine $(hostname) $(ip a show $(ip link | grep 2: | head -1 | awk '{print $2}') | grep 'inet ' | cut -d '/' -f1 | awk '{print $2}')\nThis script was run$(check_mode ${@})by $(git config user.name) ($(git config remote.origin.url | sed -e 's|.*\/\/\(.*\)@.*|\1|')) on $(date)\n############################################################\n\n" > ${LOG_FILE}
	fi
}

function get_credentials() {
	if [[ ${GET_INVENTORY_STATUS} == 0 && ! -f ${CRVAULT} ]]
	then
		if [[ "x$(echo ${@} | egrep -w '\-\-limit')" != "x" ]]
		then
			local MYHOSTS=$(echo ${@} | awk -F '--limit ' '{print $NF}' | awk -F ' -' '{print $1}')
			local ARG_NAME="--limit"
			for arg
			do
				shift
				[[ ${arg} == ${ARG_NAME} || ${arg} == ${MYHOSTS} ]] && continue
				set -- ${@} ${arg}
			done
		fi
		ansible-playbook playbooks/prompts.yml --extra-vars "{VFILE: '${CRVAULT}'}" ${@} -e @${ANSIBLE_VARS} -v
		GET_CREDS_STATUS=${?}
		[[ ${GET_CREDS_STATUS} != 0 ]] && exit 1
		if [[ ${REPOPASS} != "" ]]
		then
			[[ $- =~ x ]] && debug=1 && set +x
			encrypt_vault ${CRVAULT} ${VAULTP} ${REPOPASS}
			[[ ${debug} == 1 ]] && set -x
		else
			echo "Repository password is not defined. Aborting!"
			exit 1
		fi
	fi
}

function run_playbook() {
	if [[ ${GET_INVENTORY_STATUS} == 0 && (${GET_CREDS_STATUS} == 0 || -f ${CRVAULT}) ]]
	then
		### Begin: Determine if ASK_PASS is required
		[ $(echo ${HOST_LIST} | wc -w) -gt 1 ] && HL=$(echo ${HOST_LIST} | sed 's/ /,/g') || HL=${HOST_LIST}
		ansible ${HL} -m debug -a 'msg={{ansible_ssh_pass}}' &>/dev/null && [[ ${?} == 0 ]] && ASK_PASS=''
		### End
		[[ ! -f ${VAULTC} ]] && git config remote.origin.url | awk -F '/' '{print $NF}' > ${VAULTC}
		if [[ $(grep vault_password_file ${ANSIBLE_CFG}) != "" ]]
		then
			sed -i "s|\(^vault_password_file =\).*$|\1 ${VAULTC}|" ${ANSIBLE_CFG}
		else
			echo "vault_password_file = ${VAULTC}" >> ${ANSIBLE_CFG}
		fi
		[[ $- =~ x ]] && debug=1 && set +x
		[[ -f ${PASSVAULT} ]] && cp ${PASSVAULT} ${PASSFILE} || PV="ERROR"
		[[ ${PV} == "ERROR" ]] && echo "Passwords.yml file is missing. Aborting!" && exit 1
		[[ ! -f ${VAULTP} ]] && echo ${REPOPASS} > ${VAULTP}
		[[ ${debug} == 1 ]] && set -x
		sleep 1 && sed -i "/^vault_password_file.*$/,+d" ${ANSIBLE_CFG} &
		ansible-playbook playbooks/site.yml --extra-vars "{VFILE: '${CRVAULT}', VPFILE: '${VAULTP}', VCFILE: '${VAULTC}', PASSFILE: '${PASSFILE}', $(echo $0 | sed -e 's/.*play_\(.*\)\.sh/\1/'): true}" ${ASK_PASS} ${@} -e @${PASSFILE} -e @${CRVAULT} --vault-password-file ${VAULTP} -e @${ANSIBLE_VARS} -v 2> /tmp/${PID}.stderr
		[[ $(grep "no vault secrets were found that could decrypt" /tmp/${PID}.stderr | grep  ${PASSFILE}) != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${PASSFILE//.${ENAME}}${NORMAL}" && EC=1
		[[ $(grep "no vault secrets were found that could decrypt" /tmp/${PID}.stderr | grep ${CRVAULT}) != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${CRVAULT}${NORMAL}" && rm -f ${CRVAULT} && EC=1
		rm -f /tmp/${PID}.stderr ${VAULTC} ${VAULTP}
		sed -i "s|\(^inventory =\).*$|\1 inventories|" ${ANSIBLE_CFG}
		[[ ${EC} == 1 ]] && exit 1
	fi
}

function disable_logging() {
	if [ "${LOG}" == "true" ] && [ -f ${LOG_FILE} ]
	then
		unset ANSIBLE_LOG_PATH
		NEW_LOG_FILE=${LOG_FILE}.$(ls --full-time ${LOG_FILE} | awk '{print $6"-"$7}')
		mv ${LOG_FILE} ${NEW_LOG_FILE}
		printf "\nThe log file is ${BOLD}${NEW_LOG_FILE}${NORMAL}\n\n"
	fi
}

function send_notification() {
	if [ "$(check_mode ${@})" == " " ]
	then
		SCRIPT_ARG=$(echo ${@} | sed -e 's/-/dash/g')
		[ $(echo ${HOST_LIST} | wc -w) -gt 1 ] && HL=$(echo ${HOST_LIST} | sed 's/ /,/g') || HL=${HOST_LIST}
		# Send playbook status notification
		ansible-playbook playbooks/notify.yml --extra-vars "{SNAME: '$(basename ${0})', SARG: '${SCRIPT_ARG}', LFILE: '${NEW_LOG_FILE}'}" --limit ${HL} --tags notify -e @${ANSIBLE_VARS} -v &>/dev/null &
	fi
}

# Parameters definition
ANSIBLE_CFG="./ansible.cfg"
ANSIBLE_LOG_LOCATION="/var/tmp/ansible"
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
PKG_LIST='epel-release sshpass python2-pip'
ANSIBLE_VERSION='2.9.5'
ANSIBLE_VARS="${PWD}/vars/datacenters.yml"
PASSVAULT="${PWD}/vars/passwords.yml"

# Main
PID=${$}
check_arguments ${@}
NEW_ARGS=$(check_hosts_limit "${@}")
set -- && set -- ${@} ${NEW_ARGS}
CC=$(check_concurrency)
ORIG_ARGS=${@}
ENAME=$(get_envname ${ORIG_ARGS})
REPOVAULT="${PWD}/.repovault.yml"
CRVAULT="${PWD}/inventories/${ENAME}/group_vars/vault.yml"
VAULTP="${PWD}/.vaultp.${ENAME}"
VAULTC="${PWD}/.vaultc.${ENAME}"
SYS_DEF="${PWD}/Definitions/${ENAME}.yml"
PASSFILE="${PASSVAULT}.${ENAME}"
check_repeat_job
NEW_ARGS=$(clean_arguments "${ENAME}" "${@}")
set -- && set -- ${@} ${NEW_ARGS}
git_config
install_packages
check_updates ${REPOVAULT} ${VAULTP}
get_inventory ${@}
[[ "${CC}" != "" ]] && SLEEPTIME=$(get_sleeptime) && [[ ${SLEEPTIME} != 0 ]] && echo "Sleeping for ${SLEEPTIME}" && sleep ${SLEEPTIME}
update_inventory
get_hosts ${@}
get_credentials ${@}
enable_logging ${@}
run_playbook ${@}
disable_logging
send_notification ${ORIG_ARGS}
