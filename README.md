# README #

This README provides instructions and information to get your Ansible control machine up and running with the automation package to deploy the CMS stack.

### Disclaimer ###

The deployment procedure has to be the same for all deployments. Ansible code contained in this repository is to automate the standard deployment procedure. Customization for a given customer is limited to the environment variables used during installation. Do not modify the Ansible code on the fly during a customer installation. Ansible code is NOT meant to be touched/edited except in the context of standard deployment procedure automation development. The usage information below gives the user the needed information to set up and execute the supported automated procedures.

### What is this repository for? ###

This repository contains Ansible scripts to be used in the full deployment of the CMS stack. The automation tool automatically downloads the CMS software package(s) to  the _``Packages``_ folder on the Ansible machine or on the bastion server if applicable.

### How do I get set up? ###

On a newly installed Linux **CentOS 7** VM run the following commands to install the required packages:

1- Install the git package

    $> sudo yum install -y git

6- Download the Ansible automation package

    $> git clone https://<your-bitbucket-username>@bitbucket-eng-rtp1.cisco.com/bitbucket/scm/cc/cmsp-auto-deploy.git

7- Go to the newly cloned cmsp-auto-deploy directory

    $> cd cmsp-auto-deploy

#### Configuration:

####*Note: If you choose to make changes to git tracked items such as folder names or file names or content of files downloaded from the repository, be aware that your changes will be lost everytime the automated installation package is updated*

1- Create your own environment directory structure under the _``inventories/<customer-name>``_ folder to contain the information defining the environment to deploy. Use the included _``<environment-name>_hosted``_ or _``<environment-name>_onprem``_ as templates

2- Use the included hosts file as a template and ensure the number of hosts of each type is correct. For example, the line ``em7db[01:02]`` in the hosts file represents a list of two hosts; ``em7db01`` and ``em7db02``

3- Update the file _``inventories/<customer-name>/group_vars/all.yml``_ with the values defining your environment. **Do not add or delete variables**

4- Host specific settings are to be added to a dedicated file under _``inventories/<customer-name>/host_vars``_ directory. The name of the variables file has to match the name of the host as defined in the hosts.yml file

#### Dependencies:

All packages listed in "how to get set up" section need to be installed on the machine before running the Automation script(s)

#### Deployment instructions:

1- From the automation root directory (containing site.yml playbook), run one of the bash scripts under the Bash folder depending on what you want to do. 

    $> sh Bash/<script name> --envname <customer-name>

with the script name being one of the following options:

- ``play_deploy.sh``

- ``play_rollback.sh``

####*Note: Running multiple instances of the same script for a given customer simultaneously is prohibited*

2- Script output is automatically saved to a log file. The file is saved under _``/var/tmp/ansible/<script-name>.<customer-name>.log.<time-stamp>``_ on the Ansible control machine

3- Answer the prompts on the CLI. If you simply hit enter, default values will be used unless an input is required. In such a case you will be prompted again to enter a value

4- The list of roles used in the playbooks:

  - **collect_info**: prompts the user for required information
  - **check_creds**: validates the user's credentials
  - **todo**: determines what roles and/or tasks to execute
  - **ssh_keys**: creates and deploys SSH keys to the bastion server(s) if applicable
  - **capcheck**: performs a capacity check of the infrastructure
  - **vm_facts**: defines the individual VM facts required in the playbook
  - **vm_creation**: deploys the stack's VMs
  - **vm_configuration**: configures the stack's VMs
  - **puppet**: installs the puppet agent, generates the puppet certificates and triggers the puppet push where applicable in the stack
  - **check_requiretty**: checks for and disables requiretty on the hosts
  - **notify**: sends a notification via Webex Teams channel indicating the status of the activity

To execute specific role(s), add "_--tags 'role1,role2,...'_" as argument to the script.

To skip specific role(s), add "_--skip-tags 'role1,role2,...'_" as argument to the script.

**_Example1_**: to install/uninstall docker and ntp, run the script as follows:

    $> sh Bash/<script-name> --envname <customer-name> --tags 'docker,ntp'

**_Example2_**: to run all roles except os and ntp, run the script as follows:

    $> sh Bash/<script-name> --envname <customer-name> --skip-tags 'os,ntp'

To limit the processing to specific host(s) or group(s) or a combination of both, add "_--limit 'group1,host1,...'_" as argument to the script.

**_Example3_**: to install/uninstall docker and ntp on the linux jump servers and on relay01, run the script as follows:

    $> sh Bash/<script-name> --envname <customer-name> --tags 'docker,ntp' --limit 'lnxjmp,rly01'

####*Note: group(s) or host(s) names specified with --limit must match the names defined in the hosts.yml file*


### Contribution guidelines ###

* Writing tests
* Code review
* Other guidelines

### Who do I talk to? ###

* Repo owner or admin
* Other community or team contact
* [Learn Markdown](https://bitbucket.org/tutorials/markdowndemo)
