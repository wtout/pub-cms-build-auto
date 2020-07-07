# README #

This README provides instructions and information to get your Ansible control machine up and running with the automation package to deploy the CMS stack.


### What is this repository for? ###

This repository contains Ansible playbooks to be used in the full deployment of the CMS stack.


### Disclaimer ###

The deployment procedure has to be the same for all deployments. Ansible code contained in this repository is to automate the standard deployment procedure. Customization for a given customer is limited to the environment variables used during installation. Do not modify the Ansible code on the fly during a customer installation. Ansible code is NOT meant to be touched/edited except in the context of standard deployment procedure automation development. The usage information below gives the user the needed information to set up and execute the supported automated procedures.


### Installation ###

On a newly installed Linux **CentOS 7** VM that can access the internet, bitbucket and the VM infrastructure, run the following commands to install the required packages:

1- Install the git package

    $> sudo yum install -y git

2- Download the Ansible automation package

    $> git clone --single-branch --branch master https://<your-repo-username>@www-github3.cisco.com/cms-build-team/cmsp-auto-deploy.git

3- Go to the newly cloned cmsp-auto-deploy directory

    $> cd cmsp-auto-deploy

***Note**: you might need to disable the proxy to be able to download the package*


### System definition ###

Create your own system definition file under the _``Definitions``_ folder to contain the information defining the stack to deploy. Use the included _``cust_build_info.yml``_ file as template

***Note**: If you choose to make changes to git tracked items such as folder names or file names or content of files downloaded from the repository, be aware that your changes will be lost every time the automated installation package is updated*

The system definition file name **must match the customer name** as defined in the system definition file. The system definition file consists of the following variables:

  - **name** (_String_): Customer Name. Required
  - **release_version** (_String_): Required. Must start with **R** to match the naming convention in Maven
  - **deployment_model** (_String_): Required. Valid values are: **a** and **h**, where **a** represents “**a**ppliance” and **h** represents “**h**osted”
  - **disaster_recovery** (_Boolean_ **yes**/**no**): Required. Default value “**no**”
  - **number_of_prts** (_String_): Required. Number of EM7 portals in primary stack. Valid values are even numbers in [2-4]
  - **number_of_mcs** (_String_): Required. Number of EM7 message collectors in primary stack. Valid values are even numbers in [2-6]
  - **number_of_dcs** (_String_): Required. Number of EM7 data collectors in primary stack. Valid values are even numbers in [2-12]
  - **name_prefix** (_String_): Required. Name prefix for primary stack
  - **octets** (_String_): Required. First three octets for primary stack
  - **name_prefix** (_String_): Required when disaster_recovery is “yes”. Name prefix for secondary stack
  - **octets** (_String_): Required when disaster_recovery is “yes”. First three octets for secondary stack
  - **name** (_String_): Required. Datacenter name
  - **resources** (_String_): Required for on-prem deployments. List of ESXI hosts
  - **server_name** (_String_): Required. Valid values for Puppet server name are: **alln1qspupp01**, **alln1qspupp02**, **alln1qspupp03** and **alln1qspupp04**
  - **server_name** (_String_): Required. Valid values for Yum server name are: **alln1qsyumrpp01** and **alln1qsyumrpp02**

Non-standard host specific settings are to be added to a dedicated file under _``inventories/<system-name>/host_vars``_ directory. The name of the variables file must match the name of the host as defined in the hosts.yml file. This can only be done after the system inventory has been created.

To create the system inventory without deploying the system, issue the following command from the automation root directory (cmsp-auto-deploy):

    $> sh Bash/play_deploy.sh –-envname <system-name> --tags none


### Artifacts ###

The tool automatically downloads and checks the CMSP software package(s) to the _``Packages``_ folder on the Ansible machine or on the bastion server, if applicable. The _``Packages``_ folder will be created under /data if it exists and a symbolic link to it will be created in the automation directory. If it does not exist, the _``Packages``_ folder will be created under the automation directory. To minimize deployment run time, consider downloading the artifacts prior to starting the deployment process. However, because the artifacts repository is currently disorganized, it is highly recommended to ensure they are manually transferred to the Ansible control machine under _``Packages/<release_version>``_.

If the automated procedure is preferred, the user must ensure that the correct and complete package is available at the location the Ansible code expects it to be, _``http://engci-maven-master.cisco.com/artifactory/cms-quicksilver-release/<release_version>/Puppet/``_

To download the artifacts without deploying the system, issue the following command from the automation root directory (cmsp-auto-deploy):

    $> sh Bash/play_deploy.sh –-envname <system-name> --tags get_release


### System Deployment ###

1- From the automation root directory (cmsp-auto-deploy), run one of the bash scripts under the Bash folder depending on what you want to do. 

    $> sh Bash/<script name> --envname <system-name>

with the system-name being the name of the system definition file from "Configuration" step 1 and the script name being one of the following options:

- ``play_deploy.sh``

- ``play_rollback.sh``

  Script output is automatically saved to a log file. The file is saved under _``/var/tmp/ansible/<script-name>.<system-name>.log.<time-stamp>``_ on the Ansible control machine

***Note**: Running multiple instances of the same script for a given customer simultaneously is prohibited*

2- Answer the prompts on the CLI. If you simply hit enter, default values will be used unless an input is required. In such a case you will be prompted again to enter a value


### Tips and tricks ###

The list of roles used in the playbooks:

  - **pypkgs**: installs the required Python3 packages
  - **define_inventory**: generates the system inventory from the system definition file
  - **collect_info**: prompts the user for required information
  - **check_creds**: validates the user's credentials
  - **todo**: determines what roles and/or tasks to execute
  - **ssh_keys**: creates and deploys SSH keys to the bastion server(s) if applicable
  - **capcheck**: performs a capacity check of the infrastructure
  - **get_release**: downloads the release package from the repository
  - **vm_facts**: defines the individual VM facts required in the playbook
  - **vm_creation**: deploys the stack's VMs from OVA
  - **vm_fromiso**: deploys the stack's VMs from ISO
  - **vm_configuration**: configures the stack's VMs
  - **puppet**: installs the puppet agent, generates the puppet certificates and triggers the puppet push where applicable in the stack
  - **vm_ppp_configuration**: configures the stack's VMs post initial puppet push
  - **splunk_mop**: implements the datetime fix for splunk VMs
  - **notify**: sends a notification via Webex Teams channel indicating the status of the activity

To execute specific role(s), add "_--tags 'role1,role2,...'_" as argument to the script.

To skip specific role(s), add "_--skip-tags 'role1,role2,...'_" as argument to the script.

**_Example1_**: to install/uninstall docker and ntp, run the script as follows:

    $> sh Bash/<script-name> --envname <system-name> --tags 'docker,ntp'

**_Example2_**: to run all roles except os and ntp, run the script as follows:

    $> sh Bash/<script-name> --envname <system-name> --skip-tags 'os,ntp'

To limit the processing to specific host(s) or group(s) or a combination of both, add "_--limit 'group1,host1,...'_" as argument to the script.

**_Example3_**: to install/uninstall docker and ntp on the linux jump servers and on relay01, run the script as follows:

    $> sh Bash/<script-name> --envname <system-name> --tags 'docker,ntp' --limit 'lnxjmp,rly01'

***Note**: group(s) or host(s) names specified with --limit must match the names defined in the hosts.yml file*


### User Guide ###

For more details about the usage of this automation package, consult the user guide at https://confluence-eng-rtp1.cisco.com/conf/display/CMSPAE/Automation?preview=/96831609/109969695/CMSPAutomationUserGuide.pdf


### Who do I talk to? ###

* Repo owner or admin
* Other community or team contact
* [Learn Markdown](https://bitbucket.org/tutorials/markdowndemo)
