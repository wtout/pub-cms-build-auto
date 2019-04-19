[ $(echo ${HOST_LIST} | wc -w) -gt 1 ] && HL=$(echo ${HOST_LIST} | sed 's/ /,/g') || HL=${HOST_LIST}
ansible ${HL} -m debug -a 'msg={{ansible_ssh_pass}}' &>/dev/null && [[ ${?} == 0 ]] && ASK_PASS=''