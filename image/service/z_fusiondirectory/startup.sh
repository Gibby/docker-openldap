#!/bin/bash -e
set -o pipefail

# set -x (bash debug) if log level is trace
# https://github.com/osixia/docker-light-baseimage/blob/stable/image/tool/log-helper
log-helper level eq trace && set -x

if [ ! -f /usr/share/doc/fusiondirectory/fusiondirectory.conf ]; then
    wget -O /usr/share/doc/fusiondirectory/fusiondirectory.conf https://raw.githubusercontent.com/fusiondirectory/fusiondirectory/master/contrib/fusiondirectory.conf
fi

# Fix permissions
if [ -f /etc/fusiondirectory/fusiondirectory.conf ]; then
    echo "Yes" | fusiondirectory-setup --check-config
    echo "Yes" | fusiondirectory-setup --check-config
fi

exit 0
