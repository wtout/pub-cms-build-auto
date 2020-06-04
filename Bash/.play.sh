# Functions declaration

function get_envname() {
	[[ "$(echo ${@} | egrep -w '\-\-envname')" != "" ]] && envname=$(echo ${@} | awk -F 'envname ' '{print $NF}' | cut -d'-' -f1)
	echo ${envname}
}

function check_arguments() {
	if [[ "x$(echo ${@} | egrep -w '\-\-envname')" == "x" ]]
	then
		printf "\nEnvironment name is required!\nRe-run the script with ${BOLD}--envname${NORMAL} <environment name as defined under Inventories>\n\n"
		exit 1
	else
		[[ $(wc -w <<< $(get_envname ${@})) -ge 2 ]] && printf "\nYou can deploy only one environment at a time. Aborting!\n\n" && exit 1
	fi
}

function check_repeat_job() {
	repeat_job=$( ps -ef | grep ${ENAME} | grep $(basename ${0} | awk -F '.' '{print $1}') | grep -v ${PID} )
}

function check_hosts_limit() {
	[[ "x$(echo ${@} | egrep -w '\-\-limit')" != "x" ]] && [[ "x$(echo ${@} | egrep -w 'vcenter')" == "x" ]] && local ARG_NAME="--limit" && local MYACTION="add"
	[[ "x$(echo ${@} | egrep -w '\-l')" != "x" ]] && [[ "x$(echo ${@} | egrep -w 'vcenter')" == "x" ]] && local ARG_NAME="-l" && local MYACTION="add"
	if [[ ${MYACTION} == "add" ]]
	then
		local MYHOSTS=$(echo ${@} | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}')
		[[ "x$(echo ${@} | egrep -w '\-\-tags')" != "x" ]] && local MYTAGS=$(echo ${@} | awk -F '--tags ' '{print $NF}' | awk -F ' -' '{print $1}')
		[[ "x$(echo ${MYTAGS})" == "x" ]] && local update_args=1
		[[ "x$(echo ${MYTAGS} | egrep -w 'vm_creation')" != "x" ]] && local update_args=1
		if [[ ${update_args} -eq 1 ]]
		then
			local NEWARGS=$(echo ${@} | sed "s/${MYHOSTS}/${MYHOSTS},vcenter/")
		else
			local NEWARGS=${@}
		fi
	else
		local NEWARGS=${@}
	fi
	echo ${NEWARGS}
}

function check_concurrency() {
	ps -ef | grep $(basename ${0}) | grep -v grep | grep -v ${PID}
}

function clean_arguments() {
	# Remove --envname argument from script arguments
	local OPTION_NAME="--envname"
	local ENVNAME=${1}
	if [[ "x$(echo ${@} | egrep -w '\-\-envname')" != "x" ]]
	then
		shift
		local NEWARGS=$(echo ${@} | sed "s/${OPTION_NAME} ${ENVNAME}//")
	else
		local NEWARGS=${@}
	fi
	echo ${NEWARGS}
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

function get_centos_release() {
	cat /etc/centos-release | sed 's/^.*\([0-9]\{1,\}\)\.[0-9]\{1,\}\.[0-9]\{1,\}.*$/\1/'
}

function get_proxy() {
	grep -r "proxy.*=.*ht" /etc/environment /etc/profile ~/.bashrc ~/.bash_profile | cut -d '"' -f2 | uniq
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
			[[ ${?} == 0 ]] && printf " Installed version $(yum list installed ${pkg} | tail -1 | awk '{print $2}')\n" || exit 1
		fi
	done
	if [[ $(get_centos_release) -ne 8 ]]
	then
		if [[ "x$(which pip3 2>/dev/null)" == "x" ]]
		then
			if [[ "x${SUDO_PASS}" == "x" ]]
			then
				echo
				SUDO_PASS=$(get_sudopass) || FS=${?}
				[[ "${FS}" == 1 ]] && echo -e "\n${SUDO_PASS}\n" && exit ${FS}
			fi
			printf "\nInstalling python3 on localhost ..."
			sudo -S yum install -y python3 --quiet <<< ${SUDO_PASS} 2>/dev/null
			[[ ${?} == 0 ]] && printf " Installed version $(yum list installed python3 | tail -1 | awk '{print $2}')\n" || exit 1
			printf "\nInstalling libselinux-python3 on localhost ..."
			sudo -S yum install -y libselinux-python3 --quiet <<< ${SUDO_PASS} 2>/dev/null
			[[ ${?} == 0 ]] && printf " Installed version $(yum list installed libselinux-python3 | tail -1 | awk '{print $2}')\n" || exit 1
		fi
	fi
	if [ "x$(which ansible 2>/dev/null)" == "x" ]
	then
		printf "\nInstalling ansible on localhost ..."
		pip3 install --user --no-cache-dir --quiet -I ansible==${ANSIBLE_VERSION} --proxy="$(get_proxy)"
		[[ ${?} == 0 ]] && printf " Installed version ${ANSIBLE_VERSION}\n" || exit 1
	else
		if [ "$(printf '%s\n' $(ansible --version | grep ^ansible | awk -F 'ansible ' '{print $NF}') ${ANSIBLE_VERSION} | sort -V | head -1)" != "${ANSIBLE_VERSION}" ]
		then
			printf "\nUpgrading Ansible from version $(ansible --version | grep '^ansible' | cut -d ' ' -f2)"
			pip3 install --user --no-cache-dir --quiet --upgrade -I ansible==${ANSIBLE_VERSION} --proxy="$(get_proxy)"
			[[ ${?} == 0 ]] && printf " to version ${ANSIBLE_VERSION}\n" || exit 1
		fi
	fi
}

function remove_hosts_arg() {
	# Remove --limit or -l argument from script arguments
	[[ "x$(echo ${@} | egrep -w '\-\-limit')" != "x" ]] && local ARG_NAME="--limit" && local MYACTION="clean"
	[[ "x$(echo ${@} | egrep -w '\-l')" != "x" ]] && local ARG_NAME="-l" && local MYACTION="clean"
	if [[ ${MYACTION} == "clean" ]]
	then
		local MYARGS=$(echo ${@} | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}')
		local NEWARGS=$(echo ${@} | sed "s/${ARG_NAME} ${MYARGS}//")
	else
		local NEWARGS=${@}
	fi
	echo ${NEWARGS}
}

function remove_extra_vars_arg() {
	# Remove --extra-vars or -e argument from script arguments
	[[ "x$(echo ${@} | egrep -w '\-\-extra\-vars')" != "x" ]] && local ARG_NAME="--extra-vars" && local MYACTION="clean"
	[[ "x$(echo ${@} | egrep -w '\-e')" != "x" ]] && local ARG_NAME="-e" && local MYACTION="clean"
	if [[ ${MYACTION} == "clean" ]]
	then
		local MYARGS=$(echo ${@} | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}')
		local NEWARGS=$(echo ${@} | sed "s/${ARG_NAME} ${MYARGS}//")
	else
		local NEWARGS=${@}
	fi
	echo ${NEWARGS}
}

function install_pypkgs() {
	ansible-playbook playbooks/pypkgs.yml --extra-vars "{SYS_NAME: '${SYS_DEF}'}" $(remove_extra_vars_arg $(remove_hosts_arg ${@})) -e @${ANSIBLE_VARS} -v
	INSTALL_PYPKGS_STATUS=${?}
	[[ ${INSTALL_PYPKGS_STATUS} != 0 ]] && echo -e "\n${BOLD}Unable to install Python packages successfully. Aborting!${NORMAL}" && exit 1
}

function get_inventory() {
	sed -i "/^vault_password_file.*$/,+d" ${ANSIBLE_CFG}
	if [[ ${INSTALL_PYPKGS_STATUS} == 0 ]]
	then
		if [[ -f ${SYS_DEF} ]]
		then
			ansible-playbook playbooks/getinventory.yml --extra-vars "{SYS_NAME: '${SYS_DEF}'}" $(remove_extra_vars_arg $(remove_hosts_arg ${@})) -e @${ANSIBLE_VARS} -v
			GET_INVENTORY_STATUS=${?}
			[[ ${GET_INVENTORY_STATUS} != 0 ]] && exit 1
		elif [[ $(echo ${ENAME} | grep -i mdr) != '' ]]
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
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && ansible-vault encrypt --vault-password-file ${2} ${1} &>/dev/null
}

function decrypt_vault() {
	[[ -f ${1} ]] && [[ -f ${2} ]] && [[ -x ${2} ]] && ansible-vault decrypt --vault-password-file ${2} ${1} 2> /tmp/decrypt_error.${PID}
	[[ $(grep "was not found" /tmp/decrypt_error.${PID}) != "" ]] && sed -i "/^vault_password_file.*$/,+d" ${ANSIBLE_CFG} && ansible-vault decrypt --vault-password-file ${2} ${1} &>/dev/null
	rm -f /tmp/decrypt_error.${PID}
}

function check_updates() {
	if [[ "x$(git config user.name)" != "x" ]]
	then
		if [[ -f ${1} ]]
		then
			cp ${1} ${1}.${ENAME}
			i=0
			retries=3
			while [ ${i} -lt ${retries} ]
			do
				[[ $(grep "ANSIBLE_VAULT" ${1}.${ENAME}) != "" ]] && decrypt_vault ${1}.${ENAME} ${2} || break
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
			printf "REPOPASS='${REPOPASS}'\n" > ${1}
			encrypt_vault ${1} ${2}
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
				if [[ "$(echo ${ANSWER} | tr '[A-Z]' '[a-z]')" == "y" ]]
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
		HN="${HN}$(cat ${INVENTORY_PATH}}/hosts | awk '{print $1}' | egrep -v '\[|=' | sed '/^$/d')"
	done
	echo ${HN}
}

function get_sleeptime() {
	local HN=$(get_hostsinplay)
	local HN=( ${HN} )
	local HOSTNUM=${#HN[@]}
	echo $((${HOSTNUM} + ${HOSTNUM} / 4))
}

function get_hosts() {
	[[ "x$(echo ${@} | egrep -w '\-\-limit')" != "x" ]] && local ARG_NAME="--limit" && local MYACTION="get"
	[[ "x$(echo ${@} | egrep -w '\-l')" != "x" ]] && local ARG_NAME="-l" && local MYACTION="get"
	if [[ ${MYACTION} == "get" ]]
	then
		HOST_LIST=$(echo ${@} | awk -F "${ARG_NAME} " '{print $NF}' | awk -F ' -' '{print $1}' | sed -e 's/,/ /g')
	else
		HOST_LIST=$(ansible all -i ${INVENTORY_PATH} --list-hosts | grep -v host | sed -e 's/^\s*\(\w.*\)$/\1/g' | sort)
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

function get_bastion_address() {
	ansible localhost -i ${INVENTORY_PATH} -m debug -a var=bastion.address | grep address | awk -F ': ' '{print $NF}'
}

function get_credentials() {
	if [[ ${GET_INVENTORY_STATUS} == 0 && $(get_bastion_address) != '[]' && ! -f ${CRVAULT} ]]
	then
		ansible-playbook playbooks/prompts.yml -i ${INVENTORY_PATH} --extra-vars "{VFILE: '${CRVAULT}'}" $(remove_extra_vars_arg $(remove_hosts_arg ${@})) -e @${ANSIBLE_VARS} -v
		GET_CREDS_STATUS=${?}
		[[ ${GET_CREDS_STATUS} != 0 ]] && exit 1
		if [[ ${REPOPASS} != "" ]]
		then
			[[ $- =~ x ]] && debug=1 && set +x
			encrypt_vault ${CRVAULT} Bash/get_creds_vault_pass.sh
			[[ ${debug} == 1 ]] && set -x
		else
			echo -e "\n${BOLD}Repository password is not defined. Aborting!${NORMAL}"
			exit 1
		fi
	fi
}

function run_playbook() {
	if [[ ${GET_INVENTORY_STATUS} == 0 && (($(get_bastion_address) != '[]' && (${GET_CREDS_STATUS} == 0 || -f ${CRVAULT})) || $(get_bastion_address) == '[]') ]]
	then
		### Begin: Determine if ASK_PASS is required
		[ $(echo ${HOST_LIST} | wc -w) -gt 1 ] && HL=$(echo ${HOST_LIST} | sed 's/ /,/g') || HL=${HOST_LIST}
		ansible ${HL} -m debug -a 'msg={{ansible_ssh_pass}}' &>/dev/null && [[ ${?} == 0 ]] && ASK_PASS=''
		### End
		### Begin: Define the extra-vars argument list and bastion credentials vault name and password file
		if [[ $(get_bastion_address) == '[]' ]]
		then
			local EVARGS="{PASSFILE: '${PASSFILE}', $(echo $0 | sed -e 's/.*play_\(.*\)\.sh/\1/'): true}"
			local BCV=""
		else
			local EVARGS="{VFILE: '${CRVAULT}', SCRTFILE: 'Bash/get_creds_vault_pass.sh', PASSFILE: '${PASSFILE}', $(echo $0 | sed -e 's/.*play_\(.*\)\.sh/\1/'): true}"
			local BCV="-e @${CRVAULT} --vault-password-file Bash/get_creds_vault_pass.sh"
		fi
		### End
		[[ -f ${PASSVAULT} ]] && cp ${PASSVAULT} ${PASSFILE} || PV="ERROR"
		[[ ${PV} == "ERROR" ]] && echo "Passwords.yml file is missing. Aborting!" && exit 1
		ansible-playbook playbooks/site.yml -i ${INVENTORY_PATH} --extra-vars "${EVARGS}" ${ASK_PASS} ${@} -e @${PASSFILE} --vault-password-file Bash/get_common_vault_pass.sh ${BCV} -e @${ANSIBLE_VARS} -v 2> /tmp/${PID}.stderr
		[[ $(grep "no vault secrets were found that could decrypt" /tmp/${PID}.stderr | grep  ${PASSFILE}) != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${PASSFILE}.${ENAME}${NORMAL}" && EC=1
		[[ $(grep "no vault secrets were found that could decrypt" /tmp/${PID}.stderr | grep ${CRVAULT}) != "" ]] && echo -e "\nUnable to decrypt ${BOLD}${CRVAULT}${NORMAL}" && rm -f ${CRVAULT} && EC=1
		rm -f /tmp/${PID}.stderr
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
		NUM_HOSTS=$(wc -w <<< $(echo ${HL} | sed 's/,/ /g'))
		# Send playbook status notification
		ansible-playbook playbooks/notify.yml --extra-vars "{SNAME: '$(basename ${0})', SARG: '${SCRIPT_ARG}', LFILE: '${NEW_LOG_FILE}', NHOSTS: '${NUM_HOSTS}'}" --tags notify -e @${ANSIBLE_VARS} -v &>/dev/null &
	fi
}

# Parameters definition
ANSIBLE_CFG="./ansible.cfg"
ANSIBLE_LOG_LOCATION="/var/tmp/ansible"
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
PKG_LIST="epel-release sshpass"
ANSIBLE_VERSION='2.9.9'
ANSIBLE_VARS="${PWD}/vars/datacenters.yml"
PASSVAULT="${PWD}/vars/passwords.yml"
REPOVAULT="${PWD}/.repovault.yml"

# Main
PID=${$}
check_arguments ${@}
NEW_ARGS=$(check_hosts_limit "${@}")
set -- && set -- ${@} ${NEW_ARGS}
CC=$(check_concurrency)
ORIG_ARGS=${@}
ENAME=$(get_envname ${ORIG_ARGS})
INVENTORY_PATH="${PWD}/inventories/${ENAME}"
CRVAULT="${INVENTORY_PATH}/group_vars/vault.yml"
SYS_DEF="${PWD}/Definitions/${ENAME}.yml"
PASSFILE="${PASSVAULT}.${ENAME}"
check_repeat_job
NEW_ARGS=$(clean_arguments "${ENAME}" "${@}")
set -- && set -- ${@} ${NEW_ARGS}
git_config
install_packages
check_updates ${REPOVAULT} Bash/get_repo_vault_pass.sh
install_pypkgs ${@}
get_inventory ${@}
[[ "${CC}" != "" ]] && SLEEPTIME=$(get_sleeptime) && [[ ${SLEEPTIME} != 0 ]] && echo "Sleeping for ${SLEEPTIME}" && sleep ${SLEEPTIME}
get_hosts ${@}
get_credentials ${@}
enable_logging ${@}
run_playbook ${@}
disable_logging
send_notification ${ORIG_ARGS}
