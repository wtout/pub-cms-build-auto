# README #

This README provides instructions and information to get your Ansible control machine up and running with the automation package to deploy the CMS stack.

### Disclaimer ###

The deployment procedure has to be the same for all deployments. Ansible code contained in this repository is to automate the standard deployment procedure. Customization for a given customer is limited to the environment variables used during installation. Do not modify the Ansible code on the fly during a customer installation. Ansible code is NOT meant to be touched/edited except in the context of standard deployment procedure automation development. The usage information below gives the user the needed information to set up and execute the supported automated procedures.

### What is this repository for? ###

This repository contains Ansible scripts to be used in the full deployment of the CMS stack. The automation tool expects the CMS software package(s) to be placed in the _``Packages``_ folder in its downloaded format.

### How do I get set up? ###

On a newly installed Linux **CentOS 7** VM run the following commands to install the required packages:

1- Install the git package

    $> sudo yum install -y git

6- Download the Ansible automation package

    $> git clone https://<your-bitbucket-username>@bitbucket-eng-rtp1.cisco.com/bitbucket/scm/cc/cmsp-auto-deploy.git

7- Go to the newly cloned cmsp-auto-deploy directory

    $> cd cmsp-auto-deploy

#### Configuration:

1- Create your own hosts file under the _``inventories/<customer-name>``_ folder to contain the information of your remote host(s). Use the included hosts file as a template. **If you choose to update the included _hosts_ file, be aware that your changes will be lost everytime the automated installation package is updated**

2- Add the admin account username for each remote node or a group of nodes (see hosts file for proper syntax)

3- If Ansible is already installed, you can test connectivity to your host(s) with the following Ansible adhoc command. If host's ssh password is not defined in the hosts file, append the argument "_--ask-pass_" to the ansible command (Requires Ansible to be installed)

    $> ansible <host-or-host-group-name> -m ping [--ask-pass]

4- Environment/system specific settings are to be added to a dedicated file under _``inventories/<customer-name>/group_vars``_ directory. The name of the variables file has to match the name of the the group of hosts

5- Host specific settings are to be added to a dedicated file under _``inventories/<customer-name>/host_vars``_ directory. The name of the variables file has to match the name of the host

#### Dependencies:

All packages listed in "how to get set up" section need to be installed on the machine before running the Automation script(s)

#### Deployment instructions:

1- Place the CMS packages in the _``Packages``_ folder

2- From the automation root directory (containing site.yml playbook), run one of the bash scripts under the Bash folder depending on what you want to do. 

    $> sh Bash/<script name> --envname <customer-name>

with the script name being one of the following options:

- ``play.sh``

####*Note: Running multiple instances of the same script for a given customer simultaneously is prohibited*

3- Script output is automatically saved to a log file. The file is saved under _``/var/tmp/<script-name>.<customer-name>.log.<time-stamp>``_ on the Ansible control machine

4- Answer the prompts on the CLI. If you simply hit enter, default values will be used unless an input is required. In such a case you will be prompted again to enter a value

5- The list of roles used in the playbook:

  - **notify**: sends a notification via Webex Teams channel indicating the status of the activity

To execute specific role(s), add "_--tags 'role1,role2,...'_" as argument to the script.

To skip specific role(s), add "_--skip-tags 'role1,role2,...'_" as argument to the script.

**_Example1_**: to install/uninstall docker and ntp, run the script as follows:

    $> sh Bash/<script-name> --envname <customer-name> --tags 'docker,ntp'

**_Example2_**: to run all roles except os and ntp, run the script as follows:

    $> sh Bash/<script-name> --envname <customer-name> --skip-tags 'os,ntp'

To limit the execution of the playbook to one host or a group of hosts, add "_``--limit '<string>'``_" as argument to the script. If omitted, the playbook will be executed on all the hosts defined in the hosts file. The _``'<string>'``_ can be:

  - **host name**: 'host1.domain' or 'host1*'
  - **list of host names separated by comma**: 'host1.domain,host2.domain' or '\*host1\*,\*host2\*'
  - **group name**: 'group1'
  - **list of group names**: 'group1,group2'


### Contribution guidelines ###

* Writing tests
* Code review
* Other guidelines

### Who do I talk to? ###

* Repo owner or admin
* Other community or team contact
* [Learn Markdown](https://bitbucket.org/tutorials/markdowndemo)
