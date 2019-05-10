# Functions declaration

function check_concurrency(){
	PID=${$}
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
		[[ "${arg}" == "${OPTION_NAME}" || "${ENVNAME}" == *"${arg}"* ]] && continue
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
				read -p "Enter your full name [ENTER]: " NAME SURNAME && [[ "${SURNAME}" != "" && "$(git config remote.origin.url | sed -e 's/.*\/\/\(.*\)@.*/\1/')" == *$(echo ${SURNAME} | tr '[A-Z]' '[a-z]')* ]] && git config user.name "${NAME} ${SURNAME}" || EC=1
			fi
		fi
		[[ ${EC} -eq 1 ]] && echo "Invalid ID. Aborting!" && exit ${EC}
		if [[ "x$(git config user.email)" == "x" ]]
		then
			NAME=$(git config user.name | awk '{print $1}' | tr '[A-Z]' '[a-z]')
			SURNAME=$(git config user.name | awk '{print $NF}' | tr '[A-Z]' '[a-z]')
			if [[ "$(git config remote.origin.url)" == "" ]]
			then
				read -p "Enter your email address [ENTER]: " GIT_EMAIL_ADDRESS && [[ "${GIT_EMAIL_ADDRESS}" != "" && ("$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${NAME}* || "$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${SURNAME}*) ]] && git config user.email ${GIT_EMAIL_ADDRESS} || EC=1
			else
				read -p "Enter your email address [ENTER]: " GIT_EMAIL_ADDRESS && [[ "${GIT_EMAIL_ADDRESS}" != "" && ("$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${NAME}* || "$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/.*= \(.*\)@.*/\1/')" == *${SURNAME}*) && "$(git config remote.origin.url)" == *$(echo ${GIT_EMAIL_ADDRESS} | sed -e 's/^.*@\(.*\)\..*$/\1/')* ]] && git config user.email ${GIT_EMAIL_ADDRESS} || EC=1
			fi
		fi
		[[ ${EC} -eq 1 ]] && echo "Invalid email address. Aborting!" && exit ${EC}
	else
		echo "Please ensure git is installed on this machine before running script. Aborting!" && exit 1
	fi
}

function get_sudopass(){
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
			printf " Installed version $(yum list ${pkg} | tail -1 | awk '{print $2}')\n"
		fi
	done
	if [ "x$(which pip 2>/dev/null)" == "x" ]
	then
		if [[ "x${SUDO_PASS}" == "x" ]]
		then
			echo
			SUDO_PASS=$(get_sudopass) || FS=${?}
			[[ "${FS}" != 1 ]] && echo -e "\n${SUDO_PASS}" && exit ${FS}
		fi
		printf "\nInstalling pip on localhost ..."
		sudo -S yum install -y python-pip --quiet <<< ${SUDO_PASS} 2>/dev/null
		printf " Installed version $(pip -V 2>/dev/null | awk '{print $2}')\n"
	fi
	if [ "x$(which ansible 2>/dev/null)" == "x" ]
	then
		printf "\nInstalling ansible on localhost ..."
		pip install --user --no-cache-dir --quiet -I ansible==${ANSIBLE_VERSION}
		printf " Installed version ${ANSIBLE_VERSION}\n"
	else
		if [ "$(printf '%s\n' $(ansible --version | grep ^ansible | awk -F 'ansible ' '{print $NF}') ${ANSIBLE_VERSION} | sort -V | head -1)" != "${ANSIBLE_VERSION}" ]
		then
			echo "Upgrading ansible to the required ${ANSIBLE_VERSION} version"
			pip install --user --no-cache-dir --quiet --upgrade -I ansible==${ANSIBLE_VERSION}
		fi
	fi
}

function encrypt_vault() {
	echo $(git config user.email | cut -d'@' -f1) > ${2}
	[[ -f ${1} ]] && ansible-vault --vault-id ${2} encrypt ${1} &>/dev/null
	rm -f ${2}
}

function decrypt_vault() {
	echo $(git config user.email | cut -d'@' -f1) > ${2}
	[[ -f ${1} ]] && ansible-vault --vault-id ${2} decrypt ${1} &>/dev/null
	rm -f ${2}
}

function check_updates {
	if [[ "x$(git config user.name)" != "x" ]]
	then
		git rev-parse --short HEAD &>/dev/null
		if [ ${?} -eq 0 ]
		then
			echo $(git config user.name) > ${2}
			if [[ -f ${1} ]]
			then
				decrypt_vault ${1} ${2}
				source ${1}
				encrypt_vault ${1} ${2}
			else
				echo
				read -sp "Enter your Bitbucket password [ENTER]: " BBPASS
				printf "BBPASS=${BBPASS}\n" > ${1}
				encrypt_vault ${1} ${2}
				echo
			fi
			rm -f ${2}
			local LOCALID=$(git rev-parse --short HEAD)
			local REMOTEID=$(git ls-remote $(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${BBPASS}@|") HEAD 2>/dev/null | cut -c1-7)
			[[ "${REMOTEID}" == "" ]] && printf "\nYour Bitbucket credentials are invalid!\n\n" && rm -f ${1} && exit
			if [[ "${LOCALID}" != "${REMOTEID}" ]]
			then
				echo
				read -p "Your installation package is not up to date. Updating it will overwrite any changes to tracked files. Do you want to update? ${BOLD}(y/n)${NORMAL}: " ANSWER
				echo ""
				if [[ "$(echo ${ANSWER} | tr [A-Z] [a-z])" == "y" ]]
				then
					git reset -q --hard origin/master
					git pull $(git config --get remote.origin.url | sed -e "s|\(//.*\)@|\1:${BBPASS}@|") &>${PWD}/.pullerr
					[[ ${?} == 0 ]] && printf "\nThe installation package has been updated. ${BOLD}Please re-run the script for the updates to take effect${NORMAL}\n\n"
					[[ ${?} != 0 ]] && printf "\nThe installation package update has failed with the following error:\n\n${BOLD}$(cat ${PWD}/.pullerr)${NORMAL}\n\n"
					rm -f ${PWD}/.pullerr
					EC='exit'
				else
					rm -f ${1}
					EC='continue'
				fi
			fi
			${EC}
		fi
	fi
}

function get_hostsinplay(){
	local ENVS=$(ps -ef | grep play.sh | grep envname | grep -v grep | grep -v ${ENAME} | awk -F 'envname ' '{print $NF}' | cut -d'-' -f1 | sort -u)
	local HN=""
	for env in ${ENVS}
	do
		HN="${HN}$(cat inventories/${env}/hosts | awk '{print $1}' | egrep -v '\[|=' | sed '/^$/d')"
	done
	echo ${HN}
}

function get_sleeptime(){
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
		local HL=$(ansible $(echo ${@} | awk -F '--limit ' '{print $NF}' | awk -F ' -' '{print $1}') -m debug -a 'var=ansible_play_hosts' | sort -u | egrep -v "\[|\]|{|}" | sed -e 's/.*"\(.*\)".*/\1/g')
		ERROR_MSG="\n${BOLD}${HL}${NORMAL}\n\nThe hosts/groups in scope cannot be worked on during a single playbook run\nPlease review your '${BOLD}--limit${NORMAL}' list and try again\n\n"
	else
		HOST_LIST=$(ansible localhost -m debug -a 'var=ansible_play_batch' | sort -u | egrep -v "\[|\]|{|}" | sed -e 's/.*"\(.*\)".*/\1/g')
		ERROR_MSG="\n${BOLD}${HOST_LIST}${NORMAL}\n\nThe hosts/groups in scope cannot be worked on during a single playbook run\nPlease consider using the '${BOLD}--limit${NORMAL}' option to restrict the play to a subset of hosts or cleanup your inventory and try again\n\n"
	fi
}

function validate_hosts() {
	PASS='false'
	NOPASS='false'
	for host in ${HOST_LIST}
	do
		[ "x$(echo $( ansible ${host} -m debug -a 'var=group_names' | egrep -v "\[|\]|{|}" | sed -e 's/.*"\(.*\)".*/\1/g' | sort -u | tr '\n' ' ') | egrep -w 'aws|ec2|productionkey')" != "x" ] && NOPASS='true' || PASS='true'
		[ ${PASS} == ${NOPASS} ] && printf "${ERROR_MSG}" && exit 1
	done
	[ "x${PASS}" == "xtrue" ] && ASK_PASS="--ask-pass --ask-become-pass" || ASK_PASS=""
}

function check_mode() {
	[[ "$(echo ${@} | egrep -w '\-\-check')" != "" ]] && echo " in check mode " || echo " "
}

function enable_logging() {
	LOG=true
	if [ "${LOG}" == "true" ]
	then
		LOG_FILE="/var/tmp/$(basename ${0} | awk -F '.' '{print $1}').${ENAME}.log"
		[ "$(grep ^log_path ${ANSIBLE_CFG} | grep ${LOG_FILE})" != "" ] && printf "\nRunning multiple instances of ${BOLD}$(basename ${0})${NORMAL} is prohibited. Aborting!\n\n" && exit 1
		[ "$(grep ^log_path ${ANSIBLE_CFG} | grep ${LOG_FILE})" == "" ] && sed -i "s|^\(log_path = .*\)$|\1\nlog_path = ${LOG_FILE}|" ${ANSIBLE_CFG}
		[ "$(grep ^log_path ${ANSIBLE_CFG})" == "" ] && sed -i "s|^\(# Set the log_path\)$|\1\nlog_path = ${LOG_FILE}|" ${ANSIBLE_CFG}
		printf "############################################################\nThis script was run$(check_mode ${@})by $(git config user.name) ($(git config remote.origin.url | sed -e 's|.*\/\/\(.*\)@.*|\1|')) on $(date)\n############################################################\n\n" > ${LOG_FILE}
	fi
}

function get_credentials() {
	if [[ ! -f ${CRVAULT} ]]
	then
		ansible-playbook prompts.yml --extra-vars "{VFILE: '${CRVAULT}', $(echo $0 | sed -e 's/.*play_\(.*\)\.sh/\1/'): true}" ${ASK_PASS} ${@}
		GET_CREDS_STATUS=${?}
		encrypt_vault ${CRVAULT} ${VAULTP}
	fi
	rm -f ${VAULTP}
}

function run_playbook() {
	if [[ ${GET_CREDS_STATUS} == 0 || -f ${CRVAULT} ]]
	then
		[[ ! -f ${VAULTP} ]] && echo $(git config user.email | cut -d'@' -f1) > ${VAULTP}
		ansible-playbook site.yml --extra-vars "{VFILE: '${CRVAULT}', VPFILE: '${VAULTP}', $(echo $0 | sed -e 's/.*play_\(.*\)\.sh/\1/'): true}" ${ASK_PASS} ${@} -e @${CRVAULT} --vault-password-file ${VAULTP}
		rm -f ${VAULTP}
	fi
}

function disable_logging() {
	if [ "${LOG}" == "true" ] && [ -f ${LOG_FILE} ]
	then
		ELF=$(echo ${LOG_FILE} | sed 's|/|\\/|g')
		sed -i "/^log_path.*${ELF}$/,+d" ${ANSIBLE_CFG}
		NEW_LOG_FILE=${LOG_FILE}.$(ls --full-time ${LOG_FILE} | awk '{print $6"-"$7}')
		mv ${LOG_FILE} ${NEW_LOG_FILE}
	fi
}

function send_notification() {
#	disable_logging
	if [ "$(check_mode ${@})" == " " ]
	then
		SCRIPT_ARG=$(echo ${@} | sed -e 's/-/dash/g')
		[ $(echo ${HOST_LIST} | wc -w) -gt 1 ] && HL=$(echo ${HOST_LIST} | sed 's/ /,/g') || HL=${HOST_LIST}
		# Send playbook status notification
		ansible-playbook site.yml --extra-vars "{SNAME: '$(basename ${0})', SARG: '${SCRIPT_ARG}', LFILE: '${NEW_LOG_FILE}'}" --limit ${HL} --tags notify &>/dev/null
	fi
}

# Parameters definition
ANSIBLE_CFG="./ansible.cfg"
OFILE="${PWD}/Bash/override.sh"
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
PKG_LIST='epel-release sshpass'
ANSIBLE_VERSION='2.7.10'
BBVAULT="/var/tmp/.bbvault"
CRVAULT="/var/tmp/.crvault"
VAULTP="/var/tmp/.vaultp"

# Main
CC=$(check_concurrency)
ORIG_ARGS=${@}
ENAME=$(get_envname ${ORIG_ARGS})
NEW_ARGS=$(clean_arguments "${ENAME}" "${@}")
set -- && set -- ${@} ${NEW_ARGS}
git_config
install_packages
check_updates ${BBVAULT} ${VAULTP}
[[ "${CC}" != "" ]] && SLEEPTIME=$(get_sleeptime) && echo "Sleeping for ${SLEEPTIME}" && sleep ${SLEEPTIME}
update_inventory
get_hosts ${@}
#validate_hosts
get_credentials ${@}
enable_logging ${@}
[[ -f ${OFILE} ]] && source ${OFILE}
run_playbook ${@}
disable_logging
#send_notification ${ORIG_ARGS} &
