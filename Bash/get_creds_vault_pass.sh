#! /bin/bash
ansible-vault view .repovault.yml --vault-password-file Bash/get_repo_vault_pass.sh | awk -F "'" '{print $2}'