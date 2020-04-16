#! /bin/bash
ansible-vault view --vault-password-file Bash/get_repo_vault_pass.sh .repovault.yml | awk -F "'" '{print $2}'