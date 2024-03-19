#!/usr/bin/env bash
#source /dev/stdin <<< "$(curl -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh --compressed)"
#source /dev/stdin <<< "$(curl -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_db.sh --compressed)"

function _get_dbadmin_user() {
    local _dbadmin="$1"
    local _port="${2:-"5432"}"
    if [ -n "${_dbadmin}" ]; then
        echo "${_dbadmin}"
        return $?
    fi
    if [ "`uname`" = "Darwin" ]; then
        #psql template1 -c "create database $USER"
        _dbadmin="$USER"
    else
        _dbadmin="$(_user_by_port "${_port}" 2>/dev/null)"
    fi
    echo "${_dbadmin:-"postgres"}"
}

function _get_psql_as_admin() {
    local _dbadmin="${1:-"$USER"}"
    local _cmd="${2:-"psql"}"
    local _psql_as_admin="sudo -u ${_dbadmin} -i psql"
    if ! id "${_dbadmin}" &>/dev/null; then
        _log "WARN" "'${_dbadmin}' OS user may not exist. May require to set PGPASSWORD variable."
        # This will ask the password everytime, but you can use PGPASSWORD
        _psql_as_admin="${_cmd} -U ${_dbadmin}"
    elif [ "$USER" == "postgres" ]; then
        _psql_as_admin="${_cmd} -U ${_dbadmin}"
    fi
    echo "${_psql_as_admin}"
}

function _huge_page() {
    # @see: https://www.enterprisedb.com/blog/improving-postgresql-performance-without-making-changes-postgresql
    local _size="${1-"7602"}"   # Empty "" means check only
    local _port="${2:-"5432"}"
    cat /proc/cpuinfo | grep -m1 -w -o -E '(pse|pdpe1gb)'
    if type pmap &>/dev/null; then
        local _pid="$(_pid_by_port "${_port}")" #lsof -ti:${_port:-5432} -sTCP:LISTEN
        if [ -n "${_pid}" ]; then
            pmap -x "${_pid}" | grep -E "(^${_pid}|^Address|hugepage|^total)"  # anon_hugepage (deleted)
        fi
        # total kB / Hugepagesize (2048 kB) = (min) nr_hugepages
    fi

    #if cat /proc/meminfo | grep -E '^HugePages_Total:\s+0$'; then
    if sysctl -a | grep -E '^vm.nr_hugepages\s*=\s*0$'; then
        # TODO: /sys/kernel/mm/hugepages/hugepages-1048576kB
        [ -z "${_size}" ] && return 1
        echo "${_size}" > /proc/sys/vm/nr_hugepages
        if [ -f /etc/sysctl.conf ] && ! grep 'vm.nr_hugepages' /etc/sysctl.conf; then
            echo "vm.nr_hugepages = ${_size}" >> /etc/sysctl.conf
        fi
        sysctl -p
    fi
    # From v15
    #sudo -i -u postgres postgres --shared-buffers=20GB -D $PGDATA -C shared_memory_size_in_huge_pages
}

function _postgresql_configure() {
    # @see: https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server
    local __doc__="Update postgresql.conf and pg_hba.conf. Need to run from the PostgreSQL server (localhost)"
    local _verbose_logging="${1}"   # If Y, adds more logging configs which would work with pgbadger.
    local _wal_archive_dir="${2}"   # Automatically decided if empty
    local _postgresql_conf="${3}"   # Automatically detected if empty. "/var/lib/pgsql/data" or "/etc/postgresql/10/main" or /var/lib/pgsql/12/data/
    local _dbadmin="${4}"
    local _port="${5:-"5432"}"      # just for deciding the username. Optional.
    _dbadmin="$(_get_dbadmin_user "${_dbadmin}" "${_port}")"
    local _psql_as_admin="$(_get_psql_as_admin "${_dbadmin}")"
    local _restart=false

    if [ ! -f "${_postgresql_conf}" ]; then
        _postgresql_conf="$(${_psql_as_admin} -tAc 'SHOW config_file')" || return $?
    fi
    if [ -z "${_postgresql_conf}" ] || [ ! -s "${_postgresql_conf}" ]; then
        _log "ERROR" "No postgresql config file specified."
        return 1
    fi
    local _conf_dir="$(dirname "${_postgresql_conf}")"
    [ ! -s "${_conf_dir%/}/postgresql.conf.orig" ] && cp -f "${_postgresql_conf}" "${_conf_dir%/}/postgresql.conf.orig"
    _log "INFO" "Updating ${_postgresql_conf} ..."

    if ! _huge_page ""; then
        _log "WARN" "Huge Page might not be enabled."
    fi
    #_upsert ${_postgresql_conf} "huge_pages" "try" "#huge_pages"
    #_upsert ${_postgresql_conf} "huge_page_size" "0"    # Use default kernel setting

    ### Performance tuning (so not mandatory). Expecting the server has at least 4GB RAM
    _upsert ${_postgresql_conf} "max_connections" "200" "#max_connections"   # NOTE: work_mem * max_conn < shared_buffers.
    # @see: https://pgtune.leopard.in.ua/#/ and https://pgpedia.info/index.html
    _upsert ${_postgresql_conf} "shared_buffers" "1024MB" "#shared_buffers" # Default 8MB. RAM * 25%. Make sure enough kernel.shmmax (ipcs -l) and /dev/shm if very old Linux or BSD
    _upsert ${_postgresql_conf} "work_mem" "8MB" "#work_mem"    # Default 4MB. RAM * 25% / max_connections (200) + extra a few MB. NOTE: I'm not expecting my PG uses 200 though
    #_upsert ${_postgresql_conf} "maintenance_work_mem" "64MB" "#maintenance_work_mem"    # Default 64MB. Can be higher than work_mem
    _upsert ${_postgresql_conf} "effective_cache_size" "3072MB" "#effective_cache_size" # Default 4GB. RAM * 50% ~ 75%
    #_upsert ${_postgresql_conf} "wal_buffers" "16MB" "#wal_buffers" # Default -1 (1/32 of shared_buffers) Usually higher provides better write performance
    #_upsert ${_postgresql_conf} "random_page_cost" "1.1" "#random_page_cost"   # Default 4.0. If very fast disk is used, recommended to use same as seq_page_cost (1.0)
    #_upsert ${_postgresql_conf} "effective_io_concurrency" "200" "#effective_io_concurrency"   # Default 1. Was for RAID so number of disks. If SSD, somehow 200 is recommended
    _upsert ${_postgresql_conf} "checkpoint_completion_target" "0.9" "#checkpoint_completion_target"    # Default 0.5 (old 'checkpoint_segments')Ratio of checkpoint_timeout (5min). Larger reduce disk I/O but may take checkpointing longer
    _upsert ${_postgresql_conf} "min_wal_size" "1GB" "#min_wal_size"    # Default 80MB
    _upsert ${_postgresql_conf} "max_wal_size" "4GB" "#max_wal_size"    # Default 1GB
    #_upsert ${_postgresql_conf} "max_slot_wal_keep_size" "100GB" "#max_slot_wal_keep_size"    # Default -1 and probably from v13?
    ### End of tuning ###
    _upsert ${_postgresql_conf} "listen_addresses" "'*'" "#listen_addresses"
    [ -d /var/log/postgresql ] || mkdir -p -m 777 /var/log/postgresql
    [ -d /var/log/postgresql ] && _upsert ${_postgresql_conf} "log_directory" "'/var/log/postgresql' " "#log_directory"
    #_upsert ${_postgresql_conf} "ssl" "on" "#ssl"
    # NOTE: key file permission needs to be 0600
    #_upsert ${_postgresql_conf} "ssl_key_file" "'/var/lib/pgsql/12/standalone.localdomain.key'" "#ssl_key_file"
    #_upsert ${_postgresql_conf} "ssl_cert_file" "'/var/lib/pgsql/12/standalone.localdomain.crt'" "#ssl_cert_file"
    #_upsert ${_postgresql_conf} "ssl_ca_file" "'/var/tmp/share/cert/rootCA_standalone.crt'" "#ssl_ca_file"
    #   SELECT setting FROM pg_settings WHERE name like '%hba%';
    # pg_hba.conf: hostssl sonatype sonatype 0.0.0.0/0 md5

    if [ -z "${_wal_archive_dir}" ]; then
        _wal_archive_dir="${_WORK_DIR%/}/backups/`hostname -s`_wal"
    fi
    if [ ! -d "${_wal_archive_dir}" ]; then
        sudo -u "${_dbadmin}" mkdir -v -p "${_wal_archive_dir}" || return $?
    fi

    # @see: https://www.postgresql.org/docs/current/continuous-archiving.html https://www.postgresql.org/docs/current/runtime-config-wal.html
    _upsert ${_postgresql_conf} "archive_mode" "on" "#archive_mode"
    _upsert ${_postgresql_conf} "archive_command" "'test ! -f ${_wal_archive_dir%/}/%f && cp %p ${_wal_archive_dir%/}/%f'" # this is asynchronous
    #TODO: Can't append under #archive_command. Use recovery_min_apply_delay = '1h'
    # For wal/replication/pg_rewind, better save log files outside of _postgresql_conf

    #_upsert ${_postgresql_conf} "log_destination" "stderr" "#log_destination"  # stderr
    _upsert ${_postgresql_conf} "log_error_verbosity" "verbose" "#log_error_verbosity"  # default
    _upsert ${_postgresql_conf} "log_connections" "on" "#log_connections"
    _upsert ${_postgresql_conf} "log_disconnections" "on" "#log_disconnections"
    #_upsert ${_postgresql_conf} "log_duration" "on" "#log_duration"    # This output many lines, so log_min_duration_statement would be better
    _upsert ${_postgresql_conf} "log_lock_waits" "on" "#log_lock_waits"
    _upsert ${_postgresql_conf} "log_temp_files" "1kB" "#log_temp_files"    # -1

    # @see: https://github.com/darold/pgbadger#POSTGRESQL-CONFIGURATION (brew install pgbadger)
    if [[ "${_verbose_logging}" =~ (y|Y) ]]; then
        # @see: https://www.eversql.com/enable-slow-query-log-postgresql/ for AWS RDS to log SQL
        _upsert ${_postgresql_conf} "log_line_prefix" "'%t [%p]: db=%d,user=%u,app=%a,client=%h '" "#log_line_prefix"
        # NOTE: Below stays after restarting and requires superuser
        # ALTER system RESET ALL;
        # ALTER system SET log_min_duration_statement = 0;SELECT pg_reload_conf(); -- 'DATABASE :DBNAME' doesn't work?
        # ALTER system SET log_statement = 'mod';SELECT pg_reload_conf();
        _upsert ${_postgresql_conf} "log_min_duration_statement" "0" "#log_min_duration_statement"
        _upsert ${_postgresql_conf} "log_checkpoints" "on" "#log_checkpoints"
        _upsert ${_postgresql_conf} "log_autovacuum_min_duration" "0" "#log_autovacuum_min_duration"
        # Also, make sure 'autovacuum' is 'on', autovacuum_analyze_scale_factor (0.1), autovacuum_analyze_threshold (50)
    else
        _upsert ${_postgresql_conf} "log_line_prefix" "'%m [%p-%c]: db=%d,user=%u,app=%a,client=%h '" "#log_line_prefix"
        # ALTER system RESET ALL;
        # ALTER system SET log_statement = 'mod';SELECT pg_reload_conf();
        _upsert ${_postgresql_conf} "log_statement" "'mod'" "#log_statement"
        _upsert ${_postgresql_conf} "log_min_duration_statement" "100" "#log_min_duration_statement"
    fi
    # NOTE: ALTER system generates postgresql.auto.conf

    # "CREATE EXTENSION" creates in the current database. "" to check
    local _shared_preload_libraries="auto_explain"
    # https://www.postgresql.org/docs/current/pgstatstatements.html
    if ${_psql_as_admin} -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements schema public;"; then
        _shared_preload_libraries="${_shared_preload_libraries},pg_stat_statements"
        # @see https://www.postgresql.org/docs/current/pgstatstatements.html
        # SELECT pg_stat_statements_reset();
        # NOTE: column name is slightly different by version. eg: total_time instead of total_exec_time
        # SELECT ROUND(mean_exec_time) mean_ms, ROUND(stddev_exec_time) stddev, ROUND(max_exec_time) max_ms, ROUND(total_exec_time) ttl_ms, ROUND(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0)) AS hit_percent, calls, rows, query FROM pg_stat_statements WHERE total_exec_time/calls > 100 ORDER BY 1 DESC LIMIT 100;
    fi
    #${_psql_as_admin} -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_buffercache;"
    # https://github.com/postgres/postgres/blob/master/contrib/pg_prewarm/autoprewarm.c
    # To check: 'ps -aef | grep autoprewarm' and $PGDATA/autoprewarm.blocks file
    if ${_psql_as_admin} -d template1 -c "CREATE EXTENSION IF NOT EXISTS pg_prewarm;"; then
        _shared_preload_libraries="${_shared_preload_libraries},pg_prewarm"
        # select pg_prewarm('<tablename>'); # 2nd arg default is 'buffer', 3rd is 'main'
    fi
    if _upsert ${_postgresql_conf} "shared_preload_libraries" "'${_shared_preload_libraries}'" "#shared_preload_libraries"; then
        _restart=true
    fi

    _upsert ${_postgresql_conf} "auto_explain.log_min_duration" "5000"
    # To check:
    # SELECT setting, pending_restart FROM pg_settings WHERE name = 'shared_preload_libraries';
    # ALTER system SET auto_explain.log_min_duration TO '0';
    # SELECT pg_reload_conf();
    # SELECT * FROM pg_settings WHERE name like 'auto_explain%';

    # SSL / client certificate authentication https://smallstep.com/hello-mtls/doc/combined/postgresql/psql
    #_upsert ${_postgresql_conf} "ssl" "on" "#ssl"
    #_upsert ${_postgresql_conf} "ssl_ca_file" "/var/tmp/share/cert/rootCA.pem" "#ssl_ca_file"
    #_upsert ${_postgresql_conf} "ssl_cert_file" "/var/tmp/share/cert/standalone.localdomain.crt" "#ssl_cert_file"
    #_upsert ${_postgresql_conf} "ssl_key_file" "/var/tmp/share/cert/standalone.localdomain_postgres.key" "#ssl_key_file"
    # NOTE: .key file needs to be owned by postgres
    # NOTE: modify pg_hba.conf: hostssl nxrm3ha1 all 0.0.0.0/0 md5 clientcert=1
    # NOTE: also it seems restart is required
    # TEST: echo | openssl s_client -starttls postgres -connect localhost:5432 -state #-debug

    diff -wu ${__TMP%/}/postgresql.conf.orig ${_postgresql_conf}
    if ${_restart} || ! ${_psql_as_admin} -d template1 -c "SELECT pg_reload_conf();"; then
        _log "INFO" "Updated postgresql config. Please restart or reload the service."
    fi
}

function _postgresql_create_dbuser() {
    local __doc__="Create DB user/role and database/schema and update pg_hba.conf. Need to run from the PostgreSQL server (localhost)"
    local _dbusr="${1}"
    local _dbpwd="${2:-"${_dbusr}"}"
    local _dbname="${3-"${_dbusr}"}"    # accept "" (empty string), then 'all' database is allowed
    local _schema="${4}"
    local _dbadmin="${5}"
    local _port="${6:-"5432"}"
    local _force="${7-"${_RECREATE_DB}"}"
    _dbadmin="$(_get_dbadmin_user "${_dbadmin}" "${_port}")"
    local _psql_as_admin="$(_get_psql_as_admin "${_dbadmin}")"

    local _pg_hba_conf="$(${_psql_as_admin} -d template1 -tAc 'SHOW hba_file')"
    if [ ! -f "${_pg_hba_conf}" ]; then
        _log "WARN" "No pg_hba.conf (${_pg_hba_conf}) found."
        return 1
    fi
    if [ -z "${_dbname}" ]; then
        _log "WARN" "No _dbname specified, which will allow ${_dbusr} to access 'all' database."
        sleep 3
    fi

    # NOTE: Use 'hostssl all all 0.0.0.0/0 cert clientcert=1' for 2-way | client certificate authentication
    #       To do that, also need to utilise database.parameters.some_key:value in config.yml
    local _sudo=""
    [ -r "${_pg_hba_conf}" ] || _sudo="sudo -u ${_dbadmin}"
    if ! ${_sudo} grep -E "host\s+(${_dbname:-"all"}|all)\s+${_dbusr}\s+" "${_pg_hba_conf}"; then
        ${_sudo} bash -c "echo \"host ${_dbname:-"all"} ${_dbusr} 0.0.0.0/0 md5\" >> \"${_pg_hba_conf}\"" || return $?
        ${_psql_as_admin} -d template1 -tAc 'SELECT pg_reload_conf()' || return $?
        #${_psql_as_admin} -tAc 'SELECT pg_read_file('pg_hba.conf');'
        ${_psql_as_admin} -d template1 -tAc "select * from pg_hba_file_rules where database = '{${_dbname:-"all"}}' and user_name = '{${_dbusr}}';"
    fi

    [ "${_dbusr}" == "all" ] && return 0    # not creating user 'all'
    _log "INFO" "Creating Role:${_dbusr} and Database:${_dbname} ..."
    _postgresql_create_role_and_db "${_dbusr}" "${_dbpwd}" "${_dbname}" "${_schema}" "${_dbadmin}" "${_port}" "${_force}"
}

function _postgresql_create_role_and_db() {
    local __doc__="Create DB user/role and database/schema (no pg_hba.conf update)"
    local _dbusr="${1}" # new DB user
    local _dbpwd="${2:-"${_dbusr}"}"
    local _dbname="${3-"${_dbusr}"}"    # If explicitly "", not creating DB but user/role only
    local _schema="${4}"
    local _dbadmin="${5}"
    local _port="${6:-"5432"}"
    local _force="${7-"${_RECREATE_DB}"}"
    _dbadmin="$(_get_dbadmin_user "${_dbadmin}" "${_port}")"

    local _psql_as_admin="$(_get_psql_as_admin "${_dbadmin}")"
    # NOTE: need to be superuser and 'usename' is correct. options: -t --tuples-only, -A --no-align, -F --field-separator
    ${_psql_as_admin} -d template1 -tA -c "SELECT usename FROM pg_shadow" | grep -q "^${_dbusr}$" || ${_psql_as_admin} -d template1 -c "CREATE USER \"${_dbusr}\" WITH LOGIN PASSWORD '${_dbpwd}';"    # not SUPERUSER
    if [ "${_dbadmin}" != "postgres" ] && [ "${_dbadmin}" != "$USER" ]; then
        # TODO ${_dbadmin%@*} is only for Azure
        ${_psql_as_admin} -d template1 -c "GRANT \"${_dbusr}\" TO \"${_dbadmin%@*}\";"
    fi

    if [ -n "${_dbname}" ]; then
        local _create_db=true
        if ${_psql_as_admin} -d template1 -ltA  -F',' | grep -q "^${_dbname},"; then
            if [[ "${_force}" =~ ^[yY] ]]; then
                _log "WARN" "${_dbname} already exists. As force is specified, dropping ${_dbname} ..."
                sleep 5
                ${_psql_as_admin} -d template1 -c "DROP DATABASE \"${_dbname}\";"
            else
                _log "WARN" "${_dbname} already exists. May need to run below first:
        ${_psql_as_admin} -d ${_dbname} -c \"DROP SCHEMA ${_schema:-"public"} CASCADE;CREATE SCHEMA ${_schema:-"public"} AUTHORIZATION ${_dbusr};GRANT ALL ON SCHEMA ${_schema:-"public"} TO ${_dbusr};\""
                sleep 3
                _create_db=false
            fi
        fi
        if ${_create_db}; then
            # NOTE: to copy a database locally 'WITH TEMPLATE another_db OWNER ${_dbusr}'
            ${_psql_as_admin} -d template1 -c "CREATE DATABASE \"${_dbname}\" WITH OWNER \"${_dbusr}\" ENCODING 'UTF8';"
        else
            ${_psql_as_admin} -d template1 -c "GRANT ALL ON DATABASE \"${_dbname}\" TO \"${_dbusr}\";" >/dev/null || return $?
        fi
        # NOTE: For postgresql v15 change. Also use double-quotes for case sensitivity?
        ${_psql_as_admin} -d ${_dbname} -c "GRANT ALL ON SCHEMA public TO \"${_dbusr}\";" >/dev/null
        # To delete user: DROP OWNED BY ${_dbusr}; DROP USER ${_dbusr};

        if [ -n "${_schema}" ]; then
            local _search_path="${_dbusr},public"
            for _s in ${_schema}; do
                ${_psql_as_admin} -d ${_dbname} -c "CREATE SCHEMA IF NOT EXISTS ${_s} AUTHORIZATION ${_dbusr};"
                _search_path="${_search_path},${_s}"
            done
            ${_psql_as_admin} -d template1 -c "ALTER ROLE ${_dbusr} SET search_path = ${_search_path};"
        fi
    fi

    # test
    local _cmd="psql -h $(hostname -f) -p 5432 -U ${_dbusr} -d ${_dbname} -c \"\l ${_dbname}\""
    _log "INFO" "Testing the connection with \"${_cmd}\" ..."
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
    _dbadmin="$(_get_dbadmin_user "${_dbadmin}" "${_port}")"

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

# _postgresql_create_dbuser "test"
function _psql_restore() {
    local __doc__="To import database / restore database from pg_dump result with psql"
    local _dump_filepath="$1"
    local _dbusr="${2:-"${_DBUSER:-"$USER"}"}"
    local _dbpwd="${3:-"${PGPASSWORD:-"${_dbusr}"}"}"
    local _dbname="${4:-"${_DBNAME:-"${_dbusr}"}"}"
    local _schema="${5}"    #:-"public"
    local _opts="${6-"${_PSQL_OPTIONS}"}"  # eg: '--set ON_ERROR_STOP=1' '--set VERBOSITY=verbose' doesn't add any extra information
    local _dbhost="${7:-"${_DBHOST:-"localhost"}"}"
    local _dbport="${8:-"${_DBPORT:-"5432"}"}"
    local _db_del_cascade="${9:-"${_DB_DEL_CASCADE}"}"
    # NOTE: pg_restore has useful options: --jobs=2 --no-owner --verbose #--clean --data-only, but does not support SQL file
    #PGPASSWORD="${_dbpwd}" pg_restore -h ${_dbhost} -U ${_dbusr} -d ${_dbname} --jobs=2 --no-owner --verbose ${_dump_filepath}
    _postgresql_create_role_and_db "${_dbusr}" "${_dbpwd}" "${_dbname}" "${_schema}"
    local _cmd=""
    if [[ "${_dump_filepath}" =~ \.gz$ ]]; then
        _cmd="gunzip -c ${_dump_filepath}"
    else
        _cmd="cat ${_dump_filepath}"
    fi
    if [ -n "${_schema}" ]; then
        _cmd="${_cmd} | sed -E 's/ SCHEMA [^ ;]+/ SCHEMA ${_schema}/'"
    fi
    if [ -n "${_dbusr}" ]; then
        _cmd="${_cmd} | sed -E 's/( OWNER|GRANT ALL ON SCHEMA .+) TO [^ ]+;/\1 TO ${_dbusr};/'"
    fi
    if [[ "${_db_del_cascade}" =~ ^[yY] ]]; then
        _cmd="${_cmd} | sed -E 's/^DROP TABLE ([^;]+);$/DROP TABLE \1 cascade;/'"
    fi
    local _cmd2="psql ${_opts} -h ${_dbhost} -p ${_dbport} -U ${_dbusr} -d ${_dbname} -L ./${FUNCNAME[0]}_psql.log 2>./${FUNCNAME[0]}_psql.log"
    echo "${_cmd} | ${_cmd2}"; sleep 3
    eval "${_cmd} | PGPASSWORD="${_dbpwd}" ${_cmd2}"
    grep -w "ERROR" ./${FUNCNAME[0]}_psql.log && return 1
}

function _psql_copydb() {
    local __doc__="Copy database with 'pg_dump | psql' as superuser because 'CREATE DATABASE ... WITH TEMPLATE dbname' keeps owners"
    local _local_src_db="${1}"
    local _dbusr="${2:-"$USER"}"
    local _dbpwd="${3:-"${_dbusr}"}"
    local _dbname="${4:-"${_dbusr}"}"
    #local _schema="${5}"    # psql ... -n "${_schema}"
    local _dbhost="${5:-"${_DBHOST:-"localhost"}"}"
    local _dbport="${6:-"${_DBPORT:-"5432"}"}"

    local _pg_dump_as_admin="$(_get_psql_as_admin "$(_get_dbadmin_user)" "pg_dump" "${_dbport}")"
    ${_pg_dump_as_admin} -d "${_local_src_db}" -c -O | PGPASSWORD="${_dbpwd}" psql -h ${_dbhost} -p ${_dbport} -U ${_dbusr} -d ${_dbname}
}
