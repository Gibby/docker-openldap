#!/bin/bash -e
set -o pipefail

# set -x (bash debug) if log level is trace
# https://github.com/osixia/docker-light-baseimage/blob/stable/image/tool/log-helper
log-helper level eq trace && set -x

ln -sf ${CONTAINER_SERVICE_DIR}/apache2/assets/sites-available/* /etc/apache2/sites-available/
a2dissite 000-default | log-helper debug
a2disconf fusiondirectory | log-helper debug
a2ensite fusiondirectory | log-helper debug


exit 0
