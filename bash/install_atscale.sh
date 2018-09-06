#!/usr/bin/env bash
usage() {
    cat << END
A sample bash script for setting up and installing atscale
Tested on CentOS6|CentOS7 against hadoop clusters (HDP)

Download:
  mkdir -p -m 777 /var/tmp/share/atscale
  curl https://raw.githubusercontent.com/hajimeo/samples/master/bash/install_atscale.sh -o /var/tmp/share/atscale/install_atscale.sh

To see help message of a function:
   $0 -h <function_name>

END
    # My NOTE:
    # Restore dir when install failed in the middle of installation:
    #   rmdir /usr/local/atscale && mv /usr/local/atscale_${_ATSCALE_VER}.*_$(date +"%Y%m%d")* /usr/local/atscale
    #
    #   $exec_dir             = File.realpath(File.dirname(__FILE__) + '/../..')
    #   $custom_yaml_file     = $exec_dir + '/custom.yaml'
}


### Global variables #################
[ -z "${_HDFS_USER}" ] && _HDFS_USER="hdfs"                     # Used to create a hdfs directory for atscale user
[ -z "${_KADMIN_USR}" ] && _KADMIN_USR="admin/admin"            # Used to create atscale service principal
[ -z "${_DEFAULT_PWD}" ] && _DEFAULT_PWD="hadoop"               # kadmin password, hive metastore DB password etc.
[ -z "${_ATSCALE_DIR}" ] && _ATSCALE_DIR="/usr/local/atscale"   # AtScale installing directory path
[ -z "${_TMP_DIR}" ] && _TMP_DIR="/var/tmp/share/atscale"       # Temp/work directory to store various data, such as installer.tar.gz
[ -z "${_OS_ARCH}" ] && _OS_ARCH="el6.x86_64"                   # OS+Architecture strings used in installer file name
[ -z "${_KEYTAB_DIR}" ] && _KEYTAB_DIR="/etc/security/keytabs"  # Keytab default location (this is the default for HDP)
#[ -z "${_SCHEMA_AND_HDFSDIR}" ] && _SCHEMA_AND_HDFSDIR=""      # NOTE: This is intentional as this needs to be empty


### Arguments ########################
[ -z "${_ATSCALE_VER}" ] && _ATSCALE_VER="${1:-7.1.0}"          # AtScale version mainly used to find the right installer file
[ -z "${_ATSCALE_USER}" ] && _ATSCALE_USER="${2:-atscale}"      # AtScale service user
[ -z "${_ATSCALE_LICENSE}" ] && _ATSCALE_LICENSE="${3:-${_TMP_DIR}/dev-vm-license-atscale.json}"
[ -z "${_ATSCALE_CUSTOMYAML}" ] && _ATSCALE_CUSTOMYAML="${4}"   # Path to custom.yaml file. If empty, automatically generated
[ -z "${_UPDATING}" ] && _UPDATING="${5}"                       # Upgrading & Updating (means re-running installer to update some properties)
[ -z "${_NO_BACKUP}" ] && _NO_BACKUP="${6}"                     # As back up takes time, if you are really sure, you can skip taking backup


### Functions ########################
function f_setup() {
    local __doc__="Setup OS and hadoop to install AtScale (eg: create a user)"
    # f_setup atscale /usr/local/atscale /var/tmp/share/atscale atscale$$
    local _user="${1:-${_ATSCALE_USER}}"
    local _target_dir="${2:-${_ATSCALE_DIR}}"
    local _tmp_dir="${3:-${_TMP_DIR}}"
    local _schema="${4:-${_SCHEMA_AND_HDFSDIR}}"
    local _kadmin_usr="${5:-${_KADMIN_USR}}"
    local _kadmin_pwd="${6:-${_DEFAULT_PWD}}"
    local _is_updating="${7-${_UPDATING}}"

    local _hdfs_user="${_HDFS_USER:-hdfs}"

    if [ ! -d "${_tmp_dir}" ]; then
        _log "WARN" "${_tmp_dir} does not exist. Try creating it..."; sleep 3
        mkdir -m 777 -p ${_tmp_dir} || return $?
    fi
    chmod 777 ${_tmp_dir}

    _log "TODO" "Please run 'adduser ${_user}' on other hadoop nodes"; sleep 3
    adduser ${_user} &>/dev/null
    usermod -a -G hadoop ${_user} &>/dev/null

    if [ ! -d "${_target_dir}" ]; then
        mkdir -p "${_target_dir}" || return $?
        chown ${_user}: "${_target_dir}" || return $?
    fi

    # If looks like Kerberos is enabled
    if grep -A 1 'hadoop.security.authentication' /etc/hadoop/conf/core-site.xml | grep -qw "kerberos"; then
        if ! grep -qF "hadoop.proxyuser.${_user}" /etc/hadoop/conf/core-site.xml; then
            _log "WARN" "Please check hadoop.proxyuser.${_user}.hosts and groups in core-site."; sleep 3
        fi
        if [ ! -s ${_KEYTAB_DIR%/}/${_user}.service.keytab ]; then
            _log "INFO" "Creating principals and keytabs (TODO: only for MIT KDC)..."; sleep 1
            if [ -z "${_kadmin_usr}" ]; then
                _log "WARN" "_KADMIN_USR is not set, so that NOT creating ${_user} principal."; sleep 3
            else
                # If FreeIPA
                if which ipa &>/dev/null; then
                    local _def_realm="`sed -nr 's/^\s*default_realm\s*=\s(.+)/\1/p' /etc/krb5.conf`"
                    local _kdc="`grep -Pzo '(?s)^\s*'${_def_realm}'\s*=\s*\{.+\}' /etc/krb5.conf | sed -nr 's/\s*kdc\s*=\s*(.+)/\1/p'`"
                    if [ -n "${_kdc}" ]; then
                        _log "INFO" "Looks like ipa is used. Please type 'admin' user password"; sleep 1
                        #echo -n "${_kadmin_pwd}" | kinit ${_kadmin_usr}
                        kinit admin
                        #ipa service-add ${_atscale_user}/`hostname -f`   # TODO: Bug? https://bugzilla.redhat.com/show_bug.cgi?id=1602410
                        ipa-getkeytab -s ${_kdc} -p ${_user}/`hostname -f` -k ${_KEYTAB_DIR%/}/${_user}.service.keytab
                        # NOTE: for user keytab, append --password or -P
                        #ipa-getkeytab -s ${_kdc} -p ${_user} -f` -k ${_KEYTAB_DIR%/}/${_user}.service.keytab -P
                    fi
                    if [ $? -ne 0 ]; then
                        _log "ERROR" "If FreeIPA is used, please create SPN: ${_user}/`hostname -f` from your FreeIPA GUI and export keytab."; sleep 5
                    fi
                else
                    kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "add_principal -randkey ${_user}/`hostname -f`" && \
                    kadmin -p ${_kadmin_usr} -w ${_kadmin_pwd} -q "xst -k ${_KEYTAB_DIR%/}/${_user}.service.keytab ${_user}/`hostname -f`"
                fi
                chown ${_user}: ${_KEYTAB_DIR%/}/${_user}.service.keytab
                chmod 640 ${_KEYTAB_DIR%/}/${_user}.service.keytab
            fi
        fi

        local _atscale_principal="`klist -k ${_KEYTAB_DIR%/}/${_user}.service.keytab | grep -oE -m1 "${_user}/$(hostname -f)@.+$"`"
        sudo -u ${_user} kinit -kt ${_KEYTAB_DIR%/}/${_user}.service.keytab ${_atscale_principal} || return $?
    fi

    if [[ "${_is_updating}" =~ (^y|^Y) ]]; then
        _log "INFO" "Updating (Upgrading) is selected, so that not creating a HDFS dir and Hive schema"; sleep 1
    else
        # Assuming hive client installed
        local _zk_quorum="$(_get_from_xml "/etc/hive/conf/hive-site.xml" "hive.zookeeper.quorum")"
        sudo -u ${_user} beeline -u "jdbc:hive2://${_zk_quorum}/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2" -n ${_user} -e "CREATE DATABASE IF NOT EXISTS ${_schema}" || return $?

        if [ -s ${_KEYTAB_DIR%/}/hdfs.headless.keytab ]; then
            local _hdfs_principal="`klist -k ${_KEYTAB_DIR%/}/hdfs.headless.keytab | grep -oE -m1 'hdfs-.+$'`"
            sudo -u ${_hdfs_user} kinit -kt ${_KEYTAB_DIR%/}/hdfs.headless.keytab ${_hdfs_principal}
        fi
        sudo -u ${_hdfs_user} hdfs dfs -mkdir /user/${_user}
        sudo -u ${_hdfs_user} hdfs dfs -chown ${_user}: /user/${_user}
    fi

    # Running yum in here so that above hive command might finish before yum completes.
    yum install -e 0 -y bzip2 bzip2-libs curl rsync unzip || return $?

    # Optionals: Not important if fails
    ln -s /etc/krb5.conf /etc/krb5_atscale.conf &>/dev/null
    su - ${_user} -c 'grep -q '${_target_dir%/}' $HOME/.bash_profile || echo -e "\nexport PATH=${PATH%:}:'${_target_dir%/}'/bin" >> $HOME/.bash_profile'
    [ -s ${_KEYTAB_DIR%/}/${_user}.service.keytab ] && ( su - ${_user} -c 'grep -q '${_KEYTAB_DIR%/}/${_user}.service.keytab' $HOME/.bash_profile || echo -e "\nkinit -kt '${_KEYTAB_DIR%/}'/'${_user}'.service.keytab '${_user}'/`hostname -f` &>/dev/null &" >> $HOME/.bash_profile' )
    [ ! -d /var/log/atscale ] && ln -s ${_target_dir%/}/log /var/log/atscale &>/dev/null
    #[ -d /var/www/html ] && [ ! -e /var/www/html/atscale ] && ln -s ${_TMP_DIR%/} /var/www/html/atscale &>/dev/null

    return 0
}

function todo_delegation() {
    local _rule_name="${1:-atscalesrvda}"
    local _adm_pass="${2:-secret12}"
    local _hdp_host="${3:-`hostname -f`}"    # Currently expecting hive and hdfs are installed in one node

    echo -n "${_adm_pass}" | kinit admin
    ipa servicedelegationrule-add ${_rule_name}
    ipa servicedelegationtarget-add target-${_rule_name}
    ipa servicedelegationrule-add-target --servicedelegationtargets=target-${_rule_name} ${_rule_name}

    local _atscale_princ="`ipa service-find atscale | sed -nr 's/\s*Principal name: (.+)/\1/p'`"
    ipa servicedelegationrule-add-member --principals ${_atscale_princ} ${_rule_name}

    for _spn in `ipa service-find --man-by-hosts ${_hdp_host} | grep -i 'Keytab: True' -B 2 | sed -nr 's/\s*Principal name: (.+)/\1/p'`; do
        ipa servicedelegationtarget-add-member --principals=${_spn} target-${_rule_name}
    done

    ipa servicedelegationrule-show ${_rule_name}
    ipa servicedelegationtarget-show target-${_rule_name}
    # TODO: delegation         Group to Group Delegation ???
}

function f_setup_scala() {
    local __doc__="Download scala and setup"
    local _ver="${1:-2.12.3}"
    local _tmp_dir="${2:-${_TMP_DIR}}"
    local _inst_dir="${3:-/usr/local/scala}"

    if [ ! -d "${_tmp_dir%/}/scala-${_ver}" ]; then
        if [ ! -s "${_tmp_dir%/}/scala-${_ver}.tgz" ]; then
            curl --retry 3 -C - -o "${_tmp_dir%/}/scala-${_ver}.tgz" "https://downloads.lightbend.com/scala/${_ver}/scala-${_ver}.tgz" || return $?
        fi
        tar -xf "${_tmp_dir%/}/scala-${_ver}.tgz" -C "${_tmp_dir%/}/" || return $?
        chmod a+x ${_inst_dir%/}/bin/*
    fi

    [ -d "${_inst_dir%/}" ] || ln -s "${_tmp_dir%/}/scala-${_ver}" "${_inst_dir%/}"

    if ! grep -q 'export SCALA_HOME' /etc/profile; then
        echo -e '\nexport SCALA_HOME='${_inst_dir%/}'\nexport PATH=$PATH:$SCALA_HOME/bin' >> /etc/profile
    fi

    export SCALA_HOME=${_inst_dir%/}
    export PATH=$PATH:$SCALA_HOME/bin
}

function f_java_envs() {
    local __doc__="Export JAVA_HOME and CLASSPATH by using port number"
    local _port="${1:-10502}"
    local _dir="${2:-${_ATSCALE_DIR}}"

    local _p=`lsof -ti:${_port}`
    if [ -z "${_p}" ]; then
        echo "Nothing running on port ${_port}"
        return 11
    fi
    local _user="`stat -c '%U' /proc/${_p}`"
    export JAVA_HOME="$(ls -1d ${_dir%/}/share/jdk*| head -n1)" # not expecting more than one dir
    export CLASSPATH=".:`sudo -u ${_user} $JAVA_HOME/bin/jcmd ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"   #:`hadoop classpath`
}

function f_generate_custom_yaml() {
    local __doc__="Generate custom yaml"
    local _license_file="${1:-${_ATSCALE_LICENSE}}"
    local _usr="${2:-${_ATSCALE_USER}}"
    local _schema_and_hdfsdir="${3:-${_SCHEMA_AND_HDFSDIR}}"
    local _installer_parent_dir="${4:-/home/${_usr}}"

    # TODO: currently only for HDP
    local _tmp_yaml=/tmp/custom_hdp.yaml
    curl -s --retry 3 -o ${_tmp_yaml} "https://raw.githubusercontent.com/hajimeo/samples/master/misc/custom_hdp.yaml" || return $?

    # expected variables
    local _atscale_host="`hostname -f`" || return $?
    if [ ! -s "${_license_file}" ]; then
        _log "ERROR" "No ${_license_file}"; sleep 5
        return 11
    fi
    local _default_schema="${_schema_and_hdfsdir}"
    local _hdfs_root_dir="/user/${_usr}/${_schema_and_hdfsdir}"
    local _hdp_version="`hdp-select versions | tail -n 1`" || return $?
    local _hdp_major_version="`echo ${_hdp_version} | grep -oP '^\d\.\d+'`" || return $?
    #/usr/hdp/%hdp_version%/hadoop/conf:/usr/hdp/%hdp_version%/hadoop/lib/*:/usr/hdp/%hdp_version%/hadoop/.//*:/usr/hdp/%hdp_version%/hadoop-hdfs/./:/usr/hdp/%hdp_version%/hadoop-hdfs/lib/*:/usr/hdp/%hdp_version%/hadoop-hdfs/.//*:/usr/hdp/%hdp_version%/hadoop-yarn/lib/*:/usr/hdp/%hdp_version%/hadoop-yarn/.//*:/usr/hdp/%hdp_version%/hadoop-mapreduce/lib/*:/usr/hdp/%hdp_version%/hadoop-mapreduce/.//*::mysql-connector-java.jar:/usr/hdp/%hdp_version%/tez/*:/usr/hdp/%hdp_version%/tez/lib/*:/usr/hdp/%hdp_version%/tez/conf
    local _hadoop_classpath="`hadoop classpath`" || return $?

    # Kerberos related, decided by atscale keytab file
    local _is_kerberized="false"
    local _delegated_auth_enabled="false"
    local _realm="EXAMPLE.COM"
    local _hadoop_realm="EXAMPLE.COM"
    local _hdfs_principal="hdfs"
    local _hive_metastore_database="false"
    local _hive_metastore_password="<empty>"

    if [ -s ${_KEYTAB_DIR%/}/atscale.service.keytab ]; then
        _is_kerberized="true"
        #_delegated_auth_enabled="true"       # Default on 7.0.0 is false
        #_hive_metastore_database="true"      # Using remote metastore causes Kerberos issues, however this one update metastore version "Set by MetaStore UNKNOWN@172.17.100.6"
        #_hive_metastore_password="${_DEFAULT_PWD}"   # TODO: static password...
        _realm=`sudo -u ${_usr} klist -kt ${_KEYTAB_DIR%/}/atscale.service.keytab | grep -m1 -oP '@.+' | sed 's/@//'` || return $?
        # TODO: expecting this node has hdfs headless keytab and readable by root (it should though)
        _hadoop_realm=`klist -kt ${_KEYTAB_DIR%/}/hdfs.headless.keytab | grep -m1 -oP '@.+' | sed 's/@//'`
        [ -z "${_hadoop_realm}" ] && _hadoop_realm="${_realm}"
        _hdfs_principal=`klist -kt ${_KEYTAB_DIR%/}/hdfs.headless.keytab | grep -m1 -oP 'hdfs-.+@' | sed 's/@//'`
        [ -z "${_hdfs_principal}" ] && _hdfs_principal="hdfs"
    fi

    for _v in atscale_host license_file default_schema hdfs_root_dir hdp_version hdp_major_version hadoop_classpath is_kerberized delegated_auth_enabled hive_metastore_database hive_metastore_password hadoop_realm realm hdfs_principal; do
        local _v2="_"${_v}
        # TODO: some variable contains "/" so at this moment using "@" but not perfect
        sed -i "s@%${_v}%@${!_v2}@g" $_tmp_yaml || return $?
    done

    if [ -d "${_installer_parent_dir}" ]; then
        if [ -f ${_installer_parent_dir%/}/custom.yaml ]; then
            mv -f ${_installer_parent_dir%/}/custom.yaml ${_installer_parent_dir%/}/custom.yaml_$(date +"%Y%m%d%H%M%S") || return $?
        fi
        # CentOS seems to have an alias of "cp -i"
        mv -f ${_tmp_yaml} ${_installer_parent_dir%/}/custom.yaml && chown ${_usr}: ${_installer_parent_dir%/}/custom.yaml
    fi
}

_change_key_value_in_file() {
  local filename=$1
  local key=$2
  local new_value=$3

  if [ $(grep -c "^\s*${key}:" ${filename}) -eq 0 ]; then
    # append new_value if it's not already present in file
    echo "${key}: ${new_value}" >> ${filename}
  else
    # otherwise replace the current value with new_value
    sed -i -e 's/^\('${key}':\)\(\s*\)\(.*\)/\1 '${new_value}'/' ${filename}
  fi
}

function f_atscale_backup() {
    local __doc__="Backup atscale directory, *excluding* log files"
    local _dir="${1:-${_ATSCALE_DIR}}"
    local _usr="${2:-${_ATSCALE_USER}}"
    local _dst_dir="${3:-${_TMP_DIR}}"
    local _using_pg_dump="${4}"
    local _using_tar="${5}"

    [ -d ${_dir%/} ] || return    # No dir, no backup

    local _suffix="`_get_suffix`"

    if [[ "${_using_pg_dump}" =~ (^y|^Y) ]]; then
        if [ -s "${_TMP_DIR%/}/atscale_${_suffix}.sql.gz" ]; then
            _log "WARN" "No pg_dump as ${_TMP_DIR%/}/atscale_${_suffix}.sql.gz already exists."; sleep 3
        else
            sudo -u ${_usr} "${_dir%/}/bin/atscale_service_control" start postgres ; sleep 5
            f_pg_dump "${_TMP_DIR%/}/atscale_${_suffix}.sql.gz" "${_dir%/}/share/postgresql-9.*/"
            if [ ! -s "${_TMP_DIR%/}/atscale_${_suffix}.sql.gz" ]; then
                _log "WARN" "Failed to take DB dump into ${_TMP_DIR%/}/atscale_${_suffix}.sql.gz. Maybe PostgreSQL is stopped?"; sleep 3
            fi
        fi
    fi

    local _days=3
    _log "INFO" "Deleting log files which are older than ${_days} days..."; sleep 1
    f_rm_logs "${_dir}" "${_days}"

    _log "INFO" "Stopping AtScale before backing up..."; sleep 1
    f_atscale_stop "${_dir}" "${_usr}"  || return $?

    # Best effort of backing up custom.yaml (note: config_debug.yaml doesn't look like updated)
    if [ -s "/home/${_usr%/}/custom.yaml" ] && [ ! -e "${_dir%/}/custom_${_suffix}.yaml" ]; then
        cp -p -f "/home/${_usr%/}/custom.yaml" ${_dir%/}/custom_${_suffix}.yaml
    fi

    local _backup_filename="atscale_$(hostname -f)_${_suffix}"
    cd `dirname ${_dir}` || return $?   # Need 'cd' for creating exclude list (-X) as -C didn't work
    ls -1 `basename ${_dir%/}`/log/*{.stdout,/*.log,/*.log.gz} 2>/dev/null > /tmp/f_atscale_backup_exclude_files_$$.out
    ls -1 `basename ${_dir%/}`/share/postgresql-*/data/pg_log/* 2>/dev/null >> /tmp/f_atscale_backup_exclude_files_$$.out

    if which rsync &>/dev/null && [[ ! "${_using_tar}" =~ (^y|^Y) ]]; then
        _log "INFO" "Rsync to ${_dst_dir%/}/${_backup_filename} from ${_dir} Excluding log files ..."; sleep 1
        if [ ! -d "${_dst_dir%/}/${_backup_filename}" ]; then mkdir -p ${_dst_dir%/}/${_backup_filename} || return $?; fi
        rsync -a --modify-window=1 --exclude-from=/tmp/f_atscale_backup_exclude_files_$$.out `basename ${_dir%/}`/* ${_dst_dir%/}/${_backup_filename%/}/ || return $?
        [ 2048 -lt "`du -s ${_dst_dir%/}/${_backup_filename%/} | awk '{print $1}'`" ] || return 18
        du -sh ${_dst_dir%/}/${_backup_filename%/}
    else
        _log "INFO" "Creating ${_dst_dir%/}/${_backup_filename}.tgz from ${_dir%/} Excluding log files ..."; sleep 1
        [ -s "${_dst_dir%/}/${_backup_filename}.tgz" ] && [ ! -s ${_dst_dir%/}/${_backup_filename}_$$.tgz ] && mv -f ${_dst_dir%/}/${_backup_filename}.tgz ${_dst_dir%/}/${_backup_filename}_$$.tgz &>/dev/null
        tar -chzf ${_dst_dir%/}/${_backup_filename}.tgz "`basename ${_dir%/}`" -X /tmp/f_atscale_backup_exclude_files_$$.out
        [ 2097152 -lt "`wc -c <${_dst_dir%/}/${_backup_filename}.tgz`" ] || return 19
        ls -lh ${_dst_dir%/}/${_backup_filename}.tgz
    fi
    cd -
    _log "INFO" "To start AtScale: sudo -u ${_usr} ${_dir%/}/bin/atscale_start"
}

function f_atscale_restore() {
    local __doc__="Restore AtScale from a backup taken from f_backup_atscale()"
    local _backup="$1"
    local _dir="${2:-${_ATSCALE_DIR}}"
    local _usr="${3:-${_ATSCALE_USER}}"
    local _tmp_dir=""

    if [ ! -d "${_backup}" ]; then
        _tmp_dir="$(mktemp -d)" || return $?
        _log "INFO" "Extracting ${_backup} in ${_tmp_dir%/}/ ..."; sleep 1
        tar xf ${_backup} -C ${_tmp_dir%/}/ || return $?
    fi

    _log "INFO" "Stopping AtScale before restoring..."; sleep 1
    f_atscale_stop "${_dir}" "${_usr}" || return $?

    # making backup
    local _suffix="`_get_suffix`"
    [ -e ${_dir%/}_${_suffix} ] && [ ! -e ${_dir%/}_${_suffix}_$$ ] && mv ${_dir%/}_${_suffix} ${_dir%/}_${_suffix}_$$
    if [ -e ${_dir%/} ]; then mv ${_dir%/} ${_dir%/}_${_suffix} || return $?; fi

    if [ -n "${_tmp_dir%/}" ]; then
        mv "${_tmp_dir%/}/`basename ${_dir%/}`" "`dirname ${_dir%/}`/" || return $?
    else
        mv "${_backup%/}" "${_dir%/}" || return $?
    fi
    ls -ld ${_dir%/}*
}

function _get_version() {
    local _dir="${1:-${_ATSCALE_DIR}}"
    grep -q "^as_version:" ${_dir%/}/conf/versions/versions.*.yml 2>/dev/null || return 1
    local _ver="$(sed -n 's/^as_version: *\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' "`ls -1 ${_dir%/}/conf/versions/versions.*.yml | tail -n1`")"
    echo "${_ver}"
}

function _get_suffix() {
    local _ver="${1}"
    local _dir="${2:-${_ATSCALE_DIR}}"
    if [ -z "${_ver}" ]; then
        # NOTE: ${_dir%/}/conf/config_debug.yaml does not show the current version if it's upgraded
        _ver="`_get_version "${_dir}"`"
        [ -z "${_ver}" ] && _ver="000"    # means unknown
    fi
    # Removing dot as this will be used for database/schema name in hive
    echo "${_ver}_$(date +"%Y%m%d")" | sed 's/[^0-9_]//g'
}

function f_rm_logs() {
    local __doc__="Delete AtScale log and postgreSql log files"
    local _dir="${1:-${_ATSCALE_DIR}}"
    local _days="${2:-1}"
    [ -d "${_dir}" ] || return $?
    find ${_dir%/}/{log,share/postgresql-*/data/pg_log} -type f -and -mtime +${_days} -and \( -name "*.log.gz" -o -name "postgresql-2*.log" -o -name "*.stdout" \) -and -print0| xargs -0 -t -P3 -n1 -I {} rm -f {}
}

function f_pg_dump() {
    local __doc__="Execute atscale's pg_dump to backup PostgreSQL 'atscale' database"
    local _dump_dest_filename="${1:-./atscale_$(date +"%Y%m%d%H%M%S").sql.gz}"
    local _pg_dir="$(ls -1dt ${_ATSCALE_DIR%/}/share/postgresql-9.* | head -n1)"
    LD_LIBRARY_PATH=${_pg_dir%/}/lib PGPASSWORD=${PGPASSWORD:-atscale} ${_pg_dir%/}/bin/pg_dump -h localhost -p 10520 -U atscale -d atscale -Z 9 -f ${_dump_dest_filename} -v 1>&2 || return $?
    [ -s ${_dump_dest_filename} ] || return $?
    echo ""
    ls -lh ${_dump_dest_filename}
}

function f_pg_ctl() {
    local __doc__="pg_ctl wrapper function. Due to \$@, need env variable _ATSCALE_DIR and _ATSCALE_USER"
    local _pg_dir="$(ls -1dt ${_ATSCALE_DIR%/}/share/postgresql-9.* | head -n1)"
    sudo -u ${_ATSCALE_USER} LD_LIBRARY_PATH=${_pg_dir%/}/lib PGPASSWORD=${PGPASSWORD:-atscale} ${_pg_dir%/}/bin/pg_ctl -D ${_pg_dir%/}/data "$@"
}

function f_pg_restore() {
    local __doc__="Load .sql *text* file generated by pg_dump"
    local _sql="$1"
    [ -s "${_sql}" ] || return 1
    f_psql -d template1 -c "alter database atscale rename to atscale_"$(date +"%Y%m%d%H%M%S")";"
    f_psql -d template1 -c "create database atscale;"
    # NOTE: for custom format generated by AtScale's postgresql_dump
    #LD_LIBRARY_PATH=${_pg_dir%/}/lib PGPASSWORD=${PGPASSWORD:-atscale} ${_pg_dir%/}/bin/pg_restore -h localhost -p 10520 -U atscale -v -C -d atscale $_dump_file
    f_psql -d atscale < "${_sql}"
}

function f_psql() {
    local __doc__="psql wrapper function. Due to \$@, need env variable _ATSCALE_DIR"
    #f_psql -xc "select * from pg_settings where name ilike '%archive%' or name ilike '%wal\_%'"
    local _pg_dir="$(ls -1dt ${_ATSCALE_DIR%/}/share/postgresql-9.* | head -n1)"
    LD_LIBRARY_PATH=${_pg_dir%/}/lib PGPASSWORD=${PGPASSWORD:-atscale} ${_pg_dir%/}/bin/psql -h localhost -p 10520 -U atscale "$@"
}

function f_install_atscale() {
    local __doc__="Install AtScale software"
    local _version="${1:-${_ATSCALE_VER}}"
    local _license="${2:-${_ATSCALE_LICENSE}}"
    local _dir="${3:-${_ATSCALE_DIR}}"
    local _usr="${4:-${_ATSCALE_USER}}"
    local _custom_yaml="${5:-${_ATSCALE_CUSTOMYAML}}"
    local _installer_parent_dir="${6:-/home/${_usr}}"
    local _is_updating="${7-${_UPDATING}}"
    local _no_backup="${8-${_NO_BACKUP}}"

    # It should be created by f_setup when user is created, so exiting.
    [ -d "${_installer_parent_dir}" ] || return $?

    # If it looks like one installed already, trying to take a backup
    if [ -s "${_dir%/}/bin/atscale_service_control" ]; then
        if [[ "${_is_updating}}" =~ (^y|^Y) ]]; then
            if [[ ! "${_no_backup}}" =~ (^y|^Y) ]]; then
                _log "INFO" "Looks like another AtScale is already installed in ${_dir%/}/. Taking backup..."; sleep 1
                if ! f_atscale_backup; then     # NOTE: backup should stop AtScale
                    _log "ERROR" "Backup failed!!!"; sleep 5
                    return 1
                fi
            fi

            # If upgrading, making sure necessary services are started
            f_atscale_start ${_dir} ${_usr} || return $?
            sudo -u ${_usr} "${_dir%/}/bin/atscale_stop_apps" -f
            sleep 3
            sudo -u ${_usr} "${_dir%/}/bin/atscale_service_control" status
        else
           _log "INFO" "Looks like another AtScale is already installed in ${_dir%/}/. Moving this directory..."; sleep 1
            f_atscale_stop "${_dir}" "${_usr}" || return $?
            local _suffix="`_get_suffix`"
            [ -e ${_dir%/}_${_suffix} ] && [ ! -e ${_dir%/}_${_suffix}_$$ ] && mv ${_dir%/}_${_suffix} ${_dir%/}_${_suffix}_$$
            if [ -e ${_dir%/} ]; then mv ${_dir%/} ${_dir%/}_${_suffix} || return $?; fi
            mkdir ${_dir%/} || return $?
            chown ${_usr}: ${_dir%/} || return $?
            ls -ltrd ${_dir%/}* # Just displaying directories to remind to delete later.
        fi
    fi

    # NOTE: From here, all commands should be run as atscale user.
    if [ ! -d ${_installer_parent_dir%/}/atscale-${_version}.*-${_OS_ARCH} ]; then
        if [ ! -r "${_TMP_DIR%/}/atscale-${_version}.latest-${_OS_ARCH}.tar.gz" ]; then
            _log "INFO" "No ${_TMP_DIR%/}/atscale-${_version}.latest-${_OS_ARCH}.tar.gz. Downloading from internet..."; sleep 1
            #s3cmd ls s3://files.atscale.com/installer/package/ | grep -E 'atscale-[6789].+latest.+\.tar\.gz$'  # NOTE: https requires s3-us-west-1.amazonaws.com hostname
            sudo -u ${_usr} curl --retry 100 -C - -o ${_TMP_DIR%/}/atscale-${_version}.latest-${_OS_ARCH}.tar.gz "https://s3-us-west-1.amazonaws.com/files.atscale.com/installer/package/atscale-${_version}.latest-${_OS_ARCH}.tar.gz" || return $?
        fi

        sudo -u ${_usr} tar -xf ${_TMP_DIR%/}/atscale-${_version}.latest-${_OS_ARCH}.tar.gz -C ${_installer_parent_dir%/}/ || return $?
    fi

    # If some custom yaml is specified in the argument or _ATSCALE_CUSTOMYAML
    if [ -n "${_custom_yaml}" ]; then
        if [ ! -s "${_custom_yaml}" ]; then
            _log "ERROR" "${_custom_yaml} does not exist!!"; sleep 5
            return 1
        fi

        [ -s ${_installer_parent_dir%/}/custom.yaml ] && mv -f ${_installer_parent_dir%/}/custom.yaml ${_installer_parent_dir%/}/custom.yaml_$(date +"%Y%m%d%H%M%S")
        _log "INFO" "Copying ${_custom_yaml} to ${_installer_parent_dir%/}/custom.yaml ..."; sleep 1
        sudo -u ${_usr} cp -f "${_custom_yaml}" ${_installer_parent_dir%/}/custom.yaml || return $?
    fi

    if [[ "${_is_updating}}" =~ (^y|^Y) ]]; then
        # If upgrading, must put custom.yaml in correct location before starting installation
        if [ ! -s ${_installer_parent_dir%/}/custom.yaml ]; then
            _log "ERROR" "Upgrading is specified but no custom.yaml file!!!"; sleep 5
            return 1
        fi
    else
        if [ ! -n "${_custom_yaml}" ]; then
            _log "WARN" "As no custom.yaml specified (eg: _ATSCALE_CUSTOMYAML), generating new one..."; sleep 3
            f_generate_custom_yaml || return $?
        fi
    fi

    # installer needs to be run from this dir
    cd ${_installer_parent_dir%/}/atscale-${_version}.*-${_OS_ARCH}/ || return $?
    _log "INFO" "executing 'sudo -u ${_usr} ./bin/install -l ${_license}'"; sleep 1
    sudo -u ${_usr} ./bin/install -l ${_license}
    cd -

    local _last_log="`ls -t1 /home/atscale/log/install-20*.log | head -n1`"
    if [ -s "${_last_log}" ]; then
        cat "${_last_log}" | grep -v 'The yum provider can only be used as root' | grep '^Error:' && return 1
    fi
    return 0
}

function f_install_post_tasks() {
    local __doc__="Normal installation does not work well with HDP, so need to change a few"
    local _dir="${1:-${_ATSCALE_DIR}}"
    local _usr="${2:-${_ATSCALE_USER}}"
    local _installer_parent_dir="${3:-/home/${_usr}}"
    local _wh_name="${4:-defaultWH}"
    local _env_name="${5:-defaultEnv}"

    if [ -x "${_dir%/}/bin/atscale_start" ]; then
        grep -q 'atscale_start' /etc/rc.local || echo -e "\nsudo -u ${_usr} ${_dir%/}/bin/atscale_start" >> /etc/rc.local
    fi

    # TODO: I think below is needed if kerberos
    #${_dir%/}/apps/engine/bin/engine_wrapper.sh
    #export AS_ENGINE_EXTRA_CLASSPATH="config.ini:/etc/hadoop/conf/"

    _load_yaml ${_installer_parent_dir%/}/custom.yaml "inst_" || return $?

    local _hive_xml=${_dir%/}/share/apache-hive-*/conf/hive-site.xml
    local _spark_xml=${_dir%/}/share/spark-apache2_*/conf/hive-site.xml

    for _x in ${_hive_xml} ${_spark_xml}; do
        [ ! -s ${_x}.$$.bak ] && cp -p -f ${_x} ${_x}.$$.bak
        # Note this property order is important
        grep -q "hive.metastore.schema.verification" ${_x} || sed -i '/<\/configuration>/i \
    <property><name>hive.metastore.schema.verification</name><value>false</value></property>' ${_x}
        grep -q "hive.metastore.schema.verification.record.version" ${_x} || sed -i '/<\/configuration>/i \
    <property><name>hive.metastore.schema.verification.record.version</name><value>false</value></property>' ${_x}

        if [ -n "${inst_as_hive_metastore_password}" ] && [ "${inst_as_hive_metastore_password}" != "<empty>" ]; then
            grep -q "javax.jdo.option.ConnectionPassword" ${_x} || sed -i '/<\/configuration>/i \
    <property><name>javax.jdo.option.ConnectionPassword</name><value>'${inst_as_hive_metastore_password}'</value></property>' ${_x}
        fi
    done

    if [ "${inst_as_hive_metastore_database}" = 'true' ]; then
        sudo -u ${_usr} ${_dir%/}/bin/atscale_service_control restart atscale-hiveserver2 atscale-spark
    fi

    # Trying to setup Ambari URL for Tez TODO: still doesn't work. probably atscale doesn't use ATS?
    #local _ambari="`sed -nr 's/^hostname ?= ?([^ ]+)/\1/p' /etc/ambari-agent/conf/ambari-agent.ini`"
    #grep -q "tez.tez-ui.history-url.base" ${_dir%/}/share/apache-tez-*/conf/tez-site.xml || sed -i.$$.bak '/<\/configuration>/i \
#<property><name>tez.tez-ui.history-url.base</name><value>http://'${_ambari}':8080/#/main/view/TEZ/tez_cluster_instance</value></property>' ${_dir%/}/share/apache-tez-*/conf/tez-site.xml

    # Skipping first wizard introduced form 6.7.0 by populating data with APIs
    local _hdfsUri="`_get_from_xml "${inst_as_hadoop_conf_dir%/}/core-site.xml" "fs.defaultFS"`" || return $?

    local hdfsNameNodeKerberosPrincipal="null"
    local extraJdbcFlags="\"\""
    if [ "${inst_as_is_kerberized}" = "true" ]; then
        hdfsNameNodeKerberosPrincipal="\"${inst_as_hdfs_name_node_kerberos_principal}\""
        extraJdbcFlags="\";principal=${inst_as_kerberos_hive_principal_batch}\""
    fi

    jwt="`curl -s -X GET -u admin:admin "http://$(hostname -f):10500/default/auth"`" || return $?

    local _groupId="`curl -s -k "http://$(hostname -f):10502/connection-groups/orgId/default" -H "Authorization: Bearer ${jwt}" -d '{"name":"'${_wh_name}'","connectionId":"con1","hdfsUri":"'${_hdfsUri}'","hdfsNameNodeKerberosPrincipal":'${hdfsNameNodeKerberosPrincipal}',"hdfsSecondaryUri":null,"hdfsSecondaryNameNodeKerberosPrincipal":null,"hadoopRpcProtection":null,"subgroups":[],"defaultSchema":"'${inst_as_default_schema}'"}' | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response']['id']"`" || return $?
    # response example
    # { "status" : { "code" : 0, "message" : "200 OK" }, "responseCreated" : "2018-08-03T05:19:20.779Z", "response" : { "created" : true, "id" : "e22b575e-393f-4056-b5bf-32ea44501561" } }
    [ -z "${_groupId}" ] && return 11

    # In my custom_hdp.yaml, as_hive_flavor_batch uses atscale-hive, so using batch (also spark as interactive but it often doesn't work and also not suitable for system queries)
    if [ -z "${inst_as_hive_host_batch}" ]; then
        if [ "${as_hive_flavor_batch}" = "hive" ]; then
            # TODO: at this moment, assuming HS2 is installed same node as HMS
            inst_as_hive_host_batch="`_get_from_xml "/etc/hive/conf/hive-site.xml" "hive.metastore.uris" | sed -r 's/.+\/\/([^:]+):.+/\1/'`"
            inst_as_hive_port_batch="`_get_from_xml "/etc/hive/conf/hive-site.xml" "hive.server2.thrift.port"`"
        else
            inst_as_hive_host_batch="`hostname -f`"
        fi
    fi
    local _conId="`curl -s -k "http://$(hostname -f):10502/connection-groups/orgId/default/connection-group/${_groupId}" -H "Authorization: Bearer ${jwt}" \
    -d '{"name":"'${inst_as_hive_flavor_batch}'","hosts":"'${inst_as_hive_host_batch}'","port":'${inst_as_hive_port_batch}',"connectorType":"hive","username":"atscale","password":"atscale","extraJdbcFlags":'${extraJdbcFlags}',"queryRoles":["large_user_query_role","small_user_query_role","system_query_role","canary_query_role"],"extraProperties":{}}' | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response']['id']"`" || return $?
    # Can execute next API call without conId though...
    [ -z "${_conId}" ] && return 12

    local _envId="`curl -s -k "http://$(hostname -f):10502/environments/orgId/default" -H "Authorization: Bearer ${jwt}" \
    -d '{"name":"'${_env_name}'","connectionIds":["'${_groupId}'"],"hiveServer2Port":11111}' | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response']['id']"`" || return $?
    [ -z "${_envId}" ] && return 13

    curl -s -k "http://$(hostname -f):10500/api/1.0/org/default/setupWizard/setupComplete" -H "Authorization: Bearer ${jwt}" --data-binary 'orgId=default'
    echo ""
}

function _atscale_info() {
    local _dir="${1:-${_ATSCALE_DIR}}"
    local _msg="${2:-"Version: "}"
    echo "${_msg}`_get_version "${_dir}"`"
    # NOTE old version such as 5.12 does not have config_debug.yaml
    sed -nr 's/^(as_target_env|as_is_kerberized|as_secure_installation|as_default_schema|as_hdfs_root_dir):(.+)$/    \1:\2/p' ${_dir%/}/conf/config_debug.yaml 2>/dev/null #| sort
}

function f_switch_version() {
    local _version="$1"
    local _dir="${2:-${_ATSCALE_DIR}}"
    local _usr="${3:-${_ATSCALE_USER}}"

    if [ -z "${_version}" ]; then
        _atscale_info "${_dir}" "Currently used version: "
        echo -e "\nOther AtScales under `dirname "${_dir}"` (with *INITIAL* config)"
        for _d in `ls -1dtr ${_dir%/}_*`; do
            local _dname="`basename "${_d}"`"
            if [[ "${_dname}" =~ ^(atscale_)([^_]+)(_.+)$ ]]; then
                echo "  ${BASH_REMATCH[1]}*${BASH_REMATCH[2]}*${BASH_REMATCH[3]}"
            else
                echo "  ${_dname}"
            fi
            _atscale_info "${_d}" "    version: "
        done
        return
    fi

    local _target_dir="`ls -1dr ${_dir%/}_${_version}* | head -n1`"
    if [ -z "${_target_dir}" ]; then
        _log "ERROR" "Couldn't find ${_dir%/}_${_version}*"
        return 1
    fi

    f_atscale_stop "${_dir}" "${_usr}" || return $?

    if [ -L "${_dir%/}" ]; then
        # sometimes ln -f doesn't work so
        mv -f ${_dir%/} ${_dir%/}.symlink.bak || return $?
    elif [ -e "${_dir%/}" ]; then
        local _suffix="`_get_suffix`"
        mv ${_dir%/} ${_dir%/}_${_suffix} || return $?
    fi
    # Symlink doesn't work when upgrading due to 'Failed to set group to' error
    mv ${_target_dir%/} ${_dir%/} || return $?

    f_atscale_start ${_dir} ${_usr} || return $?
    _log "INFO" "AtScale started"
    _atscale_info "${_dir}" "Currently used version: "
}

function f_atscale_start() {
    local __doc__="Sometimes AtScale fails to start postgreSQL and I don't notice that, so that making sure postgresql is started"
    local _dir="${1:-${_ATSCALE_DIR}}"
    local _usr="${2:-${_ATSCALE_USER}}"

    if [ -s ${_dir%/}/bin/atscale_start ]; then
        sudo -u ${_usr} ${_dir%/}/bin/atscale_start
    fi

    sleep 1
    for _i in {1..3}; do
        lsof -ti:10520 -s TCP:LISTEN && return 0
        sleep 3
    done
    lsof -ti:10520 -s TCP:LISTEN
}

function f_atscale_stop() {
    local __doc__="Sometimes AtScale fails to stop postgreSQL and I don't notice that, so that making sure postgresql is stopped"
    local _dir="${1:-${_ATSCALE_DIR}}"
    local _usr="${2:-${_ATSCALE_USER}}"

    if [ -s ${_dir%/}/bin/atscale_stop ]; then
        sudo -u ${_usr} ${_dir%/}/bin/atscale_stop -f || return $?
    fi

    sleep 1
    for _i in {1..3}; do
        lsof -ti:10520 -s TCP:LISTEN || return 0
        sleep 3
    done
    ps h -u ${_usr}
    lsof -ti:10520 -s TCP:LISTEN && return 31
    #pkill -u ${_usr}
}

function f_atscale_status() {
    local _cmd="${1:-status}"
    local _dir="${2:-${_ATSCALE_DIR}}"
    local _usr="${3:-${_ATSCALE_USER}}"
    sudo -u ${_usr} ${_dir%/}/bin/atscale_service_control $_cmd
}

function _export_org_eng_env() {
    local jwt="$1"
    local _host="${2:-$(hostname -f)}"

    local _orgId="`curl -s -H "Authorization: Bearer $jwt" "http://${_host}:10500/api/1.0/orgs" | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response'][0]['id']"`"
    [ -z "${_orgId}" ] && return 21
    export _ORG_ID="${_orgId}"
    local _engId="`curl -s -H "Authorization: Bearer $jwt" "http://${_host}:10500/api/1.0/org/${_orgId}/engine" | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response'][0]['engine_id']"`"
    [ -z "${_engId}" ] && return 22
    export _ENGINE_ID="${_engId}"
    _envId="`curl -s -H "Authorization: Bearer $jwt" "http://${_host}:10500/api/1.0/org/${_orgId}/engine/${_engId}/environments" | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response'][0]['id']"`"
    [ -z "${_envId}" ] && return 23
    export _ENV_ID="${_envId}"
}

function f_dataloader() {
    local __doc__="Run dataloader-cli. Need env UUID"
    local _envId="${1}"
    [ -e ${_ATSCALE_DIR%/}/bin/dataloader ] || return $?
    if [ -z "${_envId}" ]; then
        local jwt="`curl -s -X GET -u admin:admin "http://$(hostname -f):10500/default/auth"`"
        _export_org_eng_env "${jwt}" || return $?
        _envId="${_ENV_ID}"
    fi
    # Just picking the smallest (no special reason).
    local _archive="`ls -1Sr ${_ATSCALE_DIR%/}/data/*.zip | head -n1`"
    sudo -u ${_ATSCALE_USER} ${_ATSCALE_DIR%/}/bin/dataloader installarchive -env ${_envId} -archive=${_archive}
}

function f_import_project() {
    local __doc__="Import (Upload) project xml with API calls"
    local _path="$1"
    local _host="${2:-$(hostname -f)}"
    local _envId="${3}"
    [ -s "${_path}" ] || return 11

    local jwt="`curl -s -X GET -u admin:admin "http://${_host}:10500/default/auth"`"
    _export_org_eng_env "${jwt}" "${_host}" || return $?
    [ -z "${_envId}" ] && _envId="${_ENV_ID}"

    #  -F verifyOnly=true | 'a['response']['name']
    local _projectId="`curl -s -H "Authorization: Bearer $jwt" "http://${_host}:10500/api/1.0/org/${_ORG_ID}/file/import" -F file=@${_path} --compressed | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response']['id']"`"
    [ -z "${_projectId}" ] && return 12
    # Should I rename?
    #curl 'http://${_host}:10500/api/1.0/org/${_ORG_ID}/project/${_projectId}/rename/IRM' -X POST
    # NOTE: --data-binary needs -H 'Content-Type: application/json'
    local _first_cubeId="`curl -s -H "Authorization: Bearer $jwt" "http://${_host}:10500/api/1.0/org/${_ORG_ID}/project/${_projectId}" -X PATCH -H 'Content-Type: application/json' --data-binary '{"projectId":"'${_projectId}'","display_name":"","renaming_query_name":false,"description":"","updating_description":false,"intended_env_id":"'${_envId}'","prediction_def_aggs":""}' --compressed | python -c "import sys,json;a=json.loads(sys.stdin.read());print a['response']['cubes']['cube'][0]['id']"`"
    [ -z "${_first_cubeId}" ] && return 13
    # Default permission
    curl -s -H "Authorization: Bearer $jwt" "http://${_host}:10500/api/1.0/org/${_ORG_ID}/permissions/project/${_projectId}" -H 'Content-Type: application/json' --data-binary '{"exclusive_access":false}'
    echo ""
}

function f_setup_TLS() {
    local __doc__="Enable HTTPS/SSL/TLS on AtScale"
    local _custom_yaml="${1}"
    local _key="${2:-/etc/security/serverKeys/server.`hostname -d`.key}"
    local _crt="${3:-/etc/security/serverKeys/server.`hostname -d`.crt}"
    local _dir="${4:-${_ATSCALE_DIR}}"
    local _usr="${5:-${_ATSCALE_USER}}"
    local _installer_parent_dir="${6:-/home/${_usr}}"

    # Update custom yaml so that next installer run won't break
    [ -z "${_custom_yaml}" ] && _custom_yaml=${_installer_parent_dir%/}/custom.yaml
    [ ! -r "${_custom_yaml}" ] && return 1
    sudo -u ${_usr} cp "${_custom_yaml}" "${_custom_yaml}_$(date +"%Y%m%d%H%M%S")"

    if [ ! -f ${_key} ]; then
        _log "ERROR" "Please create ${_key} and .crt for this server (eg.: f_ssl_hadoop)"
        return 1
    fi

    _change_key_value_in_file "${_custom_yaml}" "as_auth_host" "`hostname -f`"
    _change_key_value_in_file "${_custom_yaml}" "as_secure_installation" 'true'
    _change_key_value_in_file "${_custom_yaml}" "as_atscale_host_key" "${_key}"
    _change_key_value_in_file "${_custom_yaml}" "as_atscale_host_cert" "${_crt}"
    if [ -s /etc/security/clientKeys/all.jks ]; then
        _change_key_value_in_file "${_custom_yaml}" "has_custom_truststore" 'true'
        _change_key_value_in_file "${_custom_yaml}" "custom_truststore_location" "/etc/security/clientKeys/all.jks"
        _change_key_value_in_file "${_custom_yaml}" "custom_truststore_password" "changeit"
    fi

    if [[ ! "${_custom_yaml}" -ef "${_installer_parent_dir%/}/custom.yaml" ]]; then
        mv "${_installer_parent_dir%/}/custom.yaml" "${_installer_parent_dir%/}/custom.yaml_$(date +"%Y%m%d%H%M%S")"
        sudo -u ${_usr} cp "${_custom_yaml}" "${_installer_parent_dir%/}/custom.yaml" || return $?
    fi

    local _ver="`_get_version "${_dir}"`"
    _log "INFO" "Re-run '_UPDATING=Y f_install_atscale ${_ver}' to update certificate"
}

function f_setup_ldap_cert() {
    local __doc__="If LDAPS is available, import the LDAP/AD certificate into a trust store"
    local _ldap_host="${1:-$(hostname -f)}"
    local _ldap_port="${2:-636}" # or 389
    local _java_home="${3:-$(ls -1d ${_ATSCALE_DIR%/}/share/jdk*)}"
    local _truststore="${4:-${_java_home%/}/jre/lib/security/cacerts}" # or ${_dir%/}/security
    local _storepass="${5:-changeit}"

    echo -n | openssl s_client -connect ${_ldap_host}:${_ldap_port} -showcerts 2>&1 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > ${_TMP_DIR%/}/${_ldap_host}_${_ldap_port}.crt
    if [ ! -s "${_TMP_DIR%/}/${_ldap_host}_${_ldap_port}.crt" ]; then
        _log "WARN" "Certificate is NOT available on ${_ldap_host}:${_ldap_port}"; sleep 3
        return 1
    fi
    ${_java_home%/}/bin/keytool -import -trustcacerts -file "${_TMP_DIR%/}/${_ldap_host}_${_ldap_port}.crt" -alias "${_ldap_host}" -keystore "${_truststore}" -noprompt -storepass "${_storepass}" || return $?
    _log "INFO" "You need to restart Engine to use the updated truststore."; sleep 1
    #sudo -u atscale /usr/local/atscale/bin/atscale_service_control restart engine
}

function f_export_key() {
    local __doc__="Export private key from keystore"
    local _keystore="${1}"
    local _in_pass="${2}"
    local _alias="${3}"

    local _tmp_keystore="`basename "${_keystore}"`.tmp.jks"
    local _certs_dir="`dirname "${_keystore}"`"
    [ -z "${_alias}" ] &&  _alias="`hostname -f`"
    local _private_key="${_certs_dir%/}/${_alias}.key"

    keytool -importkeystore -noprompt -srckeystore ${_keystore} -srcstorepass "${_in_pass}" -srcalias ${_alias} \
     -destkeystore ${_tmp_keystore} -deststoretype PKCS12 -deststorepass ${_in_pass} -destkeypass ${_in_pass} || return $?
    openssl pkcs12 -in ${_tmp_keystore} -passin "pass:${_in_pass}" -nodes -nocerts -out ${_private_key} || return $?
    chmod 640  ${_private_key} && chown root:hadoop ${_private_key}
    rm -f ${_tmp_keystore}

    if [ -s "${_certs_dir%/}/${_alias}.crt" ] && [ -s "${_private_key}" ]; then
        cat "${_certs_dir%/}/${_alias}.crt" ${_private_key} > "${_certs_dir%/}/certificate.pem"
        chmod 640 "${_certs_dir%/}/certificate.pem"
        chown root:hadoop "${_certs_dir%/}/certificate.pem"
    fi
}

function f_setup_HAProxy_with_TLS() {
    local __doc__="Setup (outside) HAProxy for Atscale HA"
    local _certificate="${1:-/etc/security/serverKeys/certificate.pem}" # Result of f_export_key and 'cd /etc/security/serverKeys && cat ./server.`hostname -d`.crt ./rootCA.pem ./server.`hostname -d`.key > certificate.pem'
    local _master_node="${2:-node3.`hostname -d`}"
    local _slave_node="${3:-node4.`hostname -d`}"
    local _sample_conf="$4" # Result of "./bin/generate_haproxy_cfg -ah 'node3.support.localdomain,node4.support.localdomain'"

    local _certs_dir="`dirname "${_certificate}"`"
    if [ ! -s "${_certificate}" ] && [ -s "${_certs_dir%/}/server.keystore.jks" ]; then
        # TODO: password 'hadoop' needs to be changed
        f_export_key "${_certs_dir%/}/server.keystore.jks" "hadoop"
    fi
        if [ ! -s "${_certificate}" ]; then
            _log "ERROR" "No ${_certificate}"; sleep 5; return 1
    fi

    if [ ! -s "$_sample_conf" ]; then
        if [ ! -e './bin/generate_haproxy_cfg' ]; then
            _log "WARN" "No sample HA config and no generate_haproxy_cfg"; sleep 3
            if [ -s /etc/haproxy/haproxy.cfg.orig ] && [ -s /etc/haproxy/haproxy.cfg ]; then
                echo "Assuming the sample is copied to /etc/haproxy/haproxy.cfg"
            elif [ -s /var/tmp/share/atscale/haproxy.cfg.sample ]; then
                _sample_conf=/var/tmp/share/atscale/haproxy.cfg.sample
                echo "Using ${_sample_conf}"
            else
                sleep 3
                return 1
            fi
        else
            ./bin/generate_haproxy_cfg -ah ${_master_node},${_slave_node} || return $?
            _sample_conf=./bin/haproxy.cfg.sample
        fi
    fi

    if [ -s "$_sample_conf" ]; then
        mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig
        cp -f "${_sample_conf}" /etc/haproxy/haproxy.cfg || return $?
    fi

        yum install haproxy -y || return $?

    # append 'ssl-server-verify none' in global
    # comment out 'default-server init-addr last,libc,none'
    echo '--- '${_sample_conf}'   2018-07-16 18:09:09.504071841 +0000
+++ /etc/haproxy/haproxy.cfg    2018-07-14 05:04:50.272775825 +0000
@@ -11,6 +11,7 @@
 ####
 global
   maxconn 256
+  ssl-server-verify none

 defaults
   option forwardfor except 127.0.0.1
@@ -20,44 +21,44 @@
   timeout server 2d
   # timeout tunnel needed for websockets
   timeout tunnel 3600s
-  default-server init-addr last,libc,none
+  #default-server init-addr last,libc,none

 ####
 # AtScale Service Frontends
 ####
 frontend design_center_front
-  bind *:10500
+  bind *:10500 ssl crt '${_certificate}'
   default_backend design_center_back
 frontend sidecar_server_front
-  bind *:10501
+  bind *:10501 ssl crt '${_certificate}'
   default_backend sidecar_server_back
 frontend engine_http_front
-  bind *:10502
+  bind *:10502 ssl crt '${_certificate}'
   default_backend engine_http_back
 frontend auth_front
-  bind *:10503
+  bind *:10503 ssl crt '${_certificate}'
   default_backend auth_back
 frontend account_front
-  bind *:10504
+  bind *:10504 ssl crt '${_certificate}'
   default_backend account_back
 frontend engine_wamp_front
-  bind *:10508
+  bind *:10508 ssl crt '${_certificate}'
   default_backend engine_wamp_back
 frontend servicecontrol_front
-  bind *:10516
+  bind *:10516 ssl crt '${_certificate}'
   default_backend servicecontrol_back

 frontend engine_tcp_front_11111
   mode tcp
-  bind *:11111
+  bind *:11111 ssl crt '${_certificate}'
   default_backend engine_tcp_back_11111
 frontend engine_tcp_front_11112
   mode tcp
-  bind *:11112
+  bind *:11112 ssl crt '${_certificate}'
   default_backend engine_tcp_back_11112
 frontend engine_tcp_front_11113
   mode tcp
-  bind *:11113
+  bind *:11113 ssl crt '${_certificate}'
   default_backend engine_tcp_back_11113

 ####
@@ -65,46 +66,46 @@
 ####
 backend design_center_back
   option httpchk GET /ping HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':10500 check
-  server '${_slave_node}' '${_slave_node}':10500 check
+  server '${_master_node}' '${_master_node}':10500 ssl crt '${_certificate}' check
+  server '${_slave_node}' '${_slave_node}':10500 ssl crt '${_certificate}' check
 backend sidecar_server_back
   option httpchk GET /ping HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':10501 check
-  server '${_slave_node}' '${_slave_node}':10501 check
+  server '${_master_node}' '${_master_node}':10501 ssl crt '${_certificate}' check
+  server '${_slave_node}' '${_slave_node}':10501 ssl crt '${_certificate}' check
 backend engine_http_back
   option httpchk GET /ping HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':10502 check
-  server '${_slave_node}' '${_slave_node}':10502 check
+  server '${_master_node}' '${_master_node}':10502 ssl crt '${_certificate}' check
+  server '${_slave_node}' '${_slave_node}':10502 ssl crt '${_certificate}' check
 backend auth_back
-  server '${_master_node}' '${_master_node}':10503 check
-  server '${_slave_node}' '${_slave_node}':10503 check
+  server '${_master_node}' '${_master_node}':10503 ssl crt '${_certificate}' check
+  server '${_slave_node}' '${_slave_node}':10503 ssl crt '${_certificate}' check
 backend account_back
   option httpchk GET /ping HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':10504 check
-  server '${_slave_node}' '${_slave_node}':10504 check
+  server '${_master_node}' '${_master_node}':10504 ssl crt '${_certificate}' check
+  server '${_slave_node}' '${_slave_node}':10504 ssl crt '${_certificate}' check
 backend engine_wamp_back
-  server '${_master_node}' '${_master_node}':10508 check
-  server '${_slave_node}' '${_slave_node}':10508 check
+  server '${_master_node}' '${_master_node}':10508 ssl crt '${_certificate}' check
+  server '${_slave_node}' '${_slave_node}':10508 ssl crt '${_certificate}' check
 backend servicecontrol_back
   option httpchk GET /status HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':10516 check
-  server '${_slave_node}' '${_slave_node}':10516 check backup
+  server '${_master_node}' '${_master_node}':10516 ssl crt '${_certificate}' check
+  server '${_slave_node}' '${_slave_node}':10516 ssl crt '${_certificate}' check backup

 backend engine_tcp_back_11111
   mode tcp
   option httpchk GET /ping HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':11111 check port 10502
-  server '${_slave_node}' '${_slave_node}':11111 check port 10502
+  server '${_master_node}' '${_master_node}':11111 ssl crt '${_certificate}' check port 10502
+  server '${_slave_node}' '${_slave_node}':11111 ssl crt '${_certificate}' check port 10502
 backend engine_tcp_back_11112
   mode tcp
   option httpchk GET /ping HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':11112 check port 10502
-  server '${_slave_node}' '${_slave_node}':11112 check port 10502
+  server '${_master_node}' '${_master_node}':11112 ssl crt '${_certificate}' check port 10502
+  server '${_slave_node}' '${_slave_node}':11112 ssl crt '${_certificate}' check port 10502
 backend engine_tcp_back_11113
   mode tcp
   option httpchk GET /ping HTTP/1.1\r\nHost:\ www
-  server '${_master_node}' '${_master_node}':11113 check port 10502
-  server '${_slave_node}' '${_slave_node}':11113 check port 10502
+  server '${_master_node}' '${_master_node}':11113 check port 10502
+  server '${_slave_node}' '${_slave_node}':11113 check port 10502

 ####
 # HAProxy Stats' > /etc/haproxy/haproxy.cfg.patch || return $?
    patch < /etc/haproxy/haproxy.cfg.patch || return $?

    # NOTE: need to configure rsyslog.conf for log
    service haproxy reload
}

function _load_yaml() {
    local _yaml_file="${1:-${_CUSTOM_YAML}}"
    local _name_space="${2}"
    [ -s "${_yaml_file}" ] || return 1
    #source <(sed -e 's/:[^:\/\/]/=/g;s/$//g;s/ *=/=/g' ${_yaml_file})
    source <(sed -nr 's/^([^:]+): *(.+)/'${_name_space}'\1=\2/p' ${_yaml_file})
}

function _get_from_xml() {
    local _xml_file="$1"
    local _name="$2"
    # TODO: won't work with multiple lines
    grep -F '<name>'${_name}'</name>' -A 1 ${_xml_file} | grep -Pzo '<value>.+?</value>' | sed -nr 's/<value>(.+)<\/value>/\1/p'
}

function _log() {
    # At this moment, outputting to STDERR
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a ${g_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" 1>&2
    fi
}

help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        echo "help <function name> [Y]"
        echo ""
        _list "func"
        echo ""
        return
    fi

    local _output=""
    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            echo "Function name '$_function_name' does not exist."
            return 1
        fi

        eval "$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        if [ -z "$__doc__" ]; then
            _output="No help information in function name '$_function_name'.\n"
        else
            _output="$__doc__"
            if [[ "${_doc_only}" =~ (^y|^Y) ]]; then
                echo -e "${_output}"; return
            fi
        fi

        local _params="$(type $_function_name 2>/dev/null | grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v awk)"
        if [ -n "$_params" ]; then
            _output="${_output}Parameters:\n"
            _output="${_output}${_params}\n\n"
        fi
        if [[ "${_show_code}" =~ (^y|^Y) ]] ; then
            _output="${_output}${_code}\n"
            echo -e "${_output}" | less
        else
            [ -n "$_output" ] && echo -e "${_output}"
        fi
    else
        echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}
_list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep -P '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | gsed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | grep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | grep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | grep ^[r]_
    fi
}



### main ########################
if [ "$0" = "$BASH_SOURCE" ]; then
    if [[ "$1" =~ ^(-h|help)$ ]]; then
        if [[ "$2" =~ ^[fp]_ ]]; then
            help "$2" "Y"
        else
            usage
            _list
        fi
        exit
    fi
    #set -x
    # As using version, populating in here. I wouldn't create more than once per day per version
    [ -z "${_SCHEMA_AND_HDFSDIR}" ] && _SCHEMA_AND_HDFSDIR="atscale_$(_get_suffix "$_ATSCALE_VER")"
    f_setup || exit $?
    f_install_atscale || exit $?
    f_install_post_tasks
    _log "NOTE" "To import a sample data, execute 'f_dataloader' function"
fi
