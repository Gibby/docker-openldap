#!/bin/bash -e
#set -o pipefail

# set -x (bash debug) if log level is trace
# https://github.com/osixia/docker-light-baseimage/blob/stable/image/tool/log-helper
log-helper level eq trace && set -x

# function to check for a running process
function check_for_running() {

echo "Running if $1 is running..."
ps -ef | grep $1 | grep -v grep | grep -v runsv > /dev/null 2>&1

}

# function to initialize any fusiondirectory plugins
function init_fusiondirectory_plugins() {

for file in `ls /etc/ldap/schema/fusiondirectory/`
do
    fusiondirectory-insert-schema -c -i /etc/ldap/schema/fusiondirectory/${file}
done

touch /.fusiondirectory-insert-schema.done

}

function check_fusiondirectory_plugins() {

if [ ! -f /.fusiondirectory-insert-schema.done ]; then

    # wait until slapd is running the update schema for plugins
    while ! check_for_running slapd; do
        echo "Waiting for slapd to be running..."
        sleep 5
    done

    sleep 5
    init_fusiondirectory_plugins
    echo "Done loading fusiondirectory plugins"
    echo "If you want to reload them again just remove the following file and they will be loaded in about 10 seconds."
    echo "/.fusiondirectory-insert-schema.done"
fi

}


while :
do
    check_fusiondirectory_plugins
    sleep 10
done
