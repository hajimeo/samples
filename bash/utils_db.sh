#!/usr/bin/env bash
#source /dev/stdin <<< "$(curl -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils.sh --compressed)"
#source /dev/stdin <<< "$(curl -sfL https://raw.githubusercontent.com/hajimeo/samples/master/bash/utils_db.sh --compressed)"

_DB_ADMIN="${_DB_ADMIN:-"postgres"}"
_CMD_PREFIX="${_CMD_PREFIX:-""}"  # "docker exec -ti name" or "ssh postgres@host"

function _as_dbadmin() {
    if [ -n "${_CMD_PREFIX}" ]; then
        ${_CMD_PREFIX} "$@"
    else
        "$@"
    fi
}

function _psql_adm() {
    local _sql="${1}"
    local _extra_opts="${2}"
    _as_dbadmin psql -d template1 ${_extra_opts} -c "${_sql}"
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
    local __doc__="Update postgresql.conf. Need to run from the PostgreSQL server (localhost)"
    local _verbose_logging="${1}"   # If Y, adds more logging configs which would work with pgbadger.
    local _wal_archive_dir="${2}"   # Automatically decided if empty
    local _postgresql_conf="${3}"   # Automatically detected if empty. "/var/lib/pgsql/data" or "/etc/postgresql/10/main" or /var/lib/pgsql/12/data/
    local _port="${4:-"5432"}"      # just for deciding the username. Optional.
    local _restart=false

    if [ ! -f "${_postgresql_conf}" ]; then
        _postgresql_conf="$(_as_dbadmin psql -tAc 'SHOW config_file')" || return $?
    fi
    if [ -z "${_postgresql_conf}" ] || [ ! -s "${_postgresql_conf}" ]; then
        _log "ERROR" "No postgresql config file specified."
        return 1
    fi
    local _conf_dir="$(dirname "${_postgresql_conf}")"
    [ ! -s "${_conf_dir%/}/postgresql.conf.orig" ] && cp -f "${_postgresql_conf}" "${_conf_dir%/}/postgresql.conf.orig"
    _log "INFO" "Updating ${_postgresql_conf} ..."

    # TODO: Do I still need this?
    if ! _huge_page ""; then
        _log "WARN" "Huge Page might not be enabled."
    fi
    #_upsert ${_postgresql_conf} "huge_pages" "try" "#huge_pages"
    #_upsert ${_postgresql_conf} "huge_page_size" "0"    # Use default kernel setting

    ### Performance tuning (so not mandatory). Expecting the server has at least 4GB RAM
    # @see: https://pgtune.leopard.in.ua/#/ and https://pgpedia.info/index.html
    _psql_adm "ALTER SYSTEM SET max_connections TO '200'"   # NOTE: work_mem * max_conn < shared_buffers.
    _psql_adm "ALTER SYSTEM SET statement_timeout TO '8h'" # NOTE: ALTER ROLE nexus SET statement_timeout = '1h';
    _psql_adm "ALTER SYSTEM SET shared_buffers TO '1024MB'" # Default 8MB. RAM * 25%. Make sure enough kernel.shmmax (ipcs -l) and /dev/shm if very old Linux or BSD
    _psql_adm "ALTER SYSTEM SET work_mem TO '8MB'"    # Default 4MB. RAM * 25% / max_connections (200) + extra a few MB. NOTE: I'm not expecting my PG uses 200 though
    #_upsert ${_postgresql_conf} "maintenance_work_mem" "64MB" "#maintenance_work_mem"    # Default 64MB. Used for VACUUM, CREATE INDEX etc.
    #_upsert ${_postgresql_conf} "autovacuum_work_mem" "-1" "#autovacuum_work_mem"    # Default -1 means uses the above for AUTO vacuum.
    _psql_adm "ALTER SYSTEM SET effective_cache_size TO '3072MB'" # Default 4GB. RAM * 50% ~ 75%. Used by planner.
    #_upsert ${_postgresql_conf} "wal_buffers" "16MB" "#wal_buffers" # Default -1 (1/32 of shared_buffers) Usually higher provides better write performance
    #_upsert ${_postgresql_conf} "random_page_cost" "1.1" "#random_page_cost"   # Default 4.0. If very fast disk is used, recommended to use same as seq_page_cost (1.0)
    #_upsert ${_postgresql_conf} "effective_io_concurrency" "200" "#effective_io_concurrency"   # Default 1. Was for RAID so number of disks. If SSD, somehow 200 is recommended
    _psql_adm "ALTER SYSTEM SET checkpoint_completion_target TO '0.9'"    # Default 0.5 (old 'checkpoint_segments')Ratio of checkpoint_timeout (5min). Larger reduce disk I/O but may take checkpointing longer
    _psql_adm "ALTER SYSTEM SET min_wal_size TO '1GB'"    # Default 80MB
    _psql_adm "ALTER SYSTEM SET max_wal_size TO '4GB'"    # Default 1GB
    #_upsert ${_postgresql_conf} "max_slot_wal_keep_size" "100GB" "#max_slot_wal_keep_size"    # Default -1 and probably from v13?
    ### End of tuning ###
    _psql_adm "ALTER SYSTEM SET listen_addresses TO ''*''"
    [ -d /var/log/postgresql ] || mkdir -p -m 777 /var/log/postgresql
    [ -d /var/log/postgresql ] && _psql_adm "ALTER SYSTEM SET log_directory TO ''/var/log/postgresql' '"

    if [ -z "${_wal_archive_dir}" ]; then
        _wal_archive_dir="${_WORK_DIR%/}/backups/`hostname -s`_wal"
    fi
    if [ ! -d "${_wal_archive_dir}" ]; then
        sudo -u "${_DB_ADMIN}" mkdir -v -p "${_wal_archive_dir}" || return $?
    fi

    # @see: https://www.postgresql.org/docs/current/continuous-archiving.html https://www.postgresql.org/docs/current/runtime-config-wal.html
    _psql_adm "ALTER SYSTEM SET archive_mode TO 'on'"
    _upsert ${_postgresql_conf} "archive_command" "'test ! -f ${_wal_archive_dir%/}/%f && cp %p ${_wal_archive_dir%/}/%f'" # this is asynchronous
    #TODO: Can't append under #archive_command. Use recovery_min_apply_delay = '1h'
    # For wal/replication/pg_rewind, better save log files outside of _postgresql_conf

    #_upsert ${_postgresql_conf} "log_destination" "stderr" "#log_destination"  # stderr
    _psql_adm "ALTER SYSTEM SET log_error_verbosity TO 'verbose'"  # default
    _psql_adm "ALTER SYSTEM SET log_connections TO 'on'"
    _psql_adm "ALTER SYSTEM SET log_disconnections TO 'on'"
    #_upsert ${_postgresql_conf} "log_duration" "on" "#log_duration"    # This output many lines, so log_min_duration_statement would be better
    _psql_adm "ALTER SYSTEM SET log_lock_waits TO 'on'"
    _psql_adm "ALTER SYSTEM SET log_temp_files TO '1kB'"    # -1

    # @see: https://github.com/darold/pgbadger#POSTGRESQL-CONFIGURATION (brew install pgbadger)
    if [[ "${_verbose_logging}" =~ (y|Y) ]]; then
        # @see: https://www.eversql.com/enable-slow-query-log-postgresql/ for AWS RDS to log SQL
        _psql_adm "ALTER SYSTEM SET log_line_prefix TO ''%t [%p]: db=%d,user=%u,app=%a,client=%h ''"
        # NOTE: Below stays after restarting and requires superuser
        # ALTER system RESET ALL;
        # ALTER system SET log_min_duration_statement = 0;SELECT pg_reload_conf(); -- 'DATABASE :DBNAME' doesn't work?
        # ALTER system SET log_statement = 'mod';SELECT pg_reload_conf();
        _psql_adm "ALTER SYSTEM SET log_min_duration_statement TO '0'"
        _psql_adm "ALTER SYSTEM SET log_checkpoints TO 'on'"
        _psql_adm "ALTER SYSTEM SET log_autovacuum_min_duration TO '0'"
        # Also, make sure 'autovacuum' is 'on', autovacuum_analyze_scale_factor (0.1), autovacuum_analyze_threshold (50)
    else
        _psql_adm "ALTER SYSTEM SET log_line_prefix TO ''%m [%p-%c]: db=%d,user=%u,app=%a,client=%h ''"
        # ALTER system RESET ALL;
        # ALTER system SET log_statement = 'mod';SELECT pg_reload_conf();
        _psql_adm "ALTER SYSTEM SET log_statement TO ''mod''"
        _psql_adm "ALTER SYSTEM SET log_min_duration_statement TO '100'"
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
    if _psql_adm "ALTER SYSTEM SET shared_preload_libraries TO ''${_shared_preload_libraries}''"; then
        _restart=true
    fi

    _upsert ${_postgresql_conf} "auto_explain.log_min_duration" "5000"
    # To check:
    # SELECT setting, pending_restart FROM pg_settings WHERE name = 'shared_preload_libraries';
    # ALTER system SET auto_explain.log_min_duration TO '0';
    # SELECT pg_reload_conf();
    # SELECT * FROM pg_settings WHERE name like 'auto_explain%';

    diff -wu ${__TMP%/}/postgresql.conf.orig ${_postgresql_conf}
    if ${_restart} || ! ${_psql_as_admin} -d template1 -c "SELECT pg_reload_conf();"; then
        _log "INFO" "Updated postgresql config. Please restart or reload the service."
    fi
}

function _postresql_replication_common() {
    # @see: https://www.percona.com/blog/setting-up-streaming-replication-postgresql/
    # @see: bash/archives/build-dev-server.sh:2398
    local _db_data_dir="${1}"
    # At least 10GB disk space for now
    if ! _isEnoughDisk "${_db_data_dir}" "10"; then
        _log "WARN" "Not enough disk space. Please fix this later."
    fi
}

function _postresql_replication_primary() {
    local __doc__="Update postgresql.conf for primary server. Need to run from the PostgreSQL server (localhost)"
    # @see: bash/archives/build-dev-server.sh:2472
    local _db_data_dir="${1}"

    # Create user, update pg_hba.conf, and reload
    _psql_adm "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'replicator'" || return $?
}

function _postresql_replication_standby() {
    local __doc__="TODO: Update postgresql.conf for standby server. Need to run from the PostgreSQL server (localhost)"
    # @see: bash/archives/build-dev-server.sh:2520
    local _primary_host="${1}"
    local _primary_port="${2:-"5432"}"
    local _wal_archive_dir="${3}"   # Automatically decided if empty
    local _postgresql_conf="${4}"   # Automatically detected if empty. "/var/lib/pgsql/data" or "/etc/postgresql/10/main" or /var/lib/pgsql/12/data/
    local _port=""

    #Expecting the below command are running in a container crated by:
    # docker run -d -p 15432:5432 --name pgstandby -e POSTGRES_PASSWORD=postgres postgres:14
    _postresql_replication_common "${_db_data_dir}"

    # TODO: Copy the primary's data directory to the standby server
    #pg_basebackup -h ${_primary_host} -D /var/lib/postgresql/16/main/ -U replicator -P -v -R -X stream -C -S slaveslot1
}

function _postresql_configure_ssl() {
    local _cert_dir="$1"
    local _postgresql_conf="${2}"
    local _port="${3:-"5432"}"      # just for deciding the username. Optional.
    if [ ! -f "${_postgresql_conf}" ]; then
        _postgresql_conf="$(_as_dbadmin psql -tAc 'SHOW config_file')" || return $?
    fi
    if [ -z "${_postgresql_conf}" ] || [ ! -s "${_postgresql_conf}" ]; then
        _log "ERROR" "No postgresql config file specified."
        return 1
    fi
    if [ ! -d "${_cert_dir}" ]; then
        mkdir -p "${_cert_dir}" || return $?
    fi
    _cert_dir="$(readlink -f "${_cert_dir}")"
    if [ ! -s "${_cert_dir%/}/server.key" ]; then
        # https://www.cherryservers.com/blog/how-to-configure-ssl-on-postgresql
        openssl genrsa -passout "pass:admin123" -out ${_cert_dir%/}/server.key 2048 || return $?
        openssl rsa -in ${_cert_dir%/}/server.key -passin "pass:admin123" -out ${_cert_dir%/}/server.key || return $?
        # NOTE: .key file may need to be owned by postgres and key file permission needs to be 0400 or 0600
        chmod 400 ${_cert_dir%/}/server.key
        openssl req -x509 -new -key ${_cert_dir%/}/server.key -days 3650 -out ${_cert_dir%/}/server.crt -subj "/CN=$(hostname -f)" || return $?
        #cp -f -v server.crt root.crt
    fi
    # SSL / client certificate authentication https://smallstep.com/hello-mtls/doc/combined/postgresql/psql
    _psql_adm "ALTER SYSTEM SET ssl TO 'on'"
    _psql_adm "ALTER SYSTEM SET ssl_key_file TO '$(readlink -f "${_cert_dir%/}/server.key")'"
    _psql_adm "ALTER SYSTEM SET ssl_cert_file TO '$(readlink -f "${_cert_dir%/}/server.crt")'"
    _psql_adm "ALTER SYSTEM SET ssl_ca_file TO '$(readlink -f "${_cert_dir%/}/server.crt")'"
    # NOTE: (Optional) modify pg_hba.conf (SELECT setting FROM pg_settings WHERE name like '%pg_hba%';)
    #   hostssl all nexus 0.0.0.0/0 md5 clientcert=1
    # NOTE: also it seems restart is required
    # To test: echo | openssl s_client -starttls postgres -connect localhost:5432 -state #-debug
}

function _postgresql_create_dbuser() {
    local __doc__="Create DB user/role and database/schema and update pg_hba.conf. Need to run from the PostgreSQL server (localhost)"
    local _dbusr="${1}"
    local _dbpwd="${2:-"${_dbusr}"}"
    local _dbname="${3-"${_dbusr}"}"    # accept "" (empty string), then 'all' database is allowed
    local _schema="${4}"
    local _port="${6:-"5432"}"
    local _force="${7-"${_RECREATE_DB}"}"

    local _pg_hba_conf="$(_psql_adm "SHOW hba_file" "-tA")"
    if [ -z "${_pg_hba_conf}" ]; then
        _log "WARN" "No pg_hba.conf (${_pg_hba_conf}) found."
        return 1
    fi
    if [ -z "${_dbname}" ]; then
        _log "WARN" "No _dbname specified, which will allow ${_dbusr} to access 'all' database."
        sleep 3
    fi

    # NOTE: Use 'hostssl all all 0.0.0.0/0 cert clientcert=1' for 2-way | client certificate authentication
    #       To do that, also need to utilise database.parameters.some_key:value in config.yml
    local _sudo="${_CMD_PREFIX}"
    # If local file, edit as DB admin user
    if [ -z "${_CMD_PREFIX}" ] && [ ! -w "${_pg_hba_conf}" ]; then
        _sudo="sudo -u ${_DB_ADMIN} -i"
    fi
    if ! ${_sudo} grep -E "host\s+(${_dbname:-"all"}|all)\s+${_dbusr}\s+" "${_pg_hba_conf}"; then
        ${_sudo} bash -c "echo \"host ${_dbname:-"all"} ${_dbusr} 0.0.0.0/0 md5\" >> \"${_pg_hba_conf}\"" || return $?
        _psql_adm "SELECT pg_reload_conf()" || return $?
        #_as_dbadmin "psql -tAc \"SELECT pg_read_file('pg_hba.conf');\""
        _psql_adm "select * from pg_hba_file_rules where database = '{${_dbname:-"all"}}' and user_name = '{${_dbusr}}'" "-tA"
    fi

    [ "${_dbusr}" == "all" ] && return 0    # not creating user 'all'
    _log "INFO" "Creating Role:${_dbusr} and Database:${_dbname} ..."
    _postgresql_create_role_and_db "${_dbusr}" "${_dbpwd}" "${_dbname}" "${_schema}" "${_DB_ADMIN}" "${_port}" "${_force}"
}

function _postgresql_create_role_and_db() {
    local __doc__="Create DB user/role and database/schema (no pg_hba.conf update)"
    local _dbusr="${1}" # new DB user
    local _dbpwd="${2:-"${_dbusr}"}"
    local _dbname="${3-"${_dbusr}"}"    # If explicitly "", not creating DB but user/role only
    local _schema="${4}"
    local _port="${5:-"5432"}"
    local _force="${6-"${_RECREATE_DB}"}"

    # NOTE: need to be superuser. 'usename' (no 'r') is correct. options: -t --tuples-only, -A --no-align, -F --field-separator
    #       Also, double-quote for case sensitivity but not using for now.
    _psql_adm "SELECT usename FROM pg_shadow" "-tA" | grep -q "^${_dbusr}$" || _psql_adm "CREATE USER \"${_dbusr}\" WITH LOGIN PASSWORD '${_dbpwd}';"    # not giving SUPERUSER
    if [ "${_DB_ADMIN}" != "postgres" ] && [ "${_DB_ADMIN}" != "$USER" ]; then
        # NOTE: This ${_DB_ADMIN%@*} is for Azure
        _psql_adm "GRANT \"${_dbusr}\" TO \"${_DB_ADMIN%@*}\";"
    fi

    if [ -n "${_dbname}" ]; then
        local _create_db=true
        if _as_dbadmin psql -d template1 -ltA  -F',' | grep -q "^${_dbname},"; then
            if [[ "${_force}" =~ ^[yY] ]]; then
                _log "WARN" "${_dbname} already exists. As force is specified, dropping ${_dbname} ..."
                sleep 5
                _psql_adm "DROP DATABASE \"${_dbname}\";"
            else
                _log "WARN" "${_dbname} already exists. May need to run below first (or _RECREATE_DB=Y):
                psql -d ${_dbname} -c \"DROP SCHEMA ${_schema:-"public"} CASCADE;CREATE SCHEMA ${_schema:-"public"} AUTHORIZATION ${_dbusr};GRANT ALL ON SCHEMA ${_schema:-"public"} TO ${_dbusr};\""
                sleep 3
                _create_db=false
            fi
        fi
        if ${_create_db}; then
            # NOTE: to copy a database locally 'WITH TEMPLATE another_db OWNER ${_dbusr}'
            _psql_adm "CREATE DATABASE \"${_dbname}\" WITH OWNER \"${_dbusr}\" ENCODING 'UTF8';"
        else
            _psql_adm "GRANT ALL ON DATABASE \"${_dbname}\" TO \"${_dbusr}\";" >/dev/null || return $?
        fi
        # NOTE: For postgresql v15 change.
        _as_dbadmin psql -d ${_dbname} -c "GRANT ALL ON SCHEMA public TO \"${_dbusr}\";" >/dev/null
        # To delete user: DROP OWNED BY ${_dbusr}; DROP USER ${_dbusr};

        if [ -n "${_schema}" ]; then
            local _search_path="${_dbusr},public"
            for _s in ${_schema}; do
                _as_dbadmin psql -d ${_dbname} -c "CREATE SCHEMA IF NOT EXISTS ${_s} AUTHORIZATION ${_dbusr};"
                _search_path="${_search_path},${_s}"
            done
            _psql_adm "ALTER ROLE ${_dbusr} SET search_path = ${_search_path};"
        fi
    fi

    # test
    local _cmd="psql -h $(hostname -f) -p 5432 -U ${_dbusr} -d ${_dbname} -c \"\l ${_dbname}\""
    _log "INFO" "Testing the connection with \"${_cmd}\" ..."
    eval "${_CMD_PREFIX} PGPASSWORD=\"${_dbpwd}\" ${_cmd}" || return $?
}

function _postgres_pitr() {
    local __doc__="Point In Time Recovery for PostgreSQL *12* (not tested with other versions). Need to run from the PostgreSQL server (localhost)"
    # @see: https://www.postgresql.org/docs/12/continuous-archiving.html#BACKUP-PITR-RECOVERY
    # NOTE: this function doesn't do any assumption. almost all arguments need to be specified.
    local _data_dir="${1}"              # /var/lib/pgsql/data, /var/lib/pgsql/12/data or /usr/local/var/postgres (Mac)
    local _base_backup_tgz="${2}"       # File path. eg: .../node-nxiq1960_base_20201105T091218z/base.tar.gz
    local _wal_archive_dir="${3}"       # ${_WORK_DIR%/}/${_SERVICE%/}/backups/`hostname -s`_wal
    local _target_ISO_datetime="${4}"   # yyyy-mm-dd hh:mm:ss (optional)
    local _port="${5:-"5432"}"          # PostgreSQL port number (optional)

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
    sudo -u ${_DB_ADMIN} -i mkdir -m 700 -p ${_data_dir%/} || return $?
    tar -xvf "${_base_backup_tgz}" -C "${_data_dir%/}" || return $?
    sudo -u ${_DB_ADMIN} -i touch ${_data_dir%/}/recovery.signal || return $?
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
    # NOTE: Do not use superuser to restore, specify -U ${_dbusr} instead.
    #PGPASSWORD="${_dbpwd}" pg_restore -U ${_dbusr} -d ${_dbname} --jobs=3 --no-owner --disable-triggers --superuser $USER --verbose ${_dump_filepath}
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
    local __doc__="Deprecated: Copy database with 'pg_dump | psql'"
    # CREATE DATABASE newDbName WITH TEMPLATE srcDbName OWNER ownerName;
    local _local_src_db="${1}"
    local _dbusr="${2:-"$USER"}"
    local _dbpwd="${3:-"${_dbusr}"}"
    local _dbname="${4:-"${_dbusr}"}"
    #local _schema="${5}"    # psql ... -n "${_schema}"
    local _dbhost="${5:-"${_DBHOST:-"localhost"}"}"
    local _dbport="${6:-"${_DBPORT:-"5432"}"}"

    _as_dbadmin pg_dump -d "${_local_src_db}" -c -O | PGPASSWORD="${_dbpwd}" psql -h ${_dbhost} -p ${_dbport} -U ${_dbusr} -d ${_dbname}
}