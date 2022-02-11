#!/usr/bin/env bash
#source /dev/stdin <<< "$(curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh --compressed)"
#source /dev/stdin <<< "$(curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_db.sh --compressed)"

function _postgresql_configure() {
    # @see: https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server
    local __doc__="Update postgresql.conf and pg_hba.conf. Need to run from the PostgreSQL server (localhost)"
    local _verbose_logging="${1}"   # If Y, adds more logging configs which would work with pgbadger.
    local _wal_archive_dir="${2}"   # Automatically decided if empty
    local _postgresql_conf="${3}"   # Automatically detected if empty. "/var/lib/pgsql/data" or "/etc/postgresql/10/main" or /var/lib/pgsql/12/data/
    local _dbadmin="${4}"
    local _port="${5:-"5432"}"      # just for deciding the username. Optional.

    if [ -z "${_dbadmin}" ]; then
        if [ "`uname`" = "Darwin" ]; then
            _dbadmin="$USER"
        else
            _dbadmin="$(_user_by_port "${_port}" 2>/dev/null)"
            [ -z "${_dbadmin}" ] && _dbadmin="postgres"
        fi
    fi
    local _psql_as_admin="sudo -u ${_dbadmin} -i psql"
    if ! grep -q "^${_dbadmin}" /etc/passwd; then
        # This will ask the password everytime, but you can use PGPASSWORD
        _psql_as_admin="psql -U ${_dbadmin}"
    fi

    if [ ! -f "${_postgresql_conf}" ]; then
        _postgresql_conf="$(${_psql_as_admin} -tAc 'SHOW config_file')" || return $?
    fi

    if [ -z "${_postgresql_conf}" ] || [ ! -s "${_postgresql_conf}" ]; then
        _log "ERROR" "No postgresql config file specified."
        return 1
    fi

    [ ! -s "${__TMP%/}/postgresql.conf.orig" ] && cp -f "${_postgresql_conf}" "${__TMP%/}/postgresql.conf.orig"

    _log "INFO" "Updating ${_postgresql_conf} ..."
    # Performance tuning (so not mandatory). Expecting the server has at least 4GB RAM
    # @see: https://pgtune.leopard.in.ua/#/
    _upsert ${_postgresql_conf} "shared_buffers" "1024MB"       # Default 8MB. RAM * 25%. Make sure enough kernel.shmmax (ipcs -l) and /dev/shm
    _upsert ${_postgresql_conf} "work_mem" "8MB" "#work_mem"    # Default 4MB. RAM * 25% / max_connections (200) + extra a few MB. NOTE: I'm not expecting my PG uses 200 though
    #_upsert ${_postgresql_conf} "maintenance_work_mem" "64MB" "#maintenance_work_mem"    # Default 64MB. Can be higher than work_mem
    _upsert ${_postgresql_conf} "effective_cache_size" "3072MB" "#effective_cache_size" # RAM * 50% ~ 75%
    _upsert ${_postgresql_conf} "wal_buffers" "16MB" "#wal_buffers" # Usually higher provides better write performance
    ### End of tuning ###
    _upsert ${_postgresql_conf} "max_connections" "200" "#max_connections"   # This is for NXRM3 as it uses 100 per datastore NOTE: work_mem * max_conn < shared_buffers.
    _upsert ${_postgresql_conf} "listen_addresses" "'*'" "#listen_addresses"
    [ ! -d /var/log/postgresql ] && mkdir -p -m 777 /var/log/postgresql
    _upsert ${_postgresql_conf} "log_directory" "'/var/log/postgresql' " "#log_directory"
    #_upsert ${_postgresql_conf} "ssl" "on" "#ssl"
    # NOTE: key file permission needs to be 0600
    #_upsert ${_postgresql_conf} "ssl_key_file" "'/var/lib/pgsql/12/standalone.localdomain.key'" "#ssl_key_file"
    #_upsert ${_postgresql_conf} "ssl_cert_file" "'/var/lib/pgsql/12/standalone.localdomain.crt'" "#ssl_cert_file"
    #_upsert ${_postgresql_conf} "ssl_ca_file" "'/var/tmp/share/cert/rootCA_standalone.crt'" "#ssl_ca_file"
    # pg_hba.conf: hostssl sonatype sonatype 0.0.0.0/0 md5

    if [ -z "${_wal_archive_dir}" ]; then
        _wal_archive_dir="${_WORK_DIR%/}/${_dbadmin}/backups/${_save_dir%/}/`hostname -s`_wal"
    fi
    if [ ! -d "${_wal_archive_dir}" ]; then
        sudo -u "${_dbadmin}" mkdir -v -p "${_wal_archive_dir}" || return $?
    fi

    # @see: https://www.postgresql.org/docs/current/continuous-archiving.html https://www.postgresql.org/docs/current/runtime-config-wal.html
    _upsert ${_postgresql_conf} "archive_mode" "on" "#archive_mode"
    _upsert ${_postgresql_conf} "archive_command" "'test ! -f ${_wal_archive_dir%/}/%f && cp %p ${_wal_archive_dir%/}/%f'" "#archive_command" # this is asynchronous
    #TODO: use recovery_min_apply_delay = '1h'
    # For wal/replication/pg_rewind, better save log files outside of _postgresql_conf

    _upsert ${_postgresql_conf} "log_error_verbosity" "default" "#log_error_verbosity"
    _upsert ${_postgresql_conf} "log_connections" "on" "#log_connections"
    _upsert ${_postgresql_conf} "log_disconnections" "on" "#log_disconnections"
    _upsert ${_postgresql_conf} "log_lock_waits" "on" "#log_lock_waits"
    _upsert ${_postgresql_conf} "log_temp_files" "0" "#log_temp_files"

    if [[ "${_verbose_logging}" =~ (y|Y) ]]; then
        # @see: https://github.com/darold/pgbadger#POSTGRESQL-CONFIGURATION (brew install pgbadger)
        # To log the SQL statements
        _upsert ${_postgresql_conf} "log_line_prefix" "'%m [%p-%l]: user=%u,db=%d,app=%a,client=%h '" "#log_line_prefix"
        _upsert ${_postgresql_conf} "log_min_duration_statement" "0" "#log_min_duration_statement"
        _upsert ${_postgresql_conf} "log_checkpoints" "on" "#log_checkpoints"
        _upsert ${_postgresql_conf} "log_autovacuum_min_duration" "0" "#log_autovacuum_min_duration"
    else
        _upsert ${_postgresql_conf} "log_line_prefix" "'%m [%p-%l]: user=%u,db=%d,vtid=%v '" "#log_line_prefix"
        _upsert ${_postgresql_conf} "log_statement" "'mod'" "#log_statement"
        _upsert ${_postgresql_conf} "log_min_duration_statement" "1000" "#log_min_duration_statement"
    fi
    # To check:
    # SELECT setting, pending_restart FROM pg_settings WHERE name = 'shared_preload_libraries';
    #CREATE EXTENSION IF NOT EXISTS pg_buffercache;
    local _shared_preload_libraries="auto_explain"
    if ${_psql_as_admin} -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_prewarm;"; then
        _shared_preload_libraries="${_shared_preload_libraries},pg_prewarm"
        # select pg_prewarm('<tablename>', 'buffer');
    fi
    _upsert ${_postgresql_conf} "shared_preload_libraries" "'${_shared_preload_libraries}'" "#shared_preload_libraries"
    #ALTER SYSTEM SET auto_explain.log_min_duration TO '0';
    #SELECT pg_reload_conf();
    #SELECT * FROM pg_settings WHERE name like 'auto_explain%';
    _upsert ${_postgresql_conf} "auto_explain.log_min_duration" "5000"

    diff -wu ${__TMP%/}/postgresql.conf.orig ${_postgresql_conf}
    _log "INFO" "Updated postgresql config. Please restart (or reload) the service."
}

function _postgresql_create_dbuser() {
    local __doc__="Create DB user/role/schema/database. Need to run from the PostgreSQL server (localhost)"
    local _dbusr="${1}"
    local _dbpwd="${2:-"${_dbusr}"}"
    local _dbname="${3:-"${_dbusr}"}"
    local _schema="${4}"
    local _dbadmin="${5}"
    local _port="${6:-"5432"}"

    if [ -z "${_dbadmin}" ]; then
        if [ "`uname`" = "Darwin" ]; then
            #psql template1 -c "create database $USER"
            _dbadmin="$USER"
        else
            _dbadmin="$(_user_by_port "${_port}" 2>/dev/null)"
            [ -z "${_dbadmin}" ] && _dbadmin="postgres"
        fi
    fi
    local _psql_as_admin="sudo -u ${_dbadmin} -i psql"
    if ! id "${_dbadmin}" &>/dev/null; then
        _log "WARN" "'${_dbadmin}' OS user may not exist. May require to set PGPASSWORD variable."
        # This will ask the password everytime, but you can use PGPASSWORD
        _psql_as_admin="psql -U ${_dbadmin}"
    fi

    local _pg_hba_conf="$(${_psql_as_admin} -tAc 'SHOW hba_file')"
    if [ ! -f "${_pg_hba_conf}" ]; then
        _log "WARN" "No pg_hba.conf file found."
        return 1
    fi

    # NOTE: Use 'hostssl all all 0.0.0.0/0 cert clientcert=1' for 2-way | client certificate authentication
    #       To do that, also need to utilise database.parameters.some_key:value in config.yml
    if ! grep -E "host\s+${_dbname}\s+${_dbusr}\s+" "${_pg_hba_conf}"; then
        echo "host ${_dbname} ${_dbusr} 0.0.0.0/0 md5" >> "${_pg_hba_conf}" || return $?
        ${_psql_as_admin} -tAc 'SELECT pg_reload_conf()' || return $?
    fi
    [ "${_dbusr}" == "all" ] && return 0

    _log "INFO" "Creating Role:${_dbusr} and Database:${_dbname} ..."
    _postgresql_create_role_and_db "${_dbusr}" "${_dbpwd}" "${_dbname}" "${_schema}" "${_dbadmin}"
}

function _postgresql_create_role_and_db() {
    local _dbusr="${1}" # new DB user
    local _dbpwd="${2:-"${_dbusr}"}"
    local _dbname="${3:-"${_dbusr}"}"
    local _schema="${4}"
    local _dbadmin="${5}"
    local _dbhost="${6}"
    local _dbport="${7:-"5432"}"

    if [ -z "${_dbadmin}" ]; then
        if [ "`uname`" = "Darwin" ]; then
            #psql template1 -c "create database $USER"
            _dbadmin="$USER"
        else
            _dbadmin="$(_user_by_port "${_port}" 2>/dev/null)"
            [ -z "${_dbadmin}" ] && _dbadmin="postgres"
        fi
    fi

    local _psql_as_admin="sudo -u ${_dbadmin} -i psql"
    if [ -n "${_dbhost}" ]; then
        if [ -z "${PGPASSWORD}" ]; then
            echo "No PGPASSWORD set for ${_dbadmin}"; return 1
        fi
        _psql_as_admin="psql -U ${_dbadmin} -h ${_dbhost} -p ${_dbport}"
    fi
    # NOTE: need to be superuser and 'usename' is correct. options: -t --tuples-only, -A --no-align, -F --field-separator
    ${_psql_as_admin} -d template1 -tA -c "SELECT usename FROM pg_shadow" | grep -q "^${_dbusr}$" || ${_psql_as_admin} -d template1 -c "CREATE ROLE ${_dbusr} WITH LOGIN PASSWORD '${_dbpwd}';"    # not SUPERUSER
    if [ "${_dbadmin}" != "posrgres" ] && [ "${_dbadmin}" != "$USER" ]; then
        # TODO ${_dbadmin%@*} is only for Azure
        ${_psql_as_admin} -d template1 -c "GRANT ${_dbusr} TO \"${_dbadmin%@*}\";"
    fi
    ${_psql_as_admin} -d template1 -ltA  -F',' | grep -q "^${_dbname}," || ${_psql_as_admin} -d template1 -c "CREATE DATABASE ${_dbname} WITH OWNER ${_dbusr} ENCODING 'UTF8';"
    # NOTE: Below two lines are NOT needed because of 'WITH OWNER'. Just for testing purpose to avoid unnecessary permission errors.
    ${_psql_as_admin} -d template1 -c "GRANT ALL ON DATABASE ${_dbname} TO \"${_dbusr}\";" || return $?
    ${_psql_as_admin} -d ${_dbname} -c "GRANT ALL ON SCHEMA public TO \"${_dbusr}\";"

    if [ -n "${_schema}" ]; then
        local _search_path="${_dbusr},public"
        for _s in ${_schema}; do
            ${_psql_as_admin} -d ${_dbname} -c "CREATE SCHEMA IF NOT EXISTS ${_s} AUTHORIZATION ${_dbusr};"
            _search_path="${_search_path},${_s}"
        done
        ${_psql_as_admin} -d template1 -c "ALTER ROLE ${_dbusr} SET search_path = ${_search_path};"
    fi
    # test
    local _host_name="$(hostname -f)"
    local _cmd="psql -U ${_dbusr} -h ${_dbhost:-"${_host_name}"} -d ${_dbname} -c \"\l ${_dbname}\""
    _log "INFO" "Testing connection with \"${_cmd}\" ..."
    eval "PGPASSWORD=\"${_dbpwd}\" ${_cmd}" || return $?
}

function _postgres_pitr() {
    local __doc__="Point In Time Recovery for PostgreSQL *12* (not tested with other versions). Need to run from the PostgreSQL server (localhost)"
    # @see: https://www.postgresql.org/docs/12/continuous-archiving.html#BACKUP-PITR-RECOVERY
    # NOTE: this function doesn't do any assumption. almost all arguments need to be specified.
    local _data_dir="${1}"              # /var/lib/pgsql/data, /var/lib/pgsql/12/data or /usr/local/var/postgres (Mac)
    local _base_backup_tgz="${2}"       # File path. eg: .../node-nxiq1960_base_20201105T091218z/base.tar.gz
    local _wal_archive_dir="${3}"       # ${_WORK_DIR%/}/${_SERVICE%/}/backups/`hostname -s`_wal
    local _target_ISO_datetime="${4}"   # yyyy-mm-dd hh:mm:ss (optional)
    local _dbadmin="${5:-"postgres"}"   # DB OS user
    local _port="${6:-"5432"}"          # PostgreSQL port number (optional)

    if [ ! -d "${_data_dir}" ]; then
        _log "ERROR" "No PostgreSQL data dir provided: ${_data_dir}"
    fi
    if [ ! -s "${_base_backup_tgz}" ]; then
        _log "ERROR" "No base backup file: ${_base_backup_tgz}"
        return 1
    fi
    local _pid="$(_pid_by_port "${_port}")"
    if [ -n "${_pid}" ]; then
        _log "ERROR" "Please stop postgresql first: ${_pid}"
        return 1
    fi

    mv -v ${_data_dir%/} ${_data_dir%/}_$(date +"%Y%m%d%H%M%S") || return $?
    sudo -u ${_dbadmin} -i mkdir -m 700 -p ${_data_dir%/} || return $?
    tar -xvf "${_base_backup_tgz}" -C "${_data_dir%/}" || return $?
    sudo -u ${_dbadmin} -i touch ${_data_dir%/}/recovery.signal || return $?
    #mv -v ${_data_dir%/}/pg_wal/* ${_TMP%/}/ || return $?
    if [ -s "$(dirname "${_base_backup_tgz}")/pg_wal.tar.gz" ]; then
        tar -xvf "$(dirname "${_base_backup_tgz}")/pg_wal.tar.gz" -C "${_data_dir%/}/pg_wal"
    fi

    # NOTE: From PostgreSQL 12, no recovery.conf
    if [ ! -s ${_data_dir%/}/postgresql.conf.bak ]; then
        cp -p ${_data_dir%/}/postgresql.conf ${_data_dir%/}/postgresql.conf.bak || return $?
    fi
    _upsert ${_data_dir%/}/postgresql.conf "restore_command" "'cp ${_wal_archive_dir%/}/%f "%p"'" "#restore_command "
    _upsert ${_data_dir%/}/postgresql.conf "recovery_target_action" "'promote'" "#recovery_target_action "
    [ -n "${_target_ISO_datetime}" ] && _upsert ${_data_dir%/}/postgresql.conf "recovery_target_time" "'${_target_ISO_datetime}'" "#recovery_target_time "
    diff -u ${_data_dir%/}/postgresql.conf.bak ${_data_dir%/}/postgresql.conf
    _log "INFO" "postgresql.conf has been updated. Please start PostgreSQL for recovery then 'promote'."
    # Upon completion of the recovery process, the server will remove recovery.signal (to prevent accidentally re-entering recovery mode later) and then commence normal database operations.
}