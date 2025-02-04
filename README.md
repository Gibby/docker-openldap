# gibby/openldap

[![](https://badge.imagelayers.io/gibby/openldap:latest.svg)](https://imagelayers.io/?images=gibby/openldap:latest 'Get your own badge on imagelayers.io') | Latest release: 1 - OpenLDAP 2.4.40 -  [Changelog](CHANGELOG.md) | [Docker Hub](https://hub.docker.com/r/gibby/openldap/) 

A docker image to run OpenLDAP. Forked from [osixia/docker-openldap](https://github.com/osixia/docker-openldap/issues)

## Changes/Additions
This now includes [FusionDirectory](https://www.fusiondirectory.org/)

## How to use
To add FusionDirectory plugins or remove them, update the fusiondirectory.plugins or fusiondirectory.plugins.ignore file.

You will have to run this twice. This first run is required for setting up FusionDirectory.

###### First Run

    docker run \
    --volume /data/slapd/database:/var/lib/ldap \
    --volume /data/slapd/config:/etc/ldap/slapd.d \
    -p 80:80 \
    --it gibby/openldap bash

Once running open a web browser, go to http://localhost and go through the setup.
After you download the fusiondirectory.conf file. Put it in /etc/fusiondirectory directory and save it to a location for the 2nd run.
Verify you can login to the FusionDirectory site and then exit and stop the container.

###### Second Run
Same as before but now you will need to specify a mount for the fusiondirectory.conf to /etc/fusiondirectory and expose needed ports.

Something like below:

    docker run \
    --volume /data/slapd/database:/var/lib/ldap \
    --volume /data/slapd/config:/etc/ldap/slapd.d \
    --volume /data/fusiondirectory/config:/etc/fusiondirectory
    -p 80:80 \
    -p 389:389 \
    -d gibby/openldap 



# Everything below is from the forked README.md

> OpenLDAP website : [www.openldap.org](http://www.openldap.org/)

- [Contributing](#contributing)
- [Quick Start](#quick-start)
- [Beginner Guide](#beginner-guide)
	- [Create new ldap server](#create-new-ldap-server)
		- [Data persistence](#data-persistence)
		- [Edit your server configuration](#)
	- [Use an existing ldap database](#use-an-existing-ldap-database)
	- [Backup](#backup)
	- [Administrate your ldap server](#administrate-your-ldap-server)
	- [TLS](#tls)
		- [Use auto-generated certificate](#use-auto-generated-certificate)
		- [Use your own certificate](#use-your-own-certificate)
		- [Disable TLS](#disable-tls)
	- [Multi master replication](#multi-master-replication)
	- [Debug](#debug)
- [Environment Variables](#environment-variables)
	- [Default.yaml](#defaultyaml)
	- [Default.yaml.startup](#defaultyamlstartup)
	- [Set your own environment variables](#set-your-own-environment-variables)
		- [Use command line argument](#use-command-line-argument)
		- [Link environment file](#link-environment-file)
		- [Make your own image or extend this image](#make-your-own-image-or-extend-this-image)
- [Advanced User Guide](#advanced-user-guide)
	- [Extend osixia/openldap:1.1.0 image](#extend-osixiaopenldap110-image)
	- [Make your own openldap image](#make-your-own-openldap-image)
	- [Tests](#tests)
	- [Kubernetes](#kubernetes)
	- [Under the hood: osixia/light-baseimage](#under-the-hood-osixialight-baseimage)
- [Changelog](#changelog)

## Contributing

If you find this image useful here's how you can help:

- Send a pull request with your kickass new features and bug fixes
- Help new users with [issues](https://github.com/osixia/docker-openldap/issues) they may encounter
- Support the development of this image and star this repo !

## Quick Start
Run OpenLDAP docker image:

	docker run --name my-openldap-container --detach osixia/openldap:1.1.0

This start a new container with OpenLDAP running inside. Let's make the first search in our LDAP container:

	docker exec my-openldap-container ldapsearch -x -h localhost -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w admin

This should output:

	# extended LDIF
	#
	# LDAPv3
	# base <dc=example,dc=org> with scope subtree
	# filter: (objectclass=*)
	# requesting: ALL
	#

	[...]

	# numResponses: 3
	# numEntries: 2

If you have the following error, OpenLDAP is not started yet, maybe you are too fast or maybe your computer is to slow, as you want... but wait some time before retrying.

		ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)


## Beginner Guide

### Create new ldap server

This is the default behavior when you run this image.
It will create an empty ldap for the company **Example Inc.** and the domain **example.org**.

By default the admin has the password **admin**. All those default settings can be changed at the docker command line, for example:

	docker run --env LDAP_ORGANISATION="My Company" --env LDAP_DOMAIN="my-company.com" \
	--env LDAP_ADMIN_PASSWORD="JonSn0w" --detach osixia/openldap:1.1.0

#### Data persistence

The directories `/var/lib/ldap` (LDAP database files) and `/etc/ldap/slapd.d`  (LDAP config files) has been declared as volumes, so your ldap files are saved outside the container in data volumes.

For more information about docker data volume, please refer to:

> [https://docs.docker.com/userguide/dockervolumes/](https://docs.docker.com/userguide/dockervolumes/)


#### Edit your server configuration

Do not edit slapd.conf it's not used. To modify your server configuration use ldap utils: **ldapmodify / ldapadd / ldapdelete**

### Use an existing ldap database

This can be achieved by mounting host directories as volume.
Assuming you have a LDAP database on your docker host in the directory `/data/slapd/database`
and the corresponding LDAP config files on your docker host in the directory `/data/slapd/config`
simply mount this directories as a volume to `/var/lib/ldap` and `/etc/ldap/slapd.d`:

	docker run --volume /data/slapd/database:/var/lib/ldap \
	--volume /data/slapd/config:/etc/ldap/slapd.d
	--detach osixia/openldap:1.1.0

You can also use data volume containers. Please refer to:
> [https://docs.docker.com/userguide/dockervolumes/](https://docs.docker.com/userguide/dockervolumes/)

### Backup
A simple solution to backup your ldap server, is our openldap-backup docker image:
> [osixia/openldap-backup](https://github.com/osixia/docker-openldap-backup)

### Administrate your ldap server
If you are looking for a simple solution to administrate your ldap server you can take a look at our phpLDAPadmin docker image:
> [osixia/phpldapadmin](https://github.com/osixia/docker-phpLDAPadmin)

### TLS

#### Use auto-generated certificate
By default TLS is enable, a certificate is created with the container hostname (it can be set by docker run --hostname option eg: ldap.example.org).

	docker run --hostname ldap.my-company.com --detach osixia/openldap:1.1.0

#### Use your own certificate

You can set your custom certificate at run time, by mounting a directory containing those files to **/container/service/slapd/assets/certs** and adjust their name with the following environment variables:

	docker run --hostname ldap.example.org --volume /path/to/certifates:/container/service/slapd/assets/certs \
	--env LDAP_TLS_CRT_FILENAME=my-ldap.crt \
	--env LDAP_TLS_KEY_FILENAME=my-ldap.key \
	--env LDAP_TLS_CA_CRT_FILENAME=the-ca.crt \
	--detach osixia/openldap:1.1.0

Other solutions are available please refer to the [Advanced User Guide](#advanced-user-guide)

#### Disable TLS
Add --env LDAP_TLS=false to the run command:

	docker run --env LDAP_TLS=false --detach osixia/openldap:1.1.0

### Multi master replication
Quick example, with the default config.

	#Create the first ldap server, save the container id in LDAP_CID and get its IP:
	LDAP_CID=$(docker run --hostname ldap.example.org --env LDAP_REPLICATION=true --detach osixia/openldap:1.1.0)
	LDAP_IP=$(docker inspect -f "{{ .NetworkSettings.IPAddress }}" $LDAP_CID)

	#Create the second ldap server, save the container id in LDAP2_CID and get its IP:
	LDAP2_CID=$(docker run --hostname ldap2.example.org --env LDAP_REPLICATION=true --detach osixia/openldap:1.1.0)
	LDAP2_IP=$(docker inspect -f "{{ .NetworkSettings.IPAddress }}" $LDAP2_CID)

	#Add the pair "ip hostname" to /etc/hosts on each containers,
	#beacause ldap.example.org and ldap2.example.org are fake hostnames
	docker exec $LDAP_CID bash -c "echo $LDAP2_IP ldap2.example.org >> /etc/hosts"
	docker exec $LDAP2_CID bash -c "echo $LDAP_IP ldap.example.org >> /etc/hosts"

That's it! But a little test to be sure:

Add a new user "billy" on the first ldap server

	docker exec $LDAP_CID ldapadd -x -D "cn=admin,dc=example,dc=org" -w admin -f /container/service/slapd/assets/test/new-user.ldif --hostname ldap.example.org -ZZ

Search on the second ldap server, and billy should show up!

	docker exec $LDAP2_CID ldapsearch -x -h ldap2.example.org -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w admin -ZZ

	[...]

	# billy, example.org
	dn: uid=billy,dc=example,dc=org
	uid: billy
	cn: billy
	sn: 3
	objectClass: top
	objectClass: posixAccount
	objectClass: inetOrgPerson
	[...]

### Debug

The container default log level is **info**.
Available levels are: `none`, `error`, `warning`, `info`, `debug` and `trace`.

Example command to run the container in `debug` mode:

	docker run --detach osixia/openldap:1.1.0 --loglevel debug

See all command line options:

	docker run osixia/openldap:1.1.0 --help


## Environment Variables
Environment variables defaults are set in **image/environment/default.yaml** and **image/environment/default.yaml.startup**.

See how to [set your own environment variables](#set-your-own-environment-variables)

### Default.yaml
Variables defined in this file are available at anytime in the container environment.

General container configuration:
- **LDAP_LOG_LEVEL**: Slap log level. defaults to  `256`. See table 5.1 in http://www.openldap.org/doc/admin24/slapdconf2.html for the available log levels.

### Default.yaml.startup
Variables defined in this file are only available during the container **first start** in **startup files**.
This file is deleted right after startup files are processed for the first time,
then all of these values will not be available in the container environment.

This helps to keep your container configuration secret. If you don't care all environment variables can be defined in **default.yaml** and everything will work fine.

Required and used for new ldap server only:
- **LDAP_ORGANISATION**: Organisation name. Defaults to `Example Inc.`
- **LDAP_DOMAIN**: Ldap domain. Defaults to `example.org`
- **LDAP_ADMIN_PASSWORD** Ldap Admin password. Defaults to `admin`
- **LDAP_CONFIG_PASSWORD** Ldap Config password. Defaults to `config`

- **LDAP_READONLY_USER** Add a read only user. Defaults to `false`
- **LDAP_READONLY_USER_USERNAME** Read only user username. Defaults to `readonly`
- **LDAP_READONLY_USER_PASSWORD** Read only user password. Defaults to `readonly`

TLS options:
- **LDAP_TLS**: Add openldap TLS capabilities. Defaults to `true`
- **LDAP_TLS_CRT_FILENAME**: Ldap ssl certificate filename. Defaults to `ldap.crt`
- **LDAP_TLS_KEY_FILENAME**: Ldap ssl certificate private key filename. Defaults to `ldap.key`
- **LDAP_TLS_CA_CRT_FILENAME**: Ldap ssl CA certificate  filename. Defaults to `ca.crt`
- **LDAP_TLS_ENFORCE**: Enforce TLS. Defaults to `false`
- **LDAP_TLS_CIPHER_SUITE**: TLS cipher suite. Defaults to `SECURE256:-VERS-SSL3.0`
- **LDAP_TLS_PROTOCOL_MIN**: TLS min protocol. Defaults to `3.1`
- **LDAP_TLS_VERIFY_CLIENT**: TLS verify client. Defaults to `demand`

	Help: http://www.openldap.org/doc/admin24/tls.html

Replication options:
- **LDAP_REPLICATION**: Add openldap replication capabilities. Defaults to `false`

- **LDAP_REPLICATION_CONFIG_SYNCPROV**: olcSyncRepl options used for the config database. Without **rid** and **provider** which are automatically added based on LDAP_REPLICATION_HOSTS.  Defaults to `binddn="cn=admin,cn=config" bindmethod=simple credentials=$LDAP_CONFIG_PASSWORD searchbase="cn=config" type=refreshAndPersist retry="60 +" timeout=1 starttls=critical`

- **LDAP_REPLICATION_HDB_SYNCPROV**: olcSyncRepl options used for the HDB database. Without **rid** and **provider** which are automatically added based on LDAP_REPLICATION_HOSTS.  Defaults to `binddn="cn=admin,$LDAP_BASE_DN" bindmethod=simple credentials=$LDAP_ADMIN_PASSWORD searchbase="$LDAP_BASE_DN" type=refreshAndPersist interval=00:00:00:10 retry="60 +" timeout=1 starttls=critical`

- **LDAP_REPLICATION_HOSTS**: list of replication hosts, must contain the current container hostname set by --hostname on docker run command. Defaults to :
	```yaml
	- ldap://ldap.example.org
  - ldap://ldap2.example.org
	```

	If you want to set this variable at docker run command add the tag `#PYTHON2BASH:` and convert the yaml in python:

		docker run --env LDAP_REPLICATION_HOSTS="#PYTHON2BASH:['ldap://ldap.example.org','ldap://ldap2.example.org']" --detach osixia/openldap:1.1.0

	To convert yaml to python online: http://yaml-online-parser.appspot.com/

Other environment variables:
- **LDAP_REMOVE_CONFIG_AFTER_SETUP**: delete config folder after setup. Defaults to `true`
- **LDAP_CFSSL_PREFIX**: cfssl environment variables prefix. Defaults to `ldap`, cfssl-helper first search config from LDAP_CFSSL_* variables, before CFSSL_* variables.


### Set your own environment variables

#### Use command line argument
Environment variables can be set by adding the --env argument in the command line, for example:

	docker run --env LDAP_ORGANISATION="My company" --env LDAP_DOMAIN="my-company.com" \
	--env LDAP_ADMIN_PASSWORD="JonSn0w" --detach osixia/openldap:1.1.0

Be aware that environment variable added in command line will be available at any time
in the container. In this example if someone manage to open a terminal in this container
he will be able to read the admin password in clear text from environment variables.

#### Link environment file

For example if your environment files **my-env.yaml** and **my-env.yaml.startup** are in /data/ldap/environment

	docker run --volume /data/ldap/environment:/container/environment/01-custom \
	--detach osixia/openldap:1.1.0

Take care to link your environment files folder to `/container/environment/XX-somedir` (with XX < 99 so they will be processed before default environment files) and not  directly to `/container/environment` because this directory contains predefined baseimage environment files to fix container environment (INITRD, LANG, LANGUAGE and LC_CTYPE).

Note: the container will try to delete the **\*.yaml.startup** file after the end of startup files so the file will also be deleted on the docker host. To prevent that : use --volume /data/ldap/environment:/container/environment/01-custom**:ro** or set all variables in **\*.yaml** file and don't use **\*.yaml.startup**:

	docker run --volume /data/ldap/environment/my-env.yaml:/container/environment/01-custom/env.yaml \
	--detach osixia/openldap:1.1.0

#### Make your own image or extend this image

This is the best solution if you have a private registry. Please refer to the [Advanced User Guide](#advanced-user-guide) just below.

## Advanced User Guide

### Extend osixia/openldap:1.1.0 image

If you need to add your custom TLS certificate, bootstrap config or environment files the easiest way is to extends this image.

Dockerfile example:

	FROM osixia/openldap:1.1.0
	MAINTAINER Your Name <your@name.com>

	ADD bootstrap /container/service/slapd/assets/config/bootstrap
	ADD certs /container/service/slapd/assets/certs
	ADD environment /container/environment/01-custom

See complete example in **example/extend-osixia-openldap**

### Make your own openldap image

Clone this project:

	git clone https://github.com/osixia/docker-openldap
	cd docker-openldap

Adapt Makefile, set your image NAME and VERSION, for example:

	NAME = osixia/openldap
	VERSION = 1.1.0

	become:
	NAME = cool-guy/openldap
	VERSION = 0.1.0

Add your custom certificate, bootstrap ldif and environment files...

Build your image:

	make build

Run your image:

	docker run --detach cool-guy/openldap:0.1.0

### Tests

We use **Bats** (Bash Automated Testing System) to test this image:

> [https://github.com/sstephenson/bats](https://github.com/sstephenson/bats)

Install Bats, and in this project directory run:

	make test

### Kubernetes

Kubernetes is an open source system for managing containerized applications across multiple hosts, providing basic mechanisms for deployment, maintenance, and scaling of applications.

More information:
- http://kubernetes.io
- https://github.com/kubernetes/kubernetes

osixia-openldap kubernetes examples are available in **example/kubernetes**

### Under the hood: osixia/light-baseimage

This image is based on osixia/light-baseimage.
It uses the following features:

- **cfssl** service to generate tls certificates
- **log-helper** tool to print log messages based on the log level
- **run** tool as entrypoint to init the container environment

To fully understand how this image works take a look at:
https://github.com/osixia/docker-light-baseimage

## Changelog

Please refer to: [CHANGELOG.md](CHANGELOG.md)
