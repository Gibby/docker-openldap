#!/bin/bash -e
set -o pipefail

# set -x (bash debug) if log level is trace
# https://github.com/osixia/docker-light-baseimage/blob/stable/image/tool/log-helper
log-helper level eq trace && set -x

# Reduce maximum number of number of open file descriptors to 1024
# otherwise slapd consumes two orders of magnitude more of RAM
# see https://github.com/docker/docker/issues/8231
ulimit -n 1024

# fix file permissions
chown -R openldap:openldap /var/lib/ldap
chown -R openldap:openldap /etc/ldap
chown -R openldap:openldap ${CONTAINER_SERVICE_DIR}/slapd

FIRST_START_DONE="${CONTAINER_STATE_DIR}/slapd-first-start-done"
WAS_STARTED_WITH_TLS="/etc/ldap/slapd.d/docker-openldap-was-started-with-tls"
WAS_STARTED_WITH_REPLICATION="/etc/ldap/slapd.d/docker-openldap-was-started-with-replication"

# CONTAINER_SERVICE_DIR and CONTAINER_STATE_DIR variables are set by
# the baseimage run tool more info : https://github.com/osixia/docker-light-baseimage

# container first start
if [ ! -e "$FIRST_START_DONE" ]; then

  #
  # Helpers
  #
  function get_ldap_base_dn() {
    LDAP_BASE_DN=""
    IFS='.' read -ra LDAP_BASE_DN_TABLE <<< "$LDAP_DOMAIN"
    for i in "${LDAP_BASE_DN_TABLE[@]}"; do
      EXT="dc=$i,"
      LDAP_BASE_DN=$LDAP_BASE_DN$EXT
    done

    LDAP_BASE_DN=${LDAP_BASE_DN::-1}
  }

  function is_new_schema() {
    local COUNT=$(ldapsearch -Q -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config cn | grep -c $1)
    if [ "$COUNT" -eq 0 ]; then
      echo 1
    else
      echo 0
    fi
  }

  function check_tls_files() {

    local CA_CRT=$1
    local LDAP_CRT=$2
    local LDAP_KEY=$3
    local DH_PARAM=$4

    # generate a certificate and key with cfssl tool if LDAP_CRT and LDAP_KEY files don't exists
    # https://github.com/osixia/docker-light-baseimage/blob/stable/image/service-available/:cfssl/assets/tool/cfssl-helper
    cfssl-helper $LDAP_CFSSL_PREFIX $LDAP_CRT $LDAP_KEY $CA_CRT

    # create DHParamFile if not found
    [ -f ${DH_PARAM} ] || openssl dhparam -out ${DH_PARAM} 2048
    chmod 600 ${DH_PARAM}

    # fix file permissions
    chown -R openldap:openldap ${CONTAINER_SERVICE_DIR}/slapd
  }

  #
  # Global variables
  #
  BOOTSTRAP=false

  #
  # database and config directory are empty
  # setup bootstrap config - Part 1
  #
  if [ -z "$(ls -A /var/lib/ldap)" ] && [ -z "$(ls -A /etc/ldap/slapd.d)" ]; then

    BOOTSTRAP=true
    log-helper info "Database and config directory are empty..."
    log-helper info "Init new ldap server..."

    cat <<EOF | debconf-set-selections
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORGANISATION}
slapd slapd/backend string HDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
slapd slapd/dump_database select when needed
EOF

    dpkg-reconfigure -f noninteractive slapd

  #
  # Error: the database directory (/var/lib/ldap) is empty but not the config directory (/etc/ldap/slapd.d)
  #
  elif [ -z "$(ls -A /var/lib/ldap)" ] && [ ! -z "$(ls -A /etc/ldap/slapd.d)" ]; then
    log-helper error "Error: the database directory (/var/lib/ldap) is empty but not the config directory (/etc/ldap/slapd.d)"
    exit 1

  #
  # Error: the config directory (/etc/ldap/slapd.d) is empty but not the database directory (/var/lib/ldap)
  #
  elif [ ! -z "$(ls -A /var/lib/ldap)" ] && [ -z "$(ls -A /etc/ldap/slapd.d)" ]; then
    log-helper error "Error: the config directory (/etc/ldap/slapd.d) is empty but not the database directory (/var/lib/ldap)"
    exit 1

  #
  # An existing database and config are provided
  #
  else
    # if the config was bootstraped with TLS
    # to avoid error (#6) we check tls files
    if [ -e "$WAS_STARTED_WITH_TLS" ]; then
      source $WAS_STARTED_WITH_TLS
      check_tls_files $PREVIOUS_LDAP_TLS_CA_CRT_PATH $PREVIOUS_LDAP_TLS_CRT_PATH $PREVIOUS_LDAP_TLS_KEY_PATH $PREVIOUS_LDAP_TLS_DH_PARAM_PATH
    fi
  fi

  #
  # start OpenLDAP
  #

  # get previous hostname if OpenLDAP was started with replication
  # to avoid configuration pbs
  PREVIOUS_HOSTNAME_PARAM=""
  if [ -e "$WAS_STARTED_WITH_REPLICATION" ]; then

    source $WAS_STARTED_WITH_REPLICATION

    # if previous hostname != current hostname
    # set previous hostname to a loopback ip in /etc/hosts
    if [ "$PREVIOUS_HOSTNAME" != "$HOSTNAME" ]; then
      echo "127.0.0.2 $PREVIOUS_HOSTNAME" >> /etc/hosts
      PREVIOUS_HOSTNAME_PARAM="ldap://$PREVIOUS_HOSTNAME"
    fi
  fi

  # start OpenLDAP
  log-helper info "Start OpenLDAP..."
  slapd -h "ldap://$HOSTNAME $PREVIOUS_HOSTNAME_PARAM ldap://localhost ldapi:///" -u openldap -g openldap


  #
  # setup bootstrap config - Part 2
  #
  if $BOOTSTRAP; then

    log-helper info "Add bootstrap schemas..."

    # add ppolicy schema
    ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f /etc/ldap/schema/ppolicy.ldif 2>&1 | log-helper debug

    # convert schemas to ldif
    SCHEMAS=""
    for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema -name \*.schema -type f); do
      SCHEMAS="$SCHEMAS ${f}"
    done
    ${CONTAINER_SERVICE_DIR}/slapd/assets/schema-to-ldif.sh "$SCHEMAS"

    # add converted schemas
    for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/schema -name \*.ldif -type f); do
      log-helper debug "Processing file ${f}"
      # add schema if not already exists
      SCHEMA=$(basename "${f}" .ldif)
      ADD_SCHEMA=$(is_new_schema $SCHEMA)
      if [ "$ADD_SCHEMA" -eq 1 ]; then
        ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f $f 2>&1 | log-helper debug
      else
        log-helper info "schema ${f} already exists"
      fi
    done

    # set config password
    LDAP_CONFIG_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_CONFIG_PASSWORD)
    sed -i "s|{{ LDAP_CONFIG_PASSWORD_ENCRYPTED }}|${LDAP_CONFIG_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/01-config-password.ldif

    # adapt security config file
    get_ldap_base_dn
    sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/02-security.ldif

    # process config files (*.ldif) in bootstrap directory (do no process files in subdirectories)
    log-helper info "Add bootstrap ldif..."
    for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif -mindepth 1 -maxdepth 1 -type f -name \*.ldif  | sort); do
      log-helper debug "Processing file ${f}"
      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $f 2>&1 | log-helper debug || ldapmodify -h localhost -p 389 -D cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD -f $f 2>&1 | log-helper debug
    done

    # read only user
    if [ "${LDAP_READONLY_USER,,}" == "true" ]; then

      log-helper info "Add read only user..."

      LDAP_READONLY_USER_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_READONLY_USER_PASSWORD)
      sed -i "s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user.ldif
      sed -i "s|{{ LDAP_READONLY_USER_PASSWORD_ENCRYPTED }}|${LDAP_READONLY_USER_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user.ldif
      sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user.ldif

      sed -i "s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user-acl.ldif
      sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user-acl.ldif

      log-helper debug "Processing file ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user.ldif"
      ldapmodify -h localhost -p 389 -D cn=admin,$LDAP_BASE_DN -w $LDAP_ADMIN_PASSWORD -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user.ldif 2>&1 | log-helper debug

      log-helper debug "Processing file ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user-acl.ldif"
      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/bootstrap/ldif/readonly-user/readonly-user-acl.ldif 2>&1 | log-helper debug

    fi
  fi

  #
  # TLS config
  #
  if [ "${LDAP_TLS,,}" == "true" ]; then

    log-helper info "Add TLS config..."

    LDAP_TLS_CA_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_CA_CRT_FILENAME"
    LDAP_TLS_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_CRT_FILENAME"
    LDAP_TLS_KEY_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/$LDAP_TLS_KEY_FILENAME"
    LDAP_TLS_DH_PARAM_PATH="${CONTAINER_SERVICE_DIR}/slapd/assets/certs/dhparam.pem"

    check_tls_files $LDAP_TLS_CA_CRT_PATH $LDAP_TLS_CRT_PATH $LDAP_TLS_KEY_PATH $LDAP_TLS_DH_PARAM_PATH

    # adapt tls ldif
    sed -i "s|{{ LDAP_TLS_CA_CRT_PATH }}|${LDAP_TLS_CA_CRT_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
    sed -i "s|{{ LDAP_TLS_CRT_PATH }}|${LDAP_TLS_CRT_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
    sed -i "s|{{ LDAP_TLS_KEY_PATH }}|${LDAP_TLS_KEY_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
    sed -i "s|{{ LDAP_TLS_DH_PARAM_PATH }}|${LDAP_TLS_DH_PARAM_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif

    sed -i "s|{{ LDAP_TLS_CIPHER_SUITE }}|${LDAP_TLS_CIPHER_SUITE}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
    sed -i "s|{{ LDAP_TLS_PROTOCOL_MIN }}|${LDAP_TLS_PROTOCOL_MIN}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif
    sed -i "s|{{ LDAP_TLS_VERIFY_CLIENT }}|${LDAP_TLS_VERIFY_CLIENT}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif

    ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enable.ldif 2>&1 | log-helper debug

    [[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
    echo "export PREVIOUS_LDAP_TLS_CA_CRT_PATH=${LDAP_TLS_CA_CRT_PATH}" > $WAS_STARTED_WITH_TLS
    echo "export PREVIOUS_LDAP_TLS_CRT_PATH=${LDAP_TLS_CRT_PATH}" >> $WAS_STARTED_WITH_TLS
    echo "export PREVIOUS_LDAP_TLS_KEY_PATH=${LDAP_TLS_KEY_PATH}" >> $WAS_STARTED_WITH_TLS
    echo "export PREVIOUS_LDAP_TLS_DH_PARAM_PATH=${LDAP_TLS_DH_PARAM_PATH}" >> $WAS_STARTED_WITH_TLS

    # ldap client config
    sed -i --follow-symlinks "s,TLS_CACERT.*,TLS_CACERT ${LDAP_TLS_CA_CRT_PATH},g" /etc/ldap/ldap.conf
    echo "TLS_REQCERT ${LDAP_TLS_VERIFY_CLIENT}" >> /etc/ldap/ldap.conf
    cp -f /etc/ldap/ldap.conf ${CONTAINER_SERVICE_DIR}/slapd/assets/ldap.conf

    [[ -f "$HOME/.ldaprc" ]] && rm -f $HOME/.ldaprc
    echo "TLS_CERT ${LDAP_TLS_CRT_PATH}" > $HOME/.ldaprc
    echo "TLS_KEY ${LDAP_TLS_KEY_PATH}" >> $HOME/.ldaprc
    cp -f $HOME/.ldaprc ${CONTAINER_SERVICE_DIR}/slapd/assets/.ldaprc

    # enforce TLS
    if [ "${LDAP_TLS_ENFORCE,,}" == "true" ]; then
      log-helper info "Add enforce TLS..."
      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enforce-enable.ldif 2>&1 | log-helper debug

    # disable tls enforcing
    else
      log-helper info "Disable enforce TLS..."
      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enforce-disable.ldif 2>&1 | log-helper debug || true
    fi

  else
    log-helper info "Disable TLS config..."

    ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-disable.ldif 2>&1 | log-helper debug || true
    [[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
  fi



  #
  # Replication config
  #

  function disableReplication() {
    ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-disable.ldif 2>&1 | log-helper debug || true
    [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
  }

  if [ "${LDAP_REPLICATION,,}" == "true" ]; then

    log-helper info "Add replication config..."
    disableReplication || true

    i=1
    for host in $(complex-bash-env iterate LDAP_REPLICATION_HOSTS)
    do
      sed -i "s|{{ LDAP_REPLICATION_HOSTS }}|olcServerID: $i ${!host}\n{{ LDAP_REPLICATION_HOSTS }}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
      sed -i "s|{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|olcSyncRepl: rid=00$i provider=${!host} ${LDAP_REPLICATION_CONFIG_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
      sed -i "s|{{ LDAP_REPLICATION_HOSTS_HDB_SYNC_REPL }}|olcSyncRepl: rid=10$i provider=${!host} ${LDAP_REPLICATION_HDB_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_HDB_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif

      ((i++))
    done

    get_ldap_base_dn
    sed -i "s|\$LDAP_BASE_DN|$LDAP_BASE_DN|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
    sed -i "s|\$LDAP_ADMIN_PASSWORD|$LDAP_ADMIN_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
    sed -i "s|\$LDAP_CONFIG_PASSWORD|$LDAP_CONFIG_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif

    sed -i "/{{ LDAP_REPLICATION_HOSTS }}/d" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
    sed -i "/{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif
    sed -i "/{{ LDAP_REPLICATION_HOSTS_HDB_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif

    ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-enable.ldif 2>&1 | log-helper debug || true

    [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
    echo "export PREVIOUS_HOSTNAME=${HOSTNAME}" > $WAS_STARTED_WITH_REPLICATION

  else

    log-helper info "Disable replication config..."
    disableReplication || true

  fi

  #
  # stop OpenLDAP
  #
  log-helper info "Stop OpenLDAP..."

  SLAPD_PID=$(cat /run/slapd/slapd.pid)
  kill -15 $SLAPD_PID
  while [ -e /proc/$SLAPD_PID ]; do sleep 0.1; done # wait until slapd is terminated

  #
  # remove config files
  #
  if [ "${LDAP_REMOVE_CONFIG_AFTER_SETUP,,}" == "true" ]; then
    log-helper info "Remove config files..."
    rm -rf ${CONTAINER_SERVICE_DIR}/slapd/assets/config
  fi

  #
  # setup done :)
  #
  log-helper info "First start is done..."
  touch $FIRST_START_DONE
fi

ln -sf ${CONTAINER_SERVICE_DIR}/slapd/assets/.ldaprc $HOME/.ldaprc
ln -sf ${CONTAINER_SERVICE_DIR}/slapd/assets/ldap.conf /etc/ldap/ldap.conf

exit 0
