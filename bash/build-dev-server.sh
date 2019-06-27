#!/bin/bash
#
# Script to build Web and DB server (at this moment, for DEV)
#
# Naming rule:
#     f_xxxYyZz = Function with CamelCase except usage() and main()
#     g_xxx_yyy = Global variable
#     r_xxx_yyy = Variable stored or loaded from response file
#     _xxx_yyyy = function local variable
#
#     g_xxxx_dir ends with "/"
# 
#     Use _echo instead of echo
#     Use _eval if command may change system
#
# Quick test:
#     1) sudo -s
#     2) . ./<this script name>.sh
#     3) f_loadResp            # if you have your response file in default dir, otherwise f_loadResp <resp_file_path> 
#     4) g_is_dryrun=true        # if you don't want to change your system
#     5) Then test each function
#        for example, type "usage", "f_checkUpdate" etc.
# 
#     *) list defined variables: set | grep ^[gr]_
#     *) list defined functions: typeset -F | grep '^declare -f f_'
#     *) function definition:    type "function_name"
#
# @author Hajime Osako
#
# FIXME: not elegant coding
# 

usage() {
    echo "HELP/USAGE:"
    echo "This script installs required packages and configures web server.
    
How to run:
    sudo ./${g_script_name} [-r=file_name.resp]
    
How to run one function:
    1) sudo -s
    2) source ./${g_script_name}
    3) f_loadResp    # if you have response file in default location
       list [functions]    # to list available functions
       help f_xxxxxxx    # to show help for 'f_xxxxxxx'
    4) For example, import a database after loading *proper* response file:
       f_importDb 'dev_xxxx_latest' 'xxxx'
    
Available options:
    -a    Full Interview mode which asks All questions (default).
    -m    Minimum Interview mode which use default values for most questions.
    -c    To continue to use the last response file from default location.
    -r=response_file_path
          To reuse your previously saved response file.
    -h    Show this message.
    
Content Import types:
    scp:    For DB import to copy a database 7zip file.
    pgd:    For DB import to directly copy a database by using pg_dump | psql.
    smb:    For Code and Admdocs import to mount a remote file system via Windows SMB
    ssh:    For Code and Admdocs import to mount a remote file system via SSH
    svn:    For Code import to do Subversion Check-out
    sync:   For Admdoc import to mount a Read-Only file system via ssh then use Rsync (Experimental)
    
Default Response file location:
    ${g_default_response_file}
Log file path:
    ${g_command_output_log}
"
    changeLog
}

changeLog() {
    # If change affects to response file, should notify to user.
    echo "
Recent Changes:
    2013-07-25 Response file can be encrypted.
    2013-09-04 Added 'f_addApacheVirtualHost'
    2013-09-06 Added 'f_addBuildSite' to setup Apache, code and DB
    2013-09-06 New DB import type 'pgd' (which use pg_dump)
    2013-09-10 Added 'f_mountSshfs' to mount remote directory
    2013-10-02 f_importDb accepts '_db_env_name' for Dev env
    2013-11-07 Added f_copyDbForDev for Build Developer
"
}

main() {
    g_is_script_running=true
    _makeBackupDir || _critical "Could not start this script."
    
    f_interviewOrLoadResp
    
    f_validationPre
    
    echo ""
    f_ask "Would you like to start running?" "Y"
    if ! _isYes; then _echo "Bye."; _exit 0; fi
    
    local _start_time="$(date +"%Y-%m-%d %H:%M:%S")"
    f_startInstallations 2>&1 | tee -a $g_command_output_log
    
    # FIXME: don't need to save STDOUT in the log but want to see in screen
    f_startImportContents 2>&1 | tee -a $g_command_output_log
    
    f_validationPost | tee /tmp/f_validationPost_last.out
    cat /tmp/f_validationPost_last.out >> $g_command_output_log
    
    if ! $g_not_send_email && _isEmail "$r_admin_mail"; then
        cat /tmp/f_validationPost_last.out | mail -s "Build Script finished for `hostname`" "$r_admin_mail"
    fi
    
    local _end_time="$(date +"%Y-%m-%d %H:%M:%S")"
    _echo "Completed! (Start:${_start_time} - End:${_end_time})"
    echo "${g_end_msg}"
    echo ""
}

###############################################################################
# Define all Global variables and bash config in here
###############################################################################

g_is_verbose=true
g_is_debug=false
g_is_dryrun=false
g_force_default=false
g_not_send_email=false
g_last_answer=""
g_last_rc=0
g_yes_regex='^(1|y|yes|true|t)$'
g_ip_regex='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
g_ip_range_regex='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])?$'
g_hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
g_url_regex='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
g_test_regex='^\[.+\]$'
g_default_password="Welcome$(date +"%y")"
g_is_script_running=false

g_hostname=`hostname`
g_script_name=`basename $BASH_SOURCE`
g_script_base=`basename $BASH_SOURCE .sh`
g_backup_dir="$HOME/.build_script/"
g_tmp_mnt_dir="/mnt/build_tmp/"
g_start_time="$(date +"%Y%m%d-%H%M%S")"
g_command_output_log="${g_backup_dir}${g_script_base}_${g_start_time}.out"
g_default_response_file="${g_backup_dir}${g_script_base}.resp"
g_end_msg="See ${g_command_output_log} for more detail."
g_pid="$$"


### Build specific parameters
g_default_domain="build.local"
g_dev_server_ip="192.168.0.21"        # server which does many tasks in AU
g_dev_server_ip_pg="10.0.0.21"        # server which does many tasks in PNG
g_mon_server_ip="$g_dev_server_ip"    # server which pull snmp info
g_ntp_server_ip="$g_dev_server_ip"
g_db_server_ip="$g_dev_server_ip"    # DB dump download server
g_doc_server_ip="$g_dev_server_ip"    # Admdocs download server
g_svn_server_ip="svn.${g_default_domain}"
# TODO: use https
g_svn_url="http://${g_svn_server_ip}/svn/"
g_svn_url_build="http://${g_svn_server_ip}/svn/build/trunk/"
g_script_partial_path="utils/utility-scripts/build-dev-server.sh"
g_script_url="${g_svn_url_build%/}/site/${g_script_partial_path}"
g_it_mgmt_server="192.168.112.50"
g_key_server_ip="192.168.0.101"    # FIXME: hasn't properly used yet (used for SNMP)
g_smtp_ip="mx.testdomain.com" # (.60.5 .34.8 .66.8 .18.8)
g_db_backup_path="/data/backup/synched_from_production"
g_admin_mail="buildteam@testdomain.com"
g_non_delivery_mailuser="build-do-not-reply"
g_default_entity_name="default"
g_make_dir_list=( "/data/backup/synched_from_production" "/data/backup/synch_to_failover" "/data/backup/synched_from_production_intraday" "/data/backup/synch_to_failover_intraday" "/data/sql_svn" "/data/backup/intraday_dumps" "/data/backup/crontab" "/var/log/build" "/var/log/build/transient" "/var/log/build/old_logs" )
g_build_crontab="/etc/cron.d/build-crontab"
g_db_expect_line=26000
#g_db_big_tables="tblsys_audittrail,tbllog_user_access"
g_db_big_tables="tblsys_audittrail"
g_system_user="buildsystemuser"
g_automation_user="buildautomation"
g_build_config_svn_path="/build/trunk/site/webroot/xul/core_ui/config.ini.php"
g_obfuscate_prefix="ENC|"


### OS Extra Users (up to 9, alphabetical order)
g_os_username_1="hajimeosako"
g_os_is_super_1="Y"
g_os_public_k_1="ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAIB1fJLZccHzX6uP7NVUE2tPngw2vZWuZFE6hImsPdg4zWeiPFEctQphMeyPBkLg7otPdt1NQZMKasb5JD0qQQk0e8r/AgvUeN+rBzc/moH1DeEDpn9pCoVI7R9KcSmkvE8dprFXy21iiyXv0RrIFkvifn/w+PVlZ3PFzMYVg/UFLQ=="


### OS or Package installation related parameters
g_default_dir_perm="777"
g_supported_ubuntu_regex="Ubuntu 12\.04\."
# common utility type packages (others such as Apache, PostgreSQL are installed in each install function)
g_apt_packages="build-essential sysv-rc-conf python-software-properties traceroute pstack nethogs iftop dstat parallel pv sshfs smbfs winbind smbclient p7zip-full ghostscript links tmux screen expect mailutils lynx fetchmail wget curl rsync python-pip memcached unison sqlite3 poppler-utils git dos2unix logrotate ldap-utils vnstat htop debian-archive-keyring unzip imagemagick libwww-perl"
g_default_key_path="/root/.ssh/id_rsa"
g_sshfs_options="allow_other,uid=0,gid=0,umask=000,reconnect,follow_symlinks"
g_smbfs_options="iocharset=utf8,file_mode=0776,dir_mode=0777"
g_startup_script_path="/etc/rc.local"
g_min_admdocs_size_gb=240
g_min_db_data_size_gb=20
g_min_memory_size_mb=2000
g_max_rsync_size_mb=5


### Database related config parameters
g_db_version="9.2"
g_db_port="5432"
g_db_cluster_name="main"
g_db_home="/var/lib/postgresql"
g_db_wal_dir="${g_db_home%/}/wal_archive"
g_db_superuser="postgres"
g_db_username="pgsql"
g_db_replicator="build_repl"
g_db_conf_dir="/etc/postgresql/${g_db_version}/${g_db_cluster_name}"
g_db_data_dir="${g_db_home%/}/${g_db_version}/${g_db_cluster_name}"

declare -A g_db_conf_array
g_db_conf_array[datestyle]="'sql, dmy'"
g_db_conf_array[client_encoding]="unicode"
g_db_conf_array[listen_addresses]="'*'"
g_db_conf_array[log_destination]="'stderr'"
g_db_conf_array[log_connections]="on"
g_db_conf_array[log_disconnections]="on"
g_db_conf_array[logging_collector]="on"
g_db_conf_array[log_directory]="'/var/log/postgresql'"
g_db_conf_array[log_filename]="'postgresql-%Y-%m-%d.log'"
g_db_conf_array[log_file_mode]="0666"
#g_db_conf_array[log_truncate_on_rotation]="on"
#g_db_conf_array[log_rotation_age]="1d"
g_db_conf_array[log_min_messages]="notice"
g_db_conf_array[log_min_error_statement]="error"
g_db_conf_array[log_min_duration_statement]="5000"
g_db_conf_array[timezone]="'localtime'"
g_db_conf_array[log_timezone]="'localtime'"
g_db_conf_array[log_statement]="'mod'"
g_db_conf_array[ssl_renegotiation_limit]="0"
g_db_conf_array[log_line_prefix]="'%t %p '"
#g_db_conf_array[shared_buffers]="1024MB"    # automatically calculated
g_db_conf_array[timezone_abbreviations]="'Australia'"

### Apache related config parameters
g_apache_data_dir="/data/sites/"
g_apache_user="www-data"
g_apache_webroot_dirname="webroot"


### PHP related config parameters
g_php_ini_path="/etc/php5/apache2/php.ini"

declare -A g_php_ini_array
g_php_ini_array[enable_dl]="On"
g_php_ini_array[error_log]="/var/log/php-error.log"
g_php_ini_array[error_reporting]="E_ALL & ~E_NOTICE & ~E_DEPRECATED"
g_php_ini_array[max_execution_time]="100"
g_php_ini_array[max_input_time]="100"
g_php_ini_array[memory_limit]="256M"
g_php_ini_array[output_buffering]="Off"
g_php_ini_array[post_max_size]="124M"
g_php_ini_array[register_argc_argv]="On"
g_php_ini_array[register_globals]="On"
g_php_ini_array[register_long_arrays]="On"
g_php_ini_array[serialize_precision]="100"
g_php_ini_array[session.bug_compat_42]="On"
g_php_ini_array[session.bug_compat_warn]="On"
g_php_ini_array[session.gc_maxlifetime]="50400"
g_php_ini_array[session.gc_probability]="1"
g_php_ini_array[session.hash_bits_per_character]="4"
g_php_ini_array[short_open_tag]="Off"
g_php_ini_array[upload_max_filesize]="124M"
g_php_ini_array[url_rewriter.tags]="\"a=href,area=href,frame=src,form=,fieldset=\""
g_php_ini_array[variables_order]="\"EGPCS\""
#g_php_ini_array[session.save_path]="/var/lib/php5"    # if you change this to different location, default PHP GC job does not check.


### OS/shell settings
shopt -s nocasematch
#shopt -s nocaseglob
set -o posix
#umask 0000

###############################################################################
# Define functions in here
###############################################################################

function f_interview() {
    local __doc__="Ask questions and responses will be used in 2nd phase to automate."
    
    f_ask "Is this 'dev'(web+db), 'prod'(web+db), 'prod-web', or 'prod-db' server? {dev|prod|prod-web|prod-db}" "" "r_server_type" "N" "Y"
    f_ask "System/DB entity type" "" "r_db_entity" "N" "Y"
    f_ask "SVN URL for Build" "${g_svn_url_build}" "r_svn_url_build" "N" "Y"
    f_ask "SVN username" "${g_system_user}" "r_svn_user" "N" "Y"
    f_ask "Password" "" "r_svn_pass" "Y" "Y" "_isSvnCredential"
    
    _echo "A) OS and Packages related interviews"
    echo "Would you like to change Hostname?"
    f_ask "Type new hostname or leave it blank for no change" "" "r_new_hostname" "N" "N" "_isIpOrHostname"
    if [ -n "$r_new_hostname" ]; then g_hostname="$r_new_hostname"; fi
    f_ask "Would you like to configure Network Interface? {y|n}" "N" "r_config_nic"
    if _isYes "$r_config_nic"; then
        f_ask "Configuring NIC name, ex:eth1" "" "r_nic_name" "N" "[ \"\$r_config_nic\" = \"y\" ]"
        f_ask "IP Address or 'dhcp' for DHCP" "" "r_nic_address"
        f_ask "NetMask (optional)" "" "r_nic_netmask"
        f_ask "Gateway (optional)" "" "r_nic_gateway"
        f_ask "DNS Servers (space separated) ex:192.168.60.4 192.168.60.7" "" "r_nic_nameservers" "N" "[ \"\$r_config_nic\" = \"y\" ]"
        f_ask "DNS Suffix" "" "r_nic_search"
    fi
    f_ask "Would you like to configure system-wide proxy? {y|n}" "N" "r_config_proxy"
    if _isYes "$r_config_proxy"; then
        f_ask "Proxy address. Format http://username:password@hostname:port/" "" "r_proxy_address" "N" "[ \"\$r_config_proxy\" = \"y\" ]"
        f_ask "Proxy exclude address list (optional)" "" "r_proxy_exclude_list"
    fi
    local _def_auto_security_updates="Y"
    if [ "$r_server_type" != "dev" ]; then _def_auto_security_updates="N"; fi
    f_ask "Would you like to set Automatic Security Updates {y|n}" "$_def_auto_security_updates" "r_auto_security_updates"
    f_ask "Use '-y' option with apt-get command {y|n}" "Y" "r_aptget_with_y"
    f_ask "Server Admin (root) email" "${g_admin_mail}" "r_admin_mail" "N" "N" "_isEmail"
    f_ask "SMTP Relay IP" "$g_smtp_ip" "r_relay_host" "N" "N" "_isIpOrHostname"
    f_ask "Restrict SSH password auth? {y|n}" "Y" "r_disable_ssh_pauth"
    if ! _isYes "$r_disable_ssh_pauth"; then
        f_ask "Would you like to add Build Dev and System users? {y|n}" "Y" "r_add_build_dev"
        _info "Private Keys for System users are stored in ${g_key_server_ip}"
    else
        _echo "Will add Build Dev and System users."
        _info "Private Keys for System users are stored in ${g_key_server_ip}"
        r_add_build_dev="Y"
    fi
    dmidecode -s system-manufacturer | grep -wi vmware &>/dev/null
    if [ $? -eq 0 ]; then
        f_ask "Would you like to install VMWare Tools?" "Y" "r_vmware_tools"
    fi
    
    _echo "B) PostgreSQL configuration interviews"
    local _ttl_mem=`cat /proc/meminfo | grep ^MemTotal | awk '{print $2}'`
    local _recommend_mem="`expr $_ttl_mem / 4 / 1024`"
    f_ask "shared_buffers size (MB)" "${_recommend_mem}" "r_db_shared_buffers"
    if [ "$r_server_type" = "prod-web" ]; then
        _echo "As server type is $r_server_type, skipping other DB configufation interviews."
    else
        f_ask "Database username for Build" "${g_db_username}" "r_db_username" "N" "[ \"\$r_server_type\" != \"prod-web\" ]"
        f_ask "Database Password for ${r_db_username}" "" "r_db_password" "Y" "[ \"\$r_server_type\" != \"prod-web\" ]"
        f_ask "Is this a superuser? {y|n}" "Y" "r_db_is_user_super"
        local _def_db_client_ip_list="192.168.0.0/16"
        if [ "$r_server_type" != "dev" ]; then _def_db_client_ip_list=""; fi
        f_ask "Comma separated DB client IP/Range, ex:192.168.56.0/24 " "$_def_db_client_ip_list" "r_db_client_ip_list"
    fi
    
    _echo "C) Web server configuration interviews"
    f_ask "PHP Date Timezone" "Australia/Brisbane" "r_date_timezone"
    if [ "$r_server_type" = "prod-db" ]; then
        _echo "As server type is $r_server_type, skipping other Web configufation interviews."
    else
        f_ask "Virtual Host ServerName" "$g_hostname" "r_apache_server_name"
        local _def_server_alias="build_vm1_dev"
        if [ "$r_server_type" != "dev" ]; then _def_server_alias=""; fi
        f_ask "Virtual Host ServerAlias" "${_def_server_alias}" "r_apache_server_alias"
        local _def_doc_root_parent="$r_apache_server_name"
        if [ "$r_server_type" != "dev" ]; then _def_doc_root_parent="production"; fi
        f_ask "Apache Document Root (${g_apache_webroot_dirname}) path " "${g_apache_data_dir%/}/${_def_doc_root_parent}/${g_apache_webroot_dirname}" "r_apache_document_root" "N" "N" "_isFilePath"
        local _def_website=""
        if [ "$r_server_type" != "dev" ]; then _def_website="${g_hostname}-prod"; fi
        f_ask "Virtual Host SetEnv WEBSITE" "$_def_website" "r_apache_env_website" "N"
        #f_ask "Append WEBSITE in config.ini.php if doesn't exist? (experimental)" "N" "r_code_modify_config"
        local _def_filename="${r_apache_server_name}"
        if [ "$r_server_type" != "dev" ]; then _def_filename="production"; fi
        f_ask "Virtual Host file name" "${_def_filename}" "r_apache_file_name" "N" "Y"
    fi
    
    _echo "D) Build Code import interviews"
    if [ "$r_server_type" = "prod-db" ]; then
        _echo "As server type is $r_server_type, no Code importing."
        r_code_import="skip"
        r_code_import_cmd=""
    else
        f_ask "How to import Build source code {svn|smb|ssh|skip}" "svn" "r_code_import" "N" "Y"
        local _import_target="$(dirname "${r_apache_document_root}")"
        if [ "$r_code_import" = "svn" ]; then
            f_ask "SVN CheckOut URL" "${r_svn_url_build%/}/site" "r_code_import_path" "N" "[ \"\$r_code_import\" = \"svn\" ]" "_isFilePath"
            f_ask "Import target path" "$_import_target" "r_code_import_target" "N" "[ \"\$r_code_import\" = \"svn\" ]" "_isFilePath"
            #f_ask "Code SVN command" "svn co ${r_svn_url_build%/}/site ${r_code_import_target}" "r_code_import_cmd" "N" "[ \"\$r_code_import\" = \"svn\" ]" "_isFilePath"
        elif [ "$r_code_import" = "smb" ]; then
            f_interviewImportCommon "code" "$r_code_import"
            f_ask "Windows Share path (ex://$r_code_import_server/site)" "" "r_code_import_path" "N" "N" "_isFilePath"
            #if [[ "$r_code_import_path" =~ /${g_apache_webroot_dirname}$ ]]; then _import_target="$(dirname "$_import_target")"; fi
            f_ask "Mount target path" "$_import_target" "r_code_import_target" "N" "N" "_isFilePath"
            f_ask "Code Mount command" "mount -t cifs ${r_code_import_path} ${r_code_import_target} -o credentials=${r_code_import_cred_path},${g_smbfs_options}" "r_code_import_cmd" "N" "[ \"\$r_code_import\" = \"smb\" ]"
            #f_ask "FSTab entory" "${r_code_import_path} ${r_apache_document_root%/} cifs credentials=${r_code_import_cred_path},${g_smbfs_options} 0 0" "r_code_import_fstab"
        elif [ "$r_code_import" = "ssh" ]; then
            f_interviewImportCommon "code" "$r_code_import"
            f_ask "Full path to site dir on *remote* server" "" "r_code_import_path" "N" "N" "_isFilePath"
            #if [[ "$r_code_import_path" =~ /${g_apache_webroot_dirname}$ ]]; then _import_target="$(dirname "$_import_target")"; fi
            f_ask "Import target path" "$_import_target" "r_code_import_target" "N" "N" "_isFilePath"
            f_ask "Code SshFS mount command" "sshfs -o ${g_sshfs_options} ${r_code_import_user}@${r_code_import_server}:${r_code_import_path} ${r_code_import_target}" "r_code_import_cmd" "N" "[ \"\$r_code_import\" = \"ssh\" ]"
            #f_ask "FSTab entory" "sshfs#${r_code_import_user}@${r_code_import_server}:${r_code_import_path} ${r_apache_document_root%/} fuse ${g_sshfs_options} 0 0" "r_code_import_fstab"
        else
            _echo "Response: ${r_code_import}"
            _echo "Please import Build source code later."
            r_code_import="skip"
            r_code_import_cmd=""
        fi
    fi
    
    _echo "E) Build Database import interviews"
    if [ "$r_server_type" = "prod-web" ]; then
        _echo "As server type is $r_server_type, no Build Database importing."
        r_db_import="skip"
        r_db_import_cmd=""
    else
        if f_isEnoughDisk "$g_db_data_dir" ${g_min_db_data_size_gb} ; then
            _info "Available space for database: `_freeSpaceGB "$g_db_data_dir"`GB"
            local _db_import_default="scp"
        else
            _info "Available space `_freeSpaceGB "$g_db_data_dir"`GB may not be enough for SCP (about ${g_min_db_data_size_gb}GB space required)"
            local _db_import_default="skip"
        fi
        f_ask "How to import Build Database {scp|pgd|skip}" "$_db_import_default" "r_db_import" "N" "Y"
        
        if [ -z "$r_db_import_server" ]; then
            r_db_import_server="$g_db_server_ip"
        fi
        if [ "$r_db_import" = "scp" ] || [ "$r_db_import" = "pgd" ]; then
            if [ "$r_server_type" = "dev" ]; then
                #local _db_ad_login="$(echo "${r_admin_mail}" | sed -r 's/@.+$//g')"
                f_ask "Your Windows AD login or e-mail address" "$r_admin_mail" "r_db_ad_login"
                #f_ask "Build login (dummy) password" "${g_default_password}" "r_db_ad_password"
                f_ask "DB System property 'testEnvironment' value" "${r_apache_env_website}" "r_db_env_name"
                f_ask "New DB name" "dev_${r_db_entity}_$(date +"%Y%m%d")" "r_db_name"
            else
                f_ask "New DB name" "${r_db_entity}_production" "r_db_name"
            fi
            if _isDbExist "${r_db_name}"; then
                _echo "Database \"${r_db_name}\" already exists."
            fi
            f_ask "Run 'dropdb' before creating if exists?" "N" "r_db_drop"
            f_ask "DB encoding {SQL_ASCII|UTF-8}" "UTF-8" "r_db_encoding"
            f_interviewImportCommon "db" "$r_db_import"
            
            if [ "$r_db_import" = "scp" ]; then
                f_ask "Full path to the DB zipped file on *remote* server" "${g_db_backup_path}_${r_db_entity}/${r_db_entity}_build_production.7z" "r_db_import_path" "N" "[ \"\$r_db_import\" = \"scp\" ]"
                f_ask "Re-use .sql/.7z file if already exists locally?" "Y" "r_db_import_reuse"
            else
                f_ask "Remote database name" "$r_db_name" "r_db_name_remote"
                f_ask "Remote database user name" "$r_db_username" "r_db_username_remote"
                f_ask "Remote database password" "" "r_db_password_remote" "Y"
                if [ "$r_server_type" = "dev" ]; then
                    f_ask "Would you like to exclude some huge tables?" "Y"
                    if _isYes; then
                        f_ask "Exclude table list" "${g_db_big_tables}" "r_db_exclude_tables"
                    fi
                fi
                f_ask "Would you like to save a dumped SQL?" "N" "r_db_save_sql"
            fi
        else
            _echo "Response: ${r_db_import}"
            _echo "Please import Build database later."
            r_db_import="skip"
            r_db_import_cmd=""
        fi
    fi
    
    _echo "F) Build Admdocs import interviews"
    if [ "$r_server_type" = "prod-db" ]; then
        _echo "As server type is $r_server_type, no Admdoc importing."
        r_docs_import="skip"
        r_docs_import_cmd=""
    else
        if [ -z "$r_docs_import_server" ]; then
            r_docs_import_server="$g_doc_server_ip"
        fi
        _info "Available space: `_freeSpaceGB "$r_apache_document_root"`GB"
        f_ask "How to import Build Admdocs {sync|smb|ssh|skip}" "skip" "r_docs_import" "N" "Y"
        if [ "$r_docs_import" = "sync" ]; then
            f_ask "Admdocs directory path" "${r_apache_document_root%/}/admdocs" "r_docs_import_target"
            if f_isEnoughDisk "$r_docs_import_target" ${g_min_admdocs_size_gb} ; then
                f_ask "Copy with rsync? (about ${g_min_admdocs_size_gb}GB space required)" "N" "r_docs_import_full"
            else
                f_ask "Not enough space but copy with rsync? (about ${g_min_admdocs_size_gb}GB space required)" "N" "r_docs_import_full"
            fi
            f_interviewImportCommon "docs" "$r_docs_import"
            f_ask "Full path to Admdocs on *remote* server" "" "r_docs_import_path" "N" "N" "_isFilePath"
            f_ask "Read Only mount path" "$g_tmp_mnt_dir" "r_docs_import_ro_mount" "N" "N" "_isFilePath"
            if _isYes "$r_docs_import_full" ; then
                _echo "Please review the following rsync command (ex: add '--max-size=${g_max_rsync_size_mb}m')"
                local _max_rsync_size=""
            else
                _echo "Only the latest docs (media_type <> 'X') and file size less than ${g_max_rsync_size_mb}MB will be synched."
                local _max_rsync_size="--max-size=${g_max_rsync_size_mb}m"
            fi
            # synching from RO mount directly to admdoc path
            f_ask "Admdocs Sync command" "f_rsync \"${r_docs_import_ro_mount%/}/\" \"${r_docs_import_target%/}/\" \"-avz --delete ${_max_rsync_size}\"" "r_docs_import_cmd" "N" "[ \"\$r_docs_import\" = \"sync\" ]"
        elif [ "$r_docs_import" = "smb" ]; then
            f_ask "Admdocs directory path" "${r_apache_document_root%/}/admdocs" "r_docs_import_target" "N" "N" "_isFilePath"
            f_interviewImportCommon "docs" "$r_docs_import"
            f_ask "Windows Share path to Admdocs (//$r_docs_import_server/share)" "" "r_docs_import_path" "N" "N" "_isFilePath"
            f_ask "Admdocs Mount command" "mount -t cifs ${r_docs_import_path} ${r_docs_import_target%/} -o credentials=${r_docs_import_cred_path},${g_smbfs_options}" "r_docs_import_cmd" "N" "[ \"\$r_docs_import\" = \"smb\" ]"
            #f_ask "FSTab entory" "${r_docs_import_path} ${r_docs_import_target%/} cifs credentials=${r_docs_import_cred_path},${g_smbfs_options} 0 0" "r_docs_import_fstab"
        elif [ "$r_docs_import" = "ssh" ]; then
            f_ask "Admdocs directory path" "${r_apache_document_root%/}/admdocs" "r_docs_import_target" "N" "N" "_isFilePath"
            f_interviewImportCommon "docs" "$r_docs_import"
            f_ask "Full path to Admdocs on *remote* server" "" "r_docs_import_path" "N" "N" "_isFilePath"
            f_ask "Admdocs SshFS mount command" "sshfs -o ${g_sshfs_options} ${r_docs_import_user}@${r_docs_import_server}:${r_docs_import_path} ${r_docs_import_target%/}" "r_docs_import_cmd" "N" "[ \"\$r_docs_import\" = \"ssh\" ]"
            #f_ask "FSTab entory" "sshfs#${r_docs_import_user}@${r_docs_import_server}:${r_docs_import_path} ${r_docs_import_target%/} fuse ${g_sshfs_options} 0 0" "r_docs_import_fstab"
        else
            _echo "Response: ${r_docs_import}"
            _echo "Please import Build Admdocs later."
            r_docs_import_target=""
            r_docs_import="skip"
            r_docs_import_cmd=""
        fi
    fi
    
    _echo "Z) Misc. "
    local _tmp_default_answer="Y"; if [ "$r_server_type" = "dev" ]; then _tmp_default_answer="N"; fi
    f_ask "Would you like to commit '/etc' into SVN and schedule daily?" "$_tmp_default_answer" "r_commit_etc"
    if [ "$r_code_import" = "svn" ]; then
        f_ask "Would you like to schedule svn update for Build code?" "$_tmp_default_answer" "r_svn_update"
        if _isYes "$r_svn_update"; then
            f_ask "Will this web server be for Readonly/Training? {readonly|training|empty}" "" "r_svn_update_type"
        fi
    fi
}

# FIXME: can't automatically validate interviews in f_interviewImportCommon
function f_interviewImportCommon() {
    local _prefix="$1"
    local _type="$2"
    local _tmp_server="r_${_prefix}_import_server"
    local _tmp_user="r_${_prefix}_import_user"
    local _tmp_pass="r_${_prefix}_import_pass"
    #local _tmp_path="r_${_prefix}_import_path"
    local _tmp_cmd="r_${_prefix}_import_cmd"
    local _tmp_cred_path="r_${_prefix}_import_cred_path"
    local _default=""
    
    f_ask "Remote server IP for \"${_prefix}/${_type}\"" "" "${_tmp_server}" "N" "Y" "_isIpOrHostname"
    f_ask "Username for remote server" "${g_automation_user}" "${_tmp_user}"
    
    if [ "$_type" = "smb" ]; then
        f_ask "Password" "" "${_tmp_pass}" "Y"
        f_ask "Windows AD name" "HGM" "${!_tmp_domain}"
        _default="/root/.${_type}_${!_tmp_server}"
        f_ask "Credential store path" "$_default" "${_tmp_cred_path}" "N" "Y" "_isFilePath"
    elif [ "$_type" != "svn" ]; then
        if [ "${_tmp_user}" != "${g_automation_user}" ]; then 
            f_ask "Password" "" "${_tmp_pass}" "Y"
            f_ask "Key store path" "${g_default_key_path}" "${_tmp_cred_path}" "N" "Y" "_isFilePath"
            if [ ! -r "${!_tmp_cred_path}" ]; then
                if ! _isYes "$r_ssh_key_create" ; then
                    f_ask "Local key does not exist. Creating new one? {y|n}" "Y" "r_ssh_key_create"
                    if _isYes "$r_ssh_key_create" ; then
                        f_ask "Passphrase (Recommend blank, just press Enter key twice)" "" "r_ssh_key_passphrase" "Y"
                    fi
                fi
            fi
        else
            f_ask "Key store path" "/home/${g_automation_user}/.ssh/id_rsa" "${_tmp_cred_path}" "N" "Y" "_isFilePath"
        fi
    fi
}

function f_interviewOrLoadResp() {
    local __doc__="Asks user to start inteview, review interview, or start installing with given response file."
    
    if [ -z "${g_response_file}" ]; then
        _echo "Response file was not specified."
        if $g_force_default ; then
            f_ask "Would you like to start Minimum Interview mode?" "Y"
        else
            f_ask "Would you like to start Interview mode?" "Y"
        fi
        
        echo ""
        if ! _isYes; then usage; _echo "Bye."; _exit 0; fi
        
        _info "Starting Interview mode..."
        _info "You can stop this interview anytime by pressing 'Ctrl+c' (except while typing Password)."
        echo ""
        
        g_response_file="$g_default_response_file"
        
        trap '_cancelInterview' SIGINT
        while true; do
            f_interview
            _echo "Interview completed."
            f_ask "Would you like to save your response?" "Y"
            if _isYes; then
                break
            else
                echo ""
                f_ask "Would you like to re-do the interview?" "Y"
                if ! _isYes; then
                    _echo "Continuing without saving..."
                    break
                fi
            fi
        done
        trap - SIGINT
        
        _endOfInterview
        f_checkUpdate
    else
        _echo "Response file: ${g_response_file}"
        #f_ask "Would you like to load this file?" "Y"
        #if ! _isYes; then _echo "Bye."; exit 0; fi
        f_loadResp
        
        f_ask "Would you like to review your responses?" "N"
        if _isYes; then
            g_force_default=false
            f_interview
            echo ""
            f_ask "Would you like to re-save your response?" "Y"
            if _isYes; then
                _endOfInterview
            fi
        fi
    fi
}

function _endOfInterview() {
    f_ask "Response file path" "${g_default_response_file}" "g_response_file"
    f_ask "Would you like to archive and encrypt your response file?" "N" "r_response_encrypt"
    _echo "Saving your response..."
    f_saveResp "$g_response_file" "$r_response_encrypt"
    echo "Please store your response file in safe place."
}

function _cancelInterview() {
    echo ""
    echo ""
    echo "Exiting..."
    f_ask "Would you like to save your current responses?" "N" "is_saving_resp"
    if _isYes "$is_saving_resp"; then
        _endOfInterview
    fi
    _exit
}

function _askSvnUser() {
    if [ -z "${r_svn_user}" ]; then
        # if middle of build script process, do nothing.
        if $g_is_script_running; then
            return 1
        else
            f_ask "SVN username" "" "r_svn_user" "" "Y"
            f_ask "Password" "" "r_svn_pass" "Y" "Y"
        fi
    fi
    return 0
}

### OS/Package functions ######################################################
function f_startInstallations() {
    local __doc__="Install OS packages, setting up database and web server (non Build specific)."
    
    # create directories
    _info "Creating directories if it does not exist..."
    f_makeDirs
    
    _info "Setting up OS and Packages..."
    f_setupOS
    
    _info "Installing Database (PostgreSQL)..."
    f_installPostgresqlForBuild
    
    _info "Setting up Database (PostgreSQL)..."
    f_setupPostgresqlForBuild
    
    _info "Installing Web server (Apache/PHP)..."
    f_installApacheAndPhp
    
    _info "Setting up Web server (Apache/PHP)..."
    f_setupApache
    f_setupPhp
    
    if [ "$r_server_type" = "prod-db" ]; then
        _info "Stopping Apache as per server type: $r_server_type"
        _eval "sysv-rc-conf apache2 off"
        _eval "service apache2 stop"
    elif [ "$r_server_type" = "prod-web" ]; then
        _info "Stopping Postgres as per server type: $r_server_type"
        _eval "sysv-rc-conf postgresql off"
        _eval "service postgresql stop"
    fi
}

function f_setupOS() {
    local __doc__="Install and setting up OS packages excluding Web and DB related packages."
    
    if [ -n "$r_new_hostname" ]; then
        _info "Changing hostname to $r_new_hostname"
        f_setHostname "$r_new_hostname"
    fi
    
    if _isYes "$r_config_nic"; then
        _info "Configuring NIC $r_nic_name to $r_nic_address"
        f_setupNIC "$r_nic_name" "$r_nic_address" "$r_nic_netmask" "$r_nic_gateway" "$r_nic_nameservers" "$r_nic_search"
    fi
    
    if _isYes "$r_config_proxy"; then
        _info "Configuring System-wide proxy"
        f_setupProxy "$r_proxy_address" "$r_proxy_exclude_list"
    fi
    
    _info "Setting up apt-get proxy..."
    f_setupAptProxy
    
    _eval "apt-get update" || _critical "$FUNCNAME: apt-get update failed."
    
    local _cmd="apt-get install ${g_apt_packages}"
    
    if _isYes "$r_aptget_with_y" ; then
        _cmd="apt-get -y install ${g_apt_packages}"
    fi
    
    f_setupNtpUpdate
    
    f_installSar
    
    f_installSmtp
    
    f_installSsh
    
    _eval "$_cmd" || _critical "$FUNCNAME: apt-get failed"
    
    f_installSvn
    
    f_installWkhtmltopdf
    
    f_installSnmpd
    
    f_installTmpreaper
    
    if _isYes "$r_vmware_tools" ; then
        _info "Installing VMWare Tools..."
        f_installVmwareTools
    fi
    
    if _isYes "$r_add_build_dev" ; then
        f_addBuildDevUsers
        f_addSystemUsers
    fi
    
    if [ -n "$r_admin_mail" ]; then
        f_setupRootEmail
        
        if [ "$r_server_type" = "dev" ]; then
            _info "Redirecting all e-mail to $r_admin_mail"
            f_setupEmailRedirect
        fi
    fi
    
    if _isYes "$r_auto_security_updates" ; then
        f_setupAutoSecurityUpdates
    fi
    
    _info "Setting up Log Rotate..."
    f_setupLogrotate
    
    _info "Setting up hourly monitoring..."
    f_setupMonitoring
}

function f_makeDirs() {
    local __doc__="Create directories spacified in g_make_dir_list for Build"
    local _permission="$1"
    
    for d in "${g_make_dir_list[@]}"; do
        if [ -n "$_permission" ]; then
            _mkdir "$d" "$_permission"
        else
            _mkdir "$d"
        fi
    done
}

function f_addBuildDevUsers() {
    local __doc__="Add all Build developers as OS users."
    local _username_var_name=""
    local _password_var_name=""
    local _is_super_var_name=""
    local _public_k_var_name=""
    local _lg_shell_var_name=""
    
    for _u in `seq 1 9`; do
        _username_var_name="g_os_username_${_u}"
        
        if [ -n "${!_username_var_name}" ]; then
            _password_var_name="g_default_password"
            _is_super_var_name="g_os_is_super_${_u}"
            _lg_shell_var_name="g_os_lg_shell_${_u}"
            _public_k_var_name="g_os_public_k_${_u}"
            
            _info "Adding user:${!_username_var_name} and his/her public key..."
            # FIXME: not checking f_addUserAndKey result...
            f_addUserAndKey "${!_username_var_name}" "${!_password_var_name}" "${!_is_super_var_name}" "${!_lg_shell_var_name}" "${!_public_k_var_name}"
        fi
    done
}

function f_installSsh() {
    local __doc__="Install SSH packages and configure."
    local _conf_file="/etc/ssh/sshd_config"
    
    _eval "apt-get -y install openssh-server autossh rssh" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing SSH packages failed."; return 1; fi
    
    f_backup "$_conf_file"
    
    f_setConfig "$_conf_file" "PermitRootLogin" "no" "#" " "
    
    if _isYes "$r_disable_ssh_pauth" ; then
        f_setConfig "$_conf_file" "ChallengeResponseAuthentication" "no" "#" " "
        f_setConfig "$_conf_file" "PasswordAuthentication" "no" "#" " "
        #f_setConfig "$_conf_file" "UsePAM" "no" "#" " "        # This also disable motd (I like this)
        f_setConfig "$_conf_file" "PubkeyAuthentication" "yes" "#" " "
    fi
    
    # setting up restrict shell
    f_backup "/etc/rssh.conf"
    f_setConfig "/etc/rssh.conf" "allowscp" "" "#" ""
    f_setConfig "/etc/rssh.conf" "allowsftp" "" "#" ""
    f_setConfig "/etc/rssh.conf" "allowrsync" "" "#" ""
    f_setConfig "/etc/rssh.conf" "allowsvnserve" "" "#" ""
    
    _eval "service ssh restart" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Starting sshd failed."; return 1; fi
    return 0
}

function f_installSvn() {
    local __doc__="Install SVN 1.7 package."
    
    svn --version 2>/dev/null | grep 'version 1.7'
    if [ $? -ne 0 ]; then
        local _conf_file="/etc/apt/sources.list.d/svn-ppa-precise.list"
        if [ ! -s "$_conf_file" ]; then
            _eval "echo | apt-add-repository ppa:svn/ppa && apt-get update"
            
            if [ $? -ne 0 ]; then
                f_backup "$_conf_file"
                f_appendLine "$_conf_file" "deb http://ppa.launchpad.net/svn/ppa/ubuntu precise main"
                f_appendLine "$_conf_file" "deb-src http://ppa.launchpad.net/svn/ppa/ubuntu precise main"
                _eval "apt-get update" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: apt-get update failed"; return 1; fi
                # FXIME: above always return 0 even it fails...
                _warn "$FUNCNAME: Please run 'apt-key adv --keyserver keyserver.ubuntu.com --recv-keys XXXXXXXX'"
                return 1
            fi
        fi
        
        _eval "apt-get -y install subversion --force-yes; svn --version | grep 'version 1.7'"
        if [ $? -ne 0 ]; then
            _warn "$FUNCNAME: Installing SVN package failed."
            return 1
        fi
    fi
    return 0
}

function f_installTmpreaper() {
    local __doc__="Install and set up Temp cleaner"
    local _conf_file="/etc/tmpreaper.conf"
    local _date="${1-14d}"
    
    if _isYes "$r_aptget_with_y"; then
        # FIXME: noninteractive occationally does not work
        _eval "DEBIAN_FRONTEND=noninteractive apt-get -y install tmpreaper"
    else
        _eval "apt-get install tmpreaper"
    fi
    _checkLastRC "$FUNCNAME: Installing tmpreaper package failed."
    
    f_backup "$_conf_file"
    f_setConfig "$_conf_file" "SHOWWARNING" "false"
    # FIXME: this replace a comment line (but it works)
    f_setConfig "$_conf_file" "TMPREAPER_TIME" "$_date"
}

function f_installSar() {
    local __doc__="Install and setup sar/sysstat"
    local _conf_file="/etc/default/sysstat"
    
    if _isYes "$r_aptget_with_y"; then
        _eval "apt-get -y install sysstat"
    else
        _eval "apt-get install sysstat"
    fi
    _checkLastRC "$FUNCNAME: Installing sysstat package failed."
    
    f_backup "$_conf_file"
    
    f_setConfig "$_conf_file" "ENABLED" "\"true\""
    _eval "/etc/init.d/sysstat start"
    return $?
}

function f_installSmtp() {
    local __doc__="Install SMTP package (postfix) and configure."
    local _relay_host="${1-${r_relay_host}}"
    local _admin_mail="${2-${r_admin_mail}}"
    local _conf_file="/etc/postfix/main.cf"
    
    if _isYes "$r_aptget_with_y"; then
        # FIXME: noninteractive does not work
        _eval "DEBIAN_FRONTEND=noninteractive apt-get -y install postfix"
    else
        _eval "apt-get install postfix"
    fi
    _checkLastRC "$FUNCNAME: Installing Postfix package failed."
    
    f_backup "$_conf_file"
    
    if [ -n "$_relay_host" ]; then
        f_setConfig "$_conf_file" "relayhost" "$_relay_host"
    fi
    
    _eval "touch /etc/postfix/generic"
    f_setConfig "$_conf_file" "smtp_generic_maps" "hash:/etc/postfix/generic"
    
    _eval "/etc/init.d/postfix restart" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: starting postfix failed."; return 1; fi
    return 0
}

function f_installWkhtmltopdf() {
    local __doc__="Install wkhtmltopdf related packages and configure."
    
    if [ -L /usr/local/bin/wkhtmltopdf ]; then
        _info "looks like wkhtmltopdf has been installed. Skipping..."
        return 0
    fi
    
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    # ref: https://code.google.com/p/wkhtmltopdf/wiki/compilation
    # ref: https://code.google.com/p/wkhtmltopdf/downloads/list?can=2&q=wkhtmltopdf
    _eval "${_apt_get} remove --purge wkhtmltopdf"
    
    _info "Downloading wkhtmltopdf ..."
    local _wget_cmd="wget -q -t 2 https://wkhtmltopdf.googlecode.com/files/wkhtmltopdf-0.9.9-static-amd64.tar.bz2"
    if [ -n "$r_svn_user" ]; then
        _wget_cmd="wget -q -t 2 --http-user=${r_svn_user} --http-passwd=${r_svn_pass} ${g_svn_url%/}/installers/trunk/wkhtmltopdf-0.9.9-static-amd64.tar.bz2"
    fi
    
    if $g_is_dryrun ; then return 0; fi
    
    mkdir /opt/wkhtmltopdf
    cd /opt/wkhtmltopdf && $_wget_cmd && tar -xvf wkhtmltopdf-0.9.9-static-amd64.tar.bz2 && _eval "ln -s /opt/wkhtmltopdf/wkhtmltopdf-amd64 /usr/local/bin/wkhtmltopdf"
    cd - >/dev/null
    _checkLastRC "$FUNCNAME: Linking wkhtmltopdf failed."
    return 0
}

function f_installVmwareTools() {
    local __doc__="Install VMware Tools."
    local _current_file="VMwareTools-8.6.0-425873.tar.gz"
    
    if [ -e /usr/bin/vmware-config-tools.pl ]; then
        _info "looks like Vmware Tools have been installed. Skipping..."
        return 0
    fi
    
    if ! _askSvnUser ; then
        _warn "$FUNCNAME: No SVN username. Exiting."; return 1
    fi
    
    if $g_is_dryrun ; then return 0; fi
    
    _eval "mkdir /opt/vmwaretools && cd /opt/vmwaretools" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not make a dir under /opt"; return 1; fi
    f_getFromSvn "/installers/trunk/${_current_file}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Downloading /installers/trunk/${_current_file} failed."; return 1; fi
    _eval "tar -xzvf ${_current_file}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Extracting /installers/trunk/${_current_file} failed."; return 1; fi
    _eval "./vmware-tools-distrib/vmware-install.pl -d"
    _eval "cd - >/dev/null" "N"
    _checkLastRC "$FUNCNAME: VMware tools failed."
    _warn "$FUNCNAME: Install completed but please reboot this system later."
    return 0
}

function f_installSnmpd() {
    local __doc__="Install and set up SNMPd"
    local _conf_file="/etc/snmp/snmpd.conf"
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    _eval "$_apt_get install snmpd" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing SNMPd package failed."; return $g_last_rc; fi
    
    f_backup "$_conf_file"
    
    if [ ! -e "${_conf_file}.orig" ]; then
        _eval "mv ${_conf_file} ${_conf_file}.orig && touch ${_conf_file}"
    fi
    
    # Ubuntu bug workaround: https://bugs.launchpad.net/ubuntu/+source/net-snmp/+bug/1246347
    if [ -s "/etc/default/snmpd" ]; then
        f_backup "/etc/default/snmpd"
        _eval "sed -i '/^SNMPDOPTS=/s/\blsd\b/LS6d/i' /etc/default/snmpd"
        _eval "sed -i '/^TRAPDOPTS=/s/\blsd\b/LS6d/i' /etc/default/snmpd"
    fi
    
    grep -w "builddev" $_conf_file &>/dev/null
    if [ $? -ne 0 ]; then
        f_setConfig "$_conf_file" "syslocation" "AU/BNE/Server Room" "#" " "
        f_setConfig "$_conf_file" "syscontact" "BNE.IT@testdomain.com" "#" " "
        f_setConfig "$_conf_file" "sysservices" "76" "#" " "
        f_setConfig "$_conf_file" "rocommunity public" "$g_it_mgmt_server" "#" " "
        f_setConfig "$_conf_file" "rocommunity builddev" "$g_key_server_ip" "#" " "
        f_setConfig "$_conf_file" "disk" "/ 15%" "#" " "
        f_setConfig "$_conf_file" "load" "10 8 8" "#" " "
        f_setConfig "$_conf_file" "master" "no" "#" " "       # Do we need this?
        
        _eval "chmod 600 $_conf_file"
        _eval "service snmpd restart" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: starting SNMPd failed."; return $g_last_rc; fi
    fi
    
    return 0
}

function f_installApprox() {
    local __doc__="Install and set up approx which is apt package proxy/cache.
NOTE: Have not tested this function yet."
    local _conf_file="/etc/approx/approx.conf"
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    _eval "$_apt_get install approx" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing Approx package failed."; return $g_last_rc; fi
    
    f_backup "$_conf_file"
    
    if [ ! -e "${_conf_file}.orig" ]; then
        _eval "mv ${_conf_file} ${_conf_file}.orig && touch ${_conf_file}"
    fi
    
    f_setConfig "$_conf_file" "ubuntu" "http://au.archive.ubuntu.com/ubuntu" "#" " "
    f_setConfig "$_conf_file" "ubuntu-security" "http://security.ubuntu.com/ubuntu" "#" " "
    f_setConfig "$_conf_file" "partner" "http://archive.canonical.com/ubuntu" "#" " "
    f_setConfig "$_conf_file" "svn" "http://ppa.launchpad.net/svn" "#" " "
    f_setConfig "$_conf_file" "pitti" "http://ppa.launchpad.net/pitti" "#" " "
    f_setConfig "$_conf_file" "ppa" "http://ppa.launchpad.net" "#" " "
    f_setConfig "$_conf_file" "debian" "http://mirror.internode.on.net/pub/debian" "#" " "
    
    _warn "Completed. Please run 'f_setupApproxClient \"IP_OF_PROXY\"' on each server."
    return 0
}

function f_setupApproxClient() {
    local __doc__="Modify sources.list for approx (f_installApprox)"
    local _proxy_ip="$1"
    local _conf_file="/etc/apt/sources.list"
    local _proxy_hostname="apt-proxy"
    
    if ! _isIp "$_proxy_ip"; then
        _warn "$FUNCNAME: given IP $_proxy_ip does not look like an IP"
        return 1
    fi
    
    f_backup "$_conf_file"
    
    _eval "sed -i 's/au.archive.ubuntu.com/${_proxy_hostname}:9999/g' $_conf_file"
    _eval "sed -i 's/pg.archive.ubuntu.com/${_proxy_hostname}:9999/g' $_conf_file"
    _eval "sed -i 's/security.ubuntu.com/${_proxy_hostname}:9999/g' $_conf_file"
    _eval "sed -i 's/ppa.launchpad.net/${_proxy_hostname}:9999/g' $_conf_file"

    #To roleback the change (as no backup): _eval "sed -i 's/${_proxy_hostname}:9999/ppa.launchpad.net/g' /etc/apt/sources.list.d/*"
    _eval "sed -i 's/ppa.launchpad.net/${_proxy_hostname}:9999/g' /etc/apt/sources.list.d/*"
    
    f_setConfig "/etc/hosts" "$_proxy_ip" "${_proxy_hostname}" "#" " " "Y" " " 
    return $?
}

function f_addSystemUsers() {
    local __doc__="Add Build system users (itsupport/${g_system_user}/${g_automation_user})\nNOTE: keys for these users are stored or should be stored in ${g_key_server_ip}."
    
    local _hostname="$g_hostname"
    if [ -n "$r_new_hostname" ]; then _hostname="$r_new_hostname"; fi
    
    _info "Creating a restricted user 'itsupport' who can do some service restart and OS reboot"
    
    f_addUserAndKey "itsupport" "$g_default_password" "N" "/bin/bash" "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCojDaRg2LwPwzbm30EJbt/XDiBvp+bZHdpZMmWY7NowmeU+iC6gujHlASgVTSAt7GtZ4JweSWip8CncsbZVvKKKcwyWtm3PfkpRCHgrvHyj9alp2Hj745QHqnyIYLq4BZM67YkYIRCUu6bEu0A8Ya4VH1tVhKWdleeaXF1HnfAx18zmZ0NYdwTTjZG00WuEFWzywdIKDfVhWedF6eUTxaSU38T6XIP10jxoSXOzEuWyq3Wkbtd7Ts7rN7tTDuia8IiiVptnmZ0KBWrRsKvOl6K4IhGM8jwa5uBXcdPjrrdtNoYbsJYgLPccA0eBSssAcnP5H+bRBKvSdbyGkqHJqUj itsupport@BNEDEV01"
    
    if [ $? -eq 0 ]; then
        # set up sudo for itsupport
        local _sudo_inc="Host_Alias HOST = ${_hostname}\nitsupport HOST = (root) NOPASSWD: /usr/sbin/service apache2 restart,/usr/sbin/service postgresql restart,/sbin/reboot,/sbin/shutdown"
        echo -e "$_sudo_inc" > /tmp/itsupport_sudo
        chown root:root /tmp/itsupport_sudo
        chmod 0440 /tmp/itsupport_sudo
        mv /tmp/itsupport_sudo /etc/sudoers.d/
    else
        _warn "$FUNCNAME: f_addUserAndKey itsupport failed, but keep going..."
    fi
    
    _info "Creating a restricted user '${g_automation_user}' who does not have sudo but empty passphrase for automated tasks"
    _addAutomationUser ; if [ $? -ne 0 ]; then _error "$FUNCNAME: _addAutomationUser failed."; return 1; fi
    
    _info "Creating a local system user '${g_system_user}' who should be able to access remotely."
    f_addOsUser "${g_system_user}" "${g_default_password}" "Y" "N"
    
    return $?
}

function _addAutomationUser() {
    local _password="$(f_getBuildConfigValueFromSvn "core.automation.password")"
    
    if [ -z "$_password" ]; then
        _password="$g_default_password"
    fi
    
    f_addUserAndKey "${g_automation_user}" "$_password" "N" "/bin/bash" "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDu2H4yKvUVSTXLfAO6sFXuxVNaKF1znclfGyqCXwRWCi876+7iDJt7UYfov678+hU0HuoLMUlqsPnSbeA0XQ95DVgFgocprIQL0H+EtcyvqWYclk1Y+7770IN4cut39rpTf1ScMqDxW8ovte+D2iedeq/fYEpVz92YAfPhiS7wZhq4tIE9yjBuZmU23zd5nxxdtmpo7nUW0FhNOVul6zkAgl6hyyx/x3X13LbUki2LNZnTvhN02+XE/BItpRLNB1wV+2pcl0LmiHmuXYCBuxypnJHKuqvAXByxrnQ6hb9lBOW7Avz4IMIc2rHqZBw6HyAK+hpry8eqnwNG2mBmuAhf ${g_automation_user}@BNEDEV01"
    
    # buildautomation needs to be in www-data group for rsync job
    _eval "usermod -G ${g_apache_user} ${g_automation_user}"
    return $?
}

function f_copyAutomationUserRsaKey() {
    local __doc__="Be CAREFULL. This script copies '${g_automation_user}' private key into this server.
This function should be run only when necessary."
    local _copy_to="$1"
    local _force="$2"
    local _conf_file="/home/${g_automation_user}/.ssh/id_rsa"
    
    if [ -z "$_copy_to" ]; then
        _copy_to="$_conf_file"
    fi
    
    if [ -s "$_copy_to" ]; then
        chmod 600 ${_copy_to}* && chown ${g_automation_user}:${g_automation_user} ${_copy_to}*
        
        if [ ! -s "${_copy_to}.pub" ]; then
            _eval "ssh-keygen -y -f ${_copy_to} > ${_copy_to}.pub" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Generating public key failed."; return 1; fi
        fi
        
        if ! _isYes "$_force"; then
            _info "$FUNCNAME: id_rsa file exists. Skipping..."
            return 0
        fi
    fi
    
    if [ ! -d "/home/${g_automation_user}/.ssh" ]; then
        _info "$FUNCNAME: Adding OS user ${g_automation_user}..."
        _addAutomationUser
    fi
    
    # /build/trunk/site/utils/utility-scripts/monitoring/buildautomation_id_rsa
    f_getFromSvn "/build/trunk/site/utils/utility-scripts/monitoring/${g_automation_user}_id_rsa" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Downloading ${g_automation_user} key failed."; return 1; fi
    _eval "mv ./${g_automation_user}_id_rsa ${_copy_to}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Renaming id_rsa key failed."; return 1; fi
    _eval "chmod 600 ${_copy_to} && chown ${g_automation_user}:${g_automation_user} ${_copy_to}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: setting permissions on key failed."; return 1; fi
    _eval "ssh-keygen -y -f ${_copy_to} > ${_copy_to}.pub" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Generating public key failed."; return 1; fi
    _eval "chmod 600 ${_copy_to}.pub && chown ${g_automation_user}:${g_automation_user} ${_copy_to}.pub"
    return $?
}

function f_addUserAndKey() {
    local __doc__="Add/create one OS user and save given public key to user's home directory."
    
    local _username="$1"
    local _password="$2"
    local _is_super="$3"
    local _lg_shell="$4"
    local _public_k="$5"
    
    f_addOsUser "${_username}" "${_password}" "${_is_super}" "N" "${_lg_shell}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: f_addOsUser failed"; return 1; fi
    
    if [ -n "$_public_k" ]; then
        _eval "mkdir -m 700 /home/${_username}/.ssh && echo \"${_public_k}\" >> /home/${_username}/.ssh/authorized_keys && chmod 600 /home/${_username}/.ssh/authorized_keys" "" "${_username}"
        return $?
    else
        return $?
    fi
}

function f_addOsUser() {
    local __doc__="Add/create one OS user."
    local _username="$(_escape_quote "$1")"
    local _password="$(_escape_quote "$2")"
    local _is_super="$3"
    local _is_system_user="$4"
    local _lg_shell="$(_escape_quote "$5")"
    local _lg_home="$(_escape_quote "$6")"
    local _extra_option="$(_escape_quote "$7")"
    local _useradd_option=""
    local _orig_is_verbose=$g_is_verbose
    g_last_rc=0
    
    if _isYes "$_is_system_user"; then
        _useradd_option="${_useradd_option} -r"
    fi
    
    if [ -z "$_lg_shell" ]; then
        _useradd_option="${_useradd_option} -s /bin/bash"
    else
        _useradd_option="${_useradd_option} -s ${_lg_shell}"
    fi
    
    if [ -z "$_lg_home" ]; then
        if [ ! -d "/home/${_username}" ]; then
            _useradd_option="${_useradd_option} -m -d /home/${_username}"
        else
            _useradd_option="${_useradd_option} -d /home/${_username}"
        fi
    else
        if [ ! -d "${_lg_home}" ]; then
            _warn "$FUNCNAME: Please create ${_lg_home} later."
        fi
        _useradd_option="${_useradd_option} -d ${_lg_home}"
    fi
    
    if [ -n "$_username" ]; then
        grep -w "^$_username" /etc/passwd >/dev/null
        if [ $? -eq 0 ]; then
            _warn "$FUNCNAME: $_username already exists. Skipping..."
            return 0
        fi
        
        _info "Adding user: ${_username}"
        g_is_verbose=false
        
        _eval "useradd ${_useradd_option} ${_extra_option} '${_username}'" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: useradd failed for ${_username}"; return 1; fi
        
        if [ -n "$_password" ]; then
            f_changePassword "${_username}" "${_password}"
        fi
        
        f_changeToSuper "${_username}" "${_is_super}"
        
        g_is_verbose=$_orig_is_verbose
    else
        _warn "$FUNCNAME: Empty username."
        g_last_rc=1
    fi
    
    return $g_last_rc
}

function f_changeToSuper() {
    local __doc__="Change given OS user to super (sudo) user.\nNote revoking sudo permission for Ubuntu is very hard, so be careful."
    
    local _username=$1
    local _is_super=$2
    
    if [ -z "$_username" ]; then
        _warn "$FUNCNAME: Empty username."
        g_last_rc=1
    elif _isYes "$_is_super" ; then 
        _eval "usermod -a -G sudo ${_username}"
    fi
    
    return $g_last_rc
}

function f_changePassword() {
    local __doc__="Change given OS user's password."
    local _username="$1"
    local _password="$2"
    
    if [ -z "$_username" ]; then
        _warn "$FUNCNAME: Empty username."
        return 1
    fi
    
    if [ -z "$_password" ]; then
        _warn "$FUNCNAME: Empty pasword. Skipping..."
        return 0
    fi
    
    if $g_is_dryrun ; then return 0; fi
    
    expect -c "
spawn passwd ${_username}
expect Enter\ ;  send ${_password}; send \r
expect Retype\ ; send ${_password}; send \r;
expect eof exit 0^C
" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: expect failed for user ${_username}"; return 1; fi
    
    if [ "${_password}" = "${g_default_password}" ]; then
        _eval "chage -d 0 ${_username}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: chage failed for user ${_username}"; return 1; fi
    fi
    
    return 0
}

#function f_getPubKeyFromRemote() {
#    # FIXME: get key information from g_key_server
#    local _pub_key_server_ip="$1"
#}

function f_copyPubKey() {
    local __doc__="Push a public key to given username@hostname."
    local _username_hostname="$1"
    local _password="$2"
    local _private_key_path="$3"
    local _private_key_create="${4-$r_ssh_key_create}"
    local _public_key_path="${_private_key_path}.pub"
    g_last_rc=0
    
    if [ -z "$_private_key_path" ]; then
        _info "$FUNCNAME: No private key path. using ${g_default_key_path}"
        _private_key_path=${g_default_key_path}
    fi
    
    local _extension="${_private_key_path##*.}"
    if [ "$_extension" = "pub" ]; then
        _private_key_path="${_private_key_path%.*}"
        _public_key_path="${_private_key_path}"
    fi
    
    if [ -z "$_username_hostname" ]; then
        _warn "$FUNCNAME: Empty username@hostname."
        g_last_rc=1
        return $g_last_rc
    fi
    
    if [ ! -f "$_private_key_path" ]; then
        if _isYes "$_private_key_create" ; then
            _info "$FUNCNAME: ${_private_key_path} does not exist. Generating..."
            local _tmp_ssh_key_passphrase="$(_escape_quote "${r_ssh_key_passphrase}")"
            _eval "ssh-keygen -N '${_tmp_ssh_key_passphrase}' -f ${_private_key_path}" "N"
        fi
    fi
    
    ssh -q -i "$_private_key_path" -o StrictHostKeyChecking=no -o BatchMode=yes ${_username_hostname} 'echo "SSH connection test before copying key."'
    if [ $? -ne 0 ] ; then
        _expect "ssh-copy-id -i ${_public_key_path} ${_username_hostname}" "$_password"
        g_last_rc=$?
        _info "$FUNCNAME: Finished to set up public key authentication."
    else
        _info "$FUNCNAME: Looks like already set up."
    fi
    
    return $g_last_rc
}

function f_rsync() {
    local __doc__="Rsync with ssh with retry, for example, this function retries below command {_retry_num} times:
    rsync {_rsync_opt} --partial -e 'ssh {_ssh_opt}' {_source} {_destination}
{_ssh_opt} is like '-i /home/$g_automation_user/.ssh/id_rsa'."
    local _source="$1"
    local _destination="$2"
    local _rsync_opt="${3-"-avz"}"
    local _ssh_opt="$4"
    local _is_password_auth="${5-N}"
    local _retry_num="${6-5}"
    
    if [ -z "$_rsync_opt" ]; then
        _rsync_opt="-avz"
        _info "Rsync option: $_rsync_opt"
    fi
    
    if _isYes "$_is_password_auth"; then
        f_ask "Password" "" "__rsync_password" "Y" "Y"
    fi
    
    local _username=""
    # deleting hostname directory path to get username
    if [[ "${_source}" =~ @ ]]; then
        _username="$(echo "${_source}" | sed -r 's/@.+$//g')"
    elif [[ "${_destination}" =~ @ ]]; then
        _username="$(echo "${_destination}" | sed -r 's/@.+$//g')"
    fi
    
    # FIXME: this one does not consider username which contains funny characters
    if [ -z "$_ssh_opt" ] && [ -n "$_username" ] && [ -s "/home/${_username}/.ssh/id_rsa" ]; then
        _ssh_opt="-i /home/${_username}/.ssh/id_rsa"
    fi
    
    local _e="-e 'ssh ${_ssh_opt}'"
    if [ -z "$_ssh_opt" ]; then
        if [[ ! "${_source}" =~ : ]] && [[ ! "${_destination}" =~ : ]]; then
            _info "Not using SSH as it looks like local to local copy."
            _e=""
            __rsync_password=""
        fi
    fi
    
    trap "_exit" SIGINT
    
    local i=0
    local _rsync_rc=1
    # FIXME: to support wildcard, not using quotes, so if source or dest contains space, does not work.
    local _cmd="rsync ${_rsync_opt} --partial ${_e} ${_source} ${_destination}"
    
    while [ $_rsync_rc -ne 0 -a $i -lt $_retry_num ]; do
        i=$(($i+1))
        if [ -n "$__rsync_password" ]; then
            _expect "$_cmd" "$__rsync_password"
        else
            _eval "$_cmd"
        fi
        _rsync_rc=$?
        sleep 2
        # FXIME: Maybe rsync has own trap?
        if [ $_rsync_rc = 130 ]; then
            echo ""
            _info "Keyboard Intruptted. Exiting..."
            break;
        fi
    done
    
    trap - SIGINT
    
    if [ $i -eq $_retry_num ]
    then
        _echo "Hit maximum number of retries, giving up."
    fi
    
    return $_rsync_rc
}

function f_scp() {
    local __doc__="run given scp command with Expect (to automate password input)"
    local _scp_cmd="$1"
    local _password="$2"
    local _username="$(echo $_scp_cmd | grep -P -o "[^\s]+@")"
    _username="${_username%@}"
    local _username_hostname="$(echo $_scp_cmd | grep -P -o "[^\s]+:")"
    _username_hostname="${_username_hostname%:}"
    g_last_rc=0
    
    if [ -z "$_username_hostname" ]; then
        _warn "$FUNCNAME: Could not find username@hostname from ${_scp_cmd}."
        g_last_rc=1
        return $g_last_rc
    fi
    
    _echo "scp $_scp_cmd"
    
    if ! $g_is_dryrun ; then 
        if [ -z "$_username" ]; then
            _username="$USER"
        elif [ "$_username" = "$g_automation_user" ]; then
            f_copyAutomationUserRsaKey
            
            # buildautomation should NOT need password
            #if [ -z "$_password" ]; then
            #    _password="$(f_getBuildConfigValueFromSvn "core.automation.password")"
            #fi
        fi
        
        local _key_path="/home/${_username}/.ssh/id_rsa"
        local _option=""
        if [ -s "$_key_path" ]; then
            _option="-i $_key_path"
        fi
        
        ssh -q ${_option} -o StrictHostKeyChecking=no -o BatchMode=yes ${_username_hostname} 'echo "SSH connection test before scping."'
        
        if [ $? -ne 0 ] ; then
            _expect "scp ${_option} ${_scp_cmd}"
            g_last_rc=$?
        else
            _eval "scp ${_option} ${_scp_cmd}"
        fi
    fi
    return $g_last_rc
}

function _expect() {
    local _command="$1"
    local _passphrase="$2"
    local _password="$3"
    local _timeout="${4-1800}"
    #local _tmp_out="/tmp/tmp_expect_${g_pid}.out"
    local _last_rc=0
    
    if [ -z "$_command" ]; then
        _warn "$FUNCNAME: command is mandatory."
        return 1
    fi
    
    if [ -z "$_password" ]; then
        _password="$_passphrase"
    fi
    
    if $g_is_dryrun ; then return 0; fi
    
    expect -c "
set timeout ${_timeout}
spawn -noecho ${_command}
expect {
    \"*nter passphrase *\" { send \"${_passphrase}\n\" }
    \"*assword:*\" { send \"${_password}\n\" }
    \"*password for*\" { send \"${_password}\n\" }
    \"*you want to continue connecting*\" { send \"yes\n\"; expect { \"*assword:*\"; send \"${_password}\n\" \"*nter passphrase *\" send \"${_passphrase}\n\" } }
    eof { exit }
}
interact"
    
    _last_rc=$?
    if [ $_last_rc -ne 0 ]; then
        _warn "$FUNCNAME: expect $_command failed."
        return $_last_rc
    fi
    
    #rm -f ${_tmp_out}
    return $_last_rc
}

function f_setupRootEmail() {
    local __doc__="Set root user's e-mail, so that notifiation (ex:cron job) on this server will be sent to this address."
    local _email="${1-$r_admin_mail}"
    local _server_type="${2-$r_server_type}"
    local _db_entity="${3-$r_db_entity}"
    local _conf_file="/etc/aliases"
    local _do_not_reply="$_email"
    
    if ! _isEmail "${_email}" ; then
        _warn "$FUNCNAME: No admin e-mail to set. Skipping..."
        return 1
    fi
    
    if [ "$_server_type" != "dev" ]; then
        if [ "$_db_entity" != "$g_default_entity_name" ]; then
            _do_not_reply="${g_non_delivery_mailuser}@morobejv.com"
        else
            _do_not_reply="${g_non_delivery_mailuser}@testdomain.com"
        fi
    fi
    
    if [ -z "$_db_entity" ]; then
        _info "DB entity is empty so that using $g_default_entity_name..."
        _db_entity="$g_default_entity_name"
    fi
    
    f_setConfig "/etc/postfix/generic" "root" "$_email" "#" " "
    f_setConfig "/etc/postfix/generic" "www-data" "$_do_not_reply" "#" " "
    
    _eval "postmap hash:/etc/postfix/generic"
    if [ $g_last_rc -ne 0 ]; then
        _warn "$FUNCNAME: postmap error" "$g_last_rc"
        return $g_last_rc
    fi
    
    f_backup "$_conf_file" || _eval "touch $_conf_file"
    f_setConfig "$_conf_file" "postmaster" "${_email}" "#" ": "
    f_setConfig "$_conf_file" "root" "${_email}" "#" ": "
    f_setConfig "$_conf_file" "www-data" "$_do_not_reply" "#" ": "
    
    _eval "newaliases"
    if [ $g_last_rc -ne 0 ]; then
        _warn "$FUNCNAME: newaliases error" "$g_last_rc"
        return $g_last_rc
    fi
    
    _eval "service postfix restart"
    return $?
}

function f_setupEmailRedirect() {
    local __doc__="Redirect all e-mail to given mail address."
    local _redirect_to="${1-$r_admin_mail}"
    local _conf_file="/etc/postfix/main.cf"
    
    if ! _isEmail "$_redirect_to" ; then
        _warn "$FUNCNAME: given $_redirect_to does not look like an e-mail address."
        return 1
    fi
    
    f_backup "/etc/postfix/recipient_canonical_map"
    f_appendLine "/etc/postfix/recipient_canonical_map" "/./ ${_redirect_to}"
    
    f_backup "$_conf_file"
    f_appendLine "$_conf_file" "recipient_canonical_classes = envelope_recipient"
    f_appendLine "$_conf_file" "recipient_canonical_maps = regexp:/etc/postfix/recipient_canonical_map"
    
    _eval "service postfix restart"
    return $?
}

function f_setHostname() {
    local _new_name="$1"
    
    if [ -z "$_new_name" ]; then
        _warn "$FUNCNAME: No new hostname given. exiting..."
        return 0
    fi
    
    f_backup "/etc/hostname"
    _eval "hostname $_new_name"
    _eval "echo \"$_new_name\" > /etc/hostname"
    f_backup "/etc/hosts"
    f_setConfig "/etc/hosts" "127.0.1.1" "$_new_name" "#" "\t"
    return $?
}

function f_setupNIC() {
    local __doc__="Set up ethX. default is eth1 and DHCP.
_netmask, _gateway, _nameservers and _search are optional parameters"
    local _nic="${1-eth1}"
    local _address="${2-dhcp}"
    local _netmask="$3"
    local _gateway="$4"
    local _nameservers="$5"
    local _search="$6"
    local _conf_file="/etc/network/interfaces"
    local _type="static"
    
    if [ -z $_address ]; then
        _address="dhcp"
    fi
    if [ "$_address" = "dhcp" ]; then
        _type="dhcp"
    fi
    
    if [[ "$_nic" =~ $g_ip_regex ]]; then
        _warn "$FUNCNAME: The first argument is for interface name (ex: eth1)"
        return 1
    fi
    
    _info "Editing $_conf_file"
    f_backup "$_conf_file"
    
    f_setConfig "${_conf_file}" "auto" "${_nic}" "#" " " "Y" " " || _warn "$FUNCNAME: setting 'auto' failed."
    #f_appendLine "${_conf_file}" "iface ${_nic} inet ${_type}" || _warn "$FUNCNAME: adding 'iface' line failed."
    f_setConfig "${_conf_file}" "iface ${_nic} inet" "${_type}" "#" " " || _warn "$FUNCNAME: setting 'iface' failed."
    
    if [ "$_address" != "dhcp" ]; then
        local _target="iface ${_nic} inet ${_type}"
        
        if [ -n "$_search" ]; then
            f_insertLine "${_conf_file}" "$_target" "    dns-search ${_search}" "Y" || _warn "$FUNCNAME: adding 'dns-search' line failed."
        fi
        
        if [ -n "$_nameservers" ]; then
            f_insertLine "${_conf_file}" "$_target" "    dns-nameservers ${_nameservers}" "Y" || _warn "$FUNCNAME: adding 'dns-nameservers' line failed."
        fi
        
        if [ -z "$_gateway" ]; then
            #_gateway="$(echo "$_address" | sed 's/\.[0-9]\{1,3\}$/.1/')"
            _warn "$FUNCNAME: No gateway given. (but it would work)"
        elif [[ "$_gateway" =~ $g_ip_regex ]]; then
            f_insertLine "${_conf_file}" "$_target" "    gateway ${_gateway}" "Y" || _warn "$FUNCNAME: adding 'gateway' line failed."
        else
            _warn "$FUNCNAME: Given gateway '$_gateway' does not look like an IP address. Skipping Gateway section..."
        fi
        
        if [ -z "$_netmask" ]; then
            if [[ "$_address" =~ ^10\. ]]; then
                _netmask="255.0.0.0"
            elif [[ "$_address" =~ ^172\.16\. ]]; then
                _netmask="255.240.0.0"
            elif [[ "$_address" =~ ^172\. ]]; then
                _netmask="255.255.0.0"   # not accurate though.
            else
                _netmask="255.255.255.0"   # not accurate though.
            fi
            _warn "$FUNCNAME: No netmask given, so that using $_netmask"
        fi
        if [[ "$_netmask" =~ $g_ip_regex ]]; then
            f_insertLine "${_conf_file}" "$_target" "    netmask ${_netmask}" "Y" || _warn "$FUNCNAME: adding 'netmask' line failed."
        else
            _warn "$FUNCNAME: Given netmask '$_netmask' does not look like an IP address. Skipping Netmask section..."
        fi
        
        if [[ "$_address" =~ $g_ip_regex ]]; then
            f_insertLine "${_conf_file}" "$_target" "    address ${_address}" "Y" || _warn "$FUNCNAME: adding 'address' line failed."
        else
            _warn "$FUNCNAME: Given address '$_address' does not look like an IP address. Please check $_conf_file"
            return 1
        fi
    fi
    
    # making sure setup was done correctly (even above functions check)
    grep -P "^auto.* ${_nic}" "${_conf_file}" &>/dev/null
    if [ $? = 0 ]; then
        grep -P "^iface ${_nic} inet ${_type}" "${_conf_file}" &>/dev/null
        if [ $? = 0 ]; then
            _warn "$FUNCNAME: Setup complted. Please run \"/etc/init.d/networking restart\" later"
            #_eval "/etc/init.d/networking restart"
            #/sbin/ifconfig ${_nic}
        else
            _warn "$FUNCNAME: Unknown 'iface' error. Please check ${_conf_file}"
            return 1
        fi
    else
        _warn "$FUNCNAME: Unknown 'auto' error. Please check ${_conf_file}"
        return 1
    fi
    
    return 0
}

function f_setupProxy() {
    local __doc__="Set system wide proxy.\nExpecting format is 'http://hostname:8080/' or 'http://username:password@hostname:8080/'
if '_no_proxy_str' is not given or 'auto', this script tries to calculate it (experimental)."
    local _proxy_url="$1"
    local _no_proxy_str="${2-auto}"
    local _env_file="/etc/environment"
    
    #TODO: need to update /etc/apt/apt.conf?
    #Acquire::Languages "none";
    #Acquire::http::Proxy "$_proxy_url";

    if [ -z $_proxy_url ]; then
        _warn "$FUNCNAME: No proxy URL. Skipping..."
        return 0
    fi
    
    if ! _isUrl "$_proxy_url" ; then
        _warn "$FUNCNAME: Given URL \"$_proxy_url\" is not a URL. Skipping..."
        return 1
    fi
    
    f_backup "$_env_file"
    
    _info "Editing $_env_file to add proxy."
    local _orig_is_verbose=$g_is_verbose
    g_is_verbose=false
    f_setConfig "$_env_file" "http_proxy" "$_proxy_url"
    f_setConfig "$_env_file" "https_proxy" "$_proxy_url"
    f_setConfig "$_env_file" "ftp_proxy" "$_proxy_url"
    f_setConfig "$_env_file" "HTTP_PROXY" "$_proxy_url"
    f_setConfig "$_env_file" "HTTPS_PROXY" "$_proxy_url"
    f_setConfig "$_env_file" "FTP_PROXY" "$_proxy_url"
    g_is_verbose=$_orig_is_verbose
    
    if [ "$_no_proxy_str" = "auto" ]; then
        # best effort to generate exlude list (not perfect way to use broadcast address
        local _tmp_bcast
        _no_proxy_str="localhost,127.0.0.1,localaddress,.localdomain.com"
        for _bcast in `ifconfig | grep -o -P 'Bcast:.+? '`; do
            _tmp_bcast=${_bcast/Bcast:/}
            if [[ "$_tmp_bcast" =~ $g_ip_regex ]]; then
                _no_proxy_str="${_no_proxy_str},${_tmp_bcast%.255}.*"
            fi
        done
        _info "Using $_no_proxy_str for proxy exclude list."
    fi
    if [ -n $_no_proxy_str ]; then
        f_setConfig "$_env_file" "no_proxy" "$_no_proxy_str"
        f_setConfig "$_env_file" "NO_PROXY" "$_no_proxy_str"
    fi
    
    return $?
}

function f_setupAutoSecurityUpdates() {
    local __doc__="Set up Automatic Security Updates"
    local _conf_file="/etc/apt/apt.conf.d/20auto-upgrades"
    
    if [ ! -e "$_conf_file" ]; then
        local _apt_get="apt-get"
        if _isYes "$r_aptget_with_y" ; then
            _apt_get="apt-get -y"
        fi
        
        _eval "$_apt_get install unattended-upgrades" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing unattended-upgrades package failed."; return 1; fi
    fi
    
    if [ -s "$_conf_file" ]; then
        f_backup "$_conf_file"
    else
        _eval "touch $_conf_file"
    fi
    
    f_setConfig "$_conf_file" "APT::Periodic::Update-Package-Lists" "\"1\";" ";" " "
    f_setConfig "$_conf_file" "APT::Periodic::Unattended-Upgrade" "\"1\";" ";" " "
    return 0
}

function f_setupAptProxy() {
    local __doc__="Set up apt.conf to use proxy.
The first arg should be something like http://apt-proxy:8080/"
    local _proxy_host_port="$1"
    local _conf_file="/etc/apt/apt.conf"
    local _def_proxy_ip="$g_dev_server_ip"
    
    if [ -s "$_conf_file" ]; then
        f_backup "$_conf_file"
    else
        _eval "touch $_conf_file"
    fi
    
    if [ -z "$_proxy_host_port" ]; then
        _info "Proxy host:port is empty, so that using \"http://apt-proxy:8080/\"..."
        _proxy_host_port="http://apt-proxy:8080/"
        
        grep -w "apt-proxy" /etc/hosts &>/dev/null
        if [ $? -ne 0 ]; then
            # FIXME: hard-coding entity name
            if [ "`date +%Z`" = "PGT" ]; then
                _def_proxy_ip="$g_dev_server_ip_pg"
            fi
            _info "Updating /etc/hosts with \"$_def_proxy_ip apt-proxy\"..."
            
            f_backup "/etc/hosts"
            f_setConfig "/etc/hosts" "$_def_proxy_ip" "apt-proxy" "#" " " "Y" " " 
        fi
    fi
    
    # some server might have those lines comment out, so not overwriting 
    grep -w "apt-proxy" "$_conf_file" &>/dev/null
    if [ $? -ne 0 ]; then
        # languages may not be necessary to be changed.
        f_setConfig "$_conf_file" "Acquire::Languages" "\"none\";" ";" " "
        f_setConfig "$_conf_file" "Acquire::http::Proxy" "\"$_proxy_host_port\";" ";" " "
    fi
    return 0
}

function f_setupAptMirror() {
    local __doc__="Install and setup apt-mirror. This requires 50~100GB disk space. *Experimental*"
    #local _mirror_path="$1"
    #if [ -z "$_mirror_path" ]; then
    #    _mirror_path="/var/spool/apt-mirror"
    #fi
    #_mkdir "$_mirror_path" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing package failed."; return 1; fi
    
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    _eval "$_apt_get install apache2 apt-mirror" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing package failed."; return 1; fi
    _eval "ln -s /var/spool/apt-mirror/mirror/archive.ubuntu.com/ubuntu/ /var/www/ubuntu"
    return $?
}

function f_setupLogrotate() {
    local __doc__="Configure log rotate for mainly Build.\nUpdate this function when you add a new log file."
    local _conf_file="/etc/logrotate.d/build"
    
    if [ -n "$r_apache_document_root" ]; then
        local _tmp_path="$(dirname "${r_apache_document_root}")"
    else
        local _tmp_path="/data/sites/production"
    fi
    
    if [ -s "${_tmp_path%/}/utils/configs/build-logrotate" ]; then
        local _link_source="${_tmp_path%/}/utils/configs/build-logrotate"
    else
        local _link_source="`ls -t /data/sites/*/utils/configs/build-logrotate | head -n1`"
    fi
    
    if [ -s "$_link_source" ]; then
        _info "Creating symlink from Utils dir..."
        if [ -f "$_conf_file" ]; then
            f_backup "$_conf_file"
            _eval "rm -f $_conf_file"
        fi
        
        _eval "ln -s $_link_source $_conf_file"
        return $?
    fi
    
    local _default="    daily
    missingok
    compress
    delaycompress
    notifempty
    dateext
    create 666 ${g_apache_user} ${g_apache_user}"
    local _return_rc=0
    
    if [ -s "$_conf_file" ]; then
        _warn "$FUNCNAME: '$_conf_file already' exists, so skipping..."
    else
        _eval "cat /dev/null > $_conf_file"   # root can own this file so no need to change parmission/owner
        
        local _php_log_file="/var/log/php-error.log"
        if [ -n "${g_php_ini_array['error_log']}" ]; then
            _php_log_file="${g_php_ini_array['error_log']}";
        fi
        
        # Why did i do like below???
        _eval "echo \"${_php_log_file} {\" >> $_conf_file"
        _eval "echo -e \"${_default}\" >> $_conf_file"
        _eval "echo \"    rotate 28\" >> $_conf_file"
        _eval "echo \"    olddir /var/log/build/old_logs\" >> $_conf_file"
        _eval "echo \"}\" >> $_conf_file"
        
        _eval "echo \"/var/log/xdebug_remote.log {\" >> $_conf_file"
        _eval "echo -e \"${_default}\" >> $_conf_file"
        _eval "echo \"    rotate 7\" >> $_conf_file"
        _eval "echo \"}\" >> $_conf_file"
        
        _eval "echo \"/var/log/build/*.log {\" >> $_conf_file"
        _eval "echo -e \"${_default}\" >> $_conf_file"
        _eval "echo \"    rotate 28\" >> $_conf_file"
        _eval "echo \"    olddir /var/log/build/old_logs\" >> $_conf_file"
        _eval "echo \"}\" >> $_conf_file"
        
        _eval "echo \"/var/log/build/transient/*.log {\" >> $_conf_file"
        _eval "echo \"    weekly\" >> $_conf_file"
        _eval "echo \"    missingok\" >> $_conf_file"
        _eval "echo \"    rotate 0\" >> $_conf_file"
        _eval "echo \"}\" >> $_conf_file"
    fi
    
    #change /etc/crontab daily time
    grep -P '^[0-9]{1,2}\s+?[^0]{1,2}\s+?.+?cron.daily' /etc/crontab
    if [ $? -eq 0 ]; then
        _info "Modifying /etc/crontab to change daily job hour..."
        _eval "sed -r -i 's/^[0-9]{1,2}\s+?[^0]{1,2}\s+?.+?cron.daily/25 0    \* \* \*    root    test -x \/usr\/sbin\/anacron || ( cd \/ \&\& run-parts --report \/etc\/cron\.daily/' /etc/crontab"
    fi
}

function f_setupNtpUpdate() {
    local __doc__="Update time and create ntp update task in /etc/cron.daily"
    local _ntp_server="${1-$g_ntp_server_ip}"
    
    if [ -z "$_ntp_server" ]; then
        _warn "$FUNCNAME: No NTP server is given. Skipping..."
        return 1
    fi
    
    if ! _isIpOrHostname "$_ntp_server" ; then
        _warn "$FUNCNAME: '$_ntp_server' is not valid."
        return 1
    fi
    
    local _conf_file="/etc/cron.daily/ntp-update"
    #local _cmd="/usr/sbin/ntpdate -u ${_ntp_server}"
    
    if [ -s "$_conf_file" ]; then
        _warn "$FUNCNAME: $_conf_file already exists. Skipping..."
        return 0
    fi
    
    _eval "/usr/sbin/ntpdate -v -u ${_ntp_server}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not run 'ntpdate'."; return 1; fi
    
    if $g_is_dryrun ; then return 0; fi
    
    echo '#!/bin/sh' > $_conf_file && chmod a+x $_conf_file
    echo "/usr/sbin/ntpdate -s -u ${_ntp_server}" >> $_conf_file ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not create/edit $_conf_file"; return 1; fi
    
    return $?
}

function f_installNamazu() {
    local __doc__="Install document indexing/searching engine (no setup)"
    local _search_dir_path="$1"
    local _index_dir="/var/opt/namazu"
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    # libtext-kakasi-perl libnkf-perl
    _eval "$_apt_get install namazu2 namazu2-index-tools wv xlhtml xpdf" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing package failed."; return 1; fi
    
    if [ -n "$_search_dir_path" ]; then
        local _dir_name=`basename "$_search_dir_path"`
        _mkdir "${_index_dir%/}/${_dir_name}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: creating Namazu index dir failed."; return 1; fi
        if [ -d "$_search_dir_path" ]; then 
            _eval "mknmz -O \"${_index_dir%/}/${_dir_name}\" \"$_search_dir_path\""
        fi
    fi
    return $?
}
function f_installPhantomJS() {
    local __doc__="Install PhantomJs for web integration testing.\nRead http://phantomjs.org/"
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    if ! _isCmd "pip" ; then
        _eval "$_apt_get install python-pip python-dev build-essential"
    fi
    
    _eval "pip install selenium" ; if [ $? -ne 0 ]; then _error "Installing selenium package failed."; return 1; fi
    
    cd /opt/
    f_getFromSvn "/installers/trunk/phantomjs-1.9.1-linux-x86_64.tar.bz2" ; if [ $? -ne 0 ]; then _error "Downloading PhantomJS from SVN failed."; return 1; fi
    _eval "tar jxvf phantomjs-1.9.1-linux-x86_64.tar.bz2" ; if [ $? -ne 0 ]; then _error "Extracting PhantomJS failed."; return 1; fi
    _eval "ln -s /opt/phantomjs-1.9.1-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs"
    cd - &>/dev/null
    
    _info "Testing PhantomJS against localhost..."
    _eval "python -c 'from selenium import webdriver;p=webdriver.PhantomJS();p.get(\"http://localhost/\");print p.page_source' 2>/dev/null"
    return $?
}

function f_installGhostPy() {
    local __doc__="Install Ghost.py for web integration testing.\nRead http://jeanphix.me/Ghost.py/"
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    if ! _isCmd "pip" ; then
        _eval "$_apt_get install python-pip python-dev build-essential"
    fi
    
    _eval "$_apt_get install python-qt4 xvfb libicu48 xfonts-100dpi xfonts-75dpi xfonts-cyrillic xfonts-scalable x-ttcidfont-conf"
    _eval "pip install Ghost.py" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Installing Ghost.py package failed."; return 1; fi
    
    # FIXME: [dix] Could not init font path element /var/lib/defoma/x-ttcidfont-conf.d/dirs/TrueType, removing from list!
    _info "Testing Ghost.py against localhost..."
    _eval "python -c 'from ghost import Ghost;g=Ghost();p,r=g.open(\"http://localhost/\");print g.content' 2>/dev/null"
    return $?
}


### Database setup functions ##################################################
function f_installPostgresqlForBuild() {
    local __doc__="Install Postgresql for Build."
    
    # Not sure if this is necessary but just in case 'g_db_version' has been changed.
    g_db_conf_dir="/etc/postgresql/${g_db_version}/${g_db_cluster_name}"
    g_db_data_dir="${g_db_home%/}/${g_db_version}/${g_db_cluster_name}"
    
    _info "Installing PostgreSQL packages..."
    if [ "$g_db_version" = "9.2" ]; then
        f_installPostgresql92
    else
        f_installPostgresql91
    fi
    
    # if installation was successful, DB superuser 'postgres' should have been created.
    grep -w ^${g_db_superuser} /etc/passwd > /dev/null
    if [ $? -eq 1 ]; then
        _critical "$FUNCNAME: OS User ${g_db_superuser} has not been created."
    fi
    
    # If DB shared buffer will be changed, might need to increase OS shmmax.
    if [[ "${r_db_shared_buffers}" =~ ^[0-9]+$ ]]; then
        local _current_shmmax=`sysctl -n kernel.shmmax`
        local _required_shmmax=$(echo $r_db_shared_buffers | awk '{r=sprintf("%.0f", $1*1024*1024*1.25); print r}')
        
        if [ $_required_shmmax -gt $_current_shmmax ]; then
            # NOTE: changing /etc/sysctl.d/30-postgresql-shm.conf does not work
            f_backup "/etc/sysctl.conf"
            f_setConfig "/etc/sysctl.conf" "kernel.shmmax" "$_required_shmmax" && sysctl -p
        fi
    fi
    
    _eval "service postgresql restart" || _critical "$FUNCNAME: Setup PostgreSQL failed."
    return $?
}

function f_setupPostgresqlForBuild() {
    local __doc__="Install and Set up Postgresql for Build.
Please check/change g_db_version (${g_db_version}}, g_db_cluster_name (${g_db_cluster_name}), g_db_port (${g_db_port})"
    #local _db_version="$1"   # does not support version difference
    local _db_cluster_name="$1"
    local _db_port="$2"
    
    if [ -z "$_db_cluster_name" ]; then
        _db_cluster_name="$g_db_cluster_name"
    fi
    
    if [ -z "$_db_port" ]; then
        _db_port="$g_db_port"
    fi
    
    local _db_conf_dir="/etc/postgresql/${g_db_version}/${_db_cluster_name}"
    g_db_conf_dir="$_db_conf_dir"
    g_db_data_dir="${g_db_home%/}/${g_db_version}/${_db_cluster_name}"
    
    # if installation was successful, DB superuser 'postgres' should have been created.
    grep -w ^${g_db_superuser} /etc/passwd > /dev/null
    if [ $? -eq 1 ]; then
        _warn "$FUNCNAME: OS User ${g_db_superuser} has not been created."
        return 1
    fi
    
    f_backup "${_db_conf_dir%/}/postgresql.conf"
    
    # Update/overwrite postgresql parameters
    for _k in "${!g_db_conf_array[@]}"; do
        f_setPostgreConf "$_k" "${g_db_conf_array[$_k]}" "${_db_conf_dir%/}/postgresql.conf"
    done
    
    # Not necessary as it looks like localtime works
    #if [ -n "$r_date_timezone" ]; then
    #    f_setPostgreConf "timezone" "'${r_date_timezone}'" "${_db_conf_dir%/}/postgresql.conf"
    #fi
    
    # If DB shared buffer will be changed, might need to increase OS shmmax.
    if [[ "${r_db_shared_buffers}" =~ ^[0-9]+$ ]]; then
        f_setPostgreConf "shared_buffers" "${r_db_shared_buffers}MB" "${_db_conf_dir%/}/postgresql.conf"
    else
        _info "No r_db_shared_buffers, so that not changing shared_buffers value..."
    fi
    
    if [ -s "/etc/logrotate.d/postgresql-common" ]; then
        _info "Changing postgresql logrotate..."
        f_backup "/etc/logrotate.d/postgresql-common"
        _eval "sed -i '/copytruncate/d' /etc/logrotate.d/postgresql-common"
    fi
    
    if [ -n "$r_db_client_ip_list" ]; then
        local _tmp_ip_list
        _split "_tmp_ip_list" "$r_db_client_ip_list"
        for _ip in "${_tmp_ip_list[@]}"; do
            if _isIpOrHostname "$_ip" ; then
                if [ -n "$r_db_password" ]; then
                    f_addDbAccess "${r_db_username}" "${_ip}" "md5" "all" "${_db_conf_dir%/}/pg_hba.conf"
                else
                    f_addDbAccess "${r_db_username}" "${_ip}" "trust" "all" "${_db_conf_dir%/}/pg_hba.conf"
                fi
            else
                _warn "$FUNCNAME: $_ip does not look like a valid value. Skipping..."
            fi
        done
    else
        _info "No r_db_client_ip_list, so that not changing pg_hba.conf..."
    fi
    
    _eval "pg_ctlcluster ${g_db_version} ${_db_cluster_name} restart" || _critical "$FUNCNAME: Setup PostgreSQL failed. r_db_shared_buffers:${r_db_shared_buffers} might be too high."
    local _returning_rc=$?
    
    #<<< Build SPECIFIC SETTINGS       >>>
    # Creating extensions
    f_createDbCommonExtensions "$r_server_type" "template1" "$_db_port"
    
    f_addDbUser "$r_db_username" "$r_db_password" "$r_db_is_user_super" "" "$_db_port" || _warn "$FUNCNAME: Creating DB user $r_db_username failed."
    #FIXME: hard-coding role/user name would not be a good design
    f_addDbUser "db_readonly" "" "" "Y" "$_db_port" || _warn "$FUNCNAME: Creating DB user 'db_readonly' failed."
    
    if [ ! -e "/usr/local/pgsql/bin/psql" ]; then
        _mkdir "/usr/local/pgsql/bin" && _eval "ln -s /usr/bin/psql /usr/local/pgsql/bin/psql"
    fi
    #<<< END OF Build SPECIFIC SETTINGS >>>
    
    #_eval "pg_ctlcluster ${g_db_version} ${g_db_cluster_name} restart" || _critical "$FUNCNAME: Setup PostgreSQL failed."
    
    return $_returning_rc
}

function f_createDbCluster() {
    local __doc__="Create a new DB cluster (instance).
If _changing_conf is 'Y', then this function runs f_setupPostgresqlForBuild
keyword: f_addDbCluster, f_setupDbCluster"
    local _cluster_name="$1"
    local _changing_conf="$2"
    local _returning_rc=0
    
    if [ -z "$_cluster_name" ]; then
        _warn "$FUNCNAME: No new cluster name."
        return 1
    fi
    
    local _new_data_dir="${g_db_home%/}/${g_db_version}/${_cluster_name}"
    
    if _isNotEmptyDir "${_new_data_dir}"; then
        _warn "$FUNCNAME: Please clean up ${_new_data_dir} first."
        return 1
    fi
    
    _eval "pg_createcluster ${g_db_version} ${_cluster_name}" || _critical "Creating cluster ${_cluster_name} failed."
    _returning_rc=$?
    
    if ! _isYes "$_changing_conf"; then
        return $_returning_rc
    fi
    
    # if successfully created, change global variables
    local _tmp_port="$(pg_lsclusters -h | grep -P "^${g_db_version}\s+${_cluster_name}" | awk '{print $3}')"
    if [[ ! "$_tmp_port" =~ 54[3-9][0-9] ]]; then
        _warn "$FUNCNAME: New port number $_tmp_port looks suspicious. Exiting..."
        return 1
    fi
    
    local _orig_db_port=$g_db_port
    local _orig_db_cluster_name="$g_db_cluster_name"
    
    g_db_port=$_tmp_port
    g_db_cluster_name="${_cluster_name}"
    
    f_setupPostgresqlForBuild "${_cluster_name}" "$_tmp_port"
    _returning_rc=$?
    
    pg_lsclusters
    
    _info "Current DB related global variables:"
    _info "g_db_port         = $g_db_port"
    _info "g_db_conf_dir     = $g_db_conf_dir"
    _info "g_db_data_dir     = $g_db_data_dir"
    _info "g_db_cluster_name = $g_db_cluster_name"
    
    return $_returning_rc
}

function f_createDbCommonExtensions() {
    local __doc__="Create extenstions such as tablefunc."
    local _server_type="${1}";
    local _db_name="${2-template1}";
    local _db_port="${3-$g_db_port}"
    
    # Mandatory extension(s)
    _eval "psql -p ${_db_port} $_db_name -c 'CREATE EXTENSION IF NOT EXISTS tablefunc;'" "" "${g_db_superuser}" || _warn "$FUNCNAME: Creating tablefunc failed."
    
    # Optional (dont' care if fails, just WARNing)
    _eval "psql -p ${_db_port} $_db_name -c 'CREATE EXTENSION IF NOT EXISTS pg_buffercache;'" "" "${g_db_superuser}" || _warn "$FUNCNAME: Creating pg_buffercache failed."
    _eval "psql -p ${_db_port} $_db_name -c 'CREATE EXTENSION IF NOT EXISTS hstore;'" "" "${g_db_superuser}" || _warn "$FUNCNAME: Creating hstore failed."
    _eval "psql -p ${_db_port} $_db_name -c 'CREATE EXTENSION IF NOT EXISTS dblink;'" "" "${g_db_superuser}" || _warn "$FUNCNAME: Creating hstore failed."
    _eval "psql -p ${_db_port} -c 'CREATE EXTENSION IF NOT EXISTS adminpack;'" "" "${g_db_superuser}" || _warn "$FUNCNAME: Creating pg_buffercache failed."
    
    if [ "$_server_type" = "dev" ]; then
        f_installPgadminDebugger "$_db_name" "N" "Y" || _warn "$FUNCNAME: Creating Pgadmin Debugger failed."
    fi
    
    return $?
}

function f_installPostgresql91() {
    local __doc__="Install and Set up Postgresql *9.1* (Ubuntu default) if not installed.
If '_ignore_version' is Yes, 9.1 will be installed even if 9.x has been installed."
    local _ignore_version="$1"
    
    if _isPostgresInstalled "9.1" "$_ignore_version" ]; then
        _warn "$FUNCNAME: Postgresql 9.x has been installed. Skipping..."
        return 1
    fi
    
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    # looks like installing the following two packages automatically install postgresql-client-9.x
    _eval "$_apt_get install postgresql postgresql-contrib"
    return $?
}

function f_installPostgresql92() {
    local __doc__="Install and Set up Postgresql *9.2* if not installed.
If '_ignore_version' is Yes, 9.2 will be installed even if 9.x has been installed."
    local _ignore_version="$1"
    
    if _isPostgresInstalled "9.2" "$_ignore_version" ]; then
        _warn "$FUNCNAME: Postgresql 9.x has been installed. Skipping..."
        return 1
    fi
    
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        # Without --force-yes, installation started failing...
        _apt_get="apt-get -y --force-yes"
    fi
    
    local _conf_file="/etc/apt/sources.list.d/pitti-postgresql-precise.list"
    if [ ! -s "$_conf_file" ]; then
        _eval "echo '' | add-apt-repository ppa:pitti/postgresql && apt-get update"
        if [ $? -ne 0 ]; then
            f_backup "$_conf_file"
            f_appendLine "$_conf_file" "deb http://ppa.launchpad.net/pitti/postgresql/ubuntu precise main"
            f_appendLine "$_conf_file" "deb-src http://ppa.launchpad.net/pitti/postgresql/ubuntu precise main"
            _eval "apt-get update" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: apt-get update failed"; return 1; fi
            # FIXME: above returns 0 even it fails with NO_PUBKEY
            _warn "$FUNCNAME: Please run 'apt-key adv --keyserver keyserver.ubuntu.com --recv-keys XXXXXXXX'"
            return 1
        fi
    fi
    
    _eval "$_apt_get install libpq-dev postgresql-9.2 postgresql-client-9.2 postgresql-contrib-9.2"
    return $?
}

function _isPostgresInstalled() {
    local _version="$1"
    local _ignore_version="$2"
    
    #pg_lsclusters -h | grep ^${_version} >/dev/null
    dpkg -l | grep -P "^ii\s+?postgresql-${_version}\s" > /dev/null && dpkg -l | grep -P "^ii\s+?postgresql-client-${_version}\s" > /dev/null && dpkg -l | grep -P "^ii\s+?postgresql-contrib-${_version}\s" > /dev/null
    if [ $? -eq 0 ]; then
        #_info "$FUNCNAME: Looks like PostgreSQL ${_version} has been installed. Skipping..."
        return 0
    fi
    
    if _isYes "$_ignore_version"; then
        # if _ignore_version, no further checking required and assume PostgreSQL is not installed.
        return 1;
    fi
    
    #pg_lsclusters -h | grep ^9 | grep -v ^${_version} >/dev/null
    dpkg -l | grep -P "^ii\s+?postgresql-9" > /dev/null
    if [ $? -eq 0 ]; then
        #_info "$FUNCNAME: PostgreSQL 9.x version has been installed."
        return 0
    fi
    
    return 1
}

function f_upgradePostgresql() {
    local __doc__="Upgrade existing postgresql.
NOTE: Deleting existing databases before upgrading makes this process faster."
    local _old_version="${1-9.1}"
    local _old_cl_name="${2-$g_db_cluster_name}"
    local _new_version="${3-9.2}"
    local _new_cl_name="${4-$_old_cl_name}"
    local _new_data_dir="$5"
    local _is_new_install=false
    
    # To upgrade, need to install 9.2 pacages first
    dpkg -l | grep -P "^ii\s+?postgresql-${_new_version}\s" > /dev/null
    if [ $? -ne 0 ]; then
        f_installPostgresql92 "Y"
        _is_new_install=true
    fi
    
    pg_lsclusters -h | grep -P "^${_new_version}\s+${_new_cl_name}\s"
    if [ $? -eq 0 ]; then
        if $_is_new_install; then
            _eval "pg_dropcluster --stop ${_new_version} ${_new_cl_name}"
        else
            _warn "$FUNCNAME: Please drop ${_new_version} ${_new_cl_name} first."
            return 1
        fi
    fi
    
    local _cmd="pg_upgradecluster -v ${_new_version} ${_old_version} ${_old_cl_name}"
    if [ -n "$_new_data_dir" ]; then
        _cmd="$_cmd $_new_data_dir"
        
        pg_lsclusters -h | grep "$_new_data_dir"
        if [ $? -eq 0 ]; then
            _warn "$FUNCNAME: $_new_data_dir is in use."
            return 1
        fi
        
        if _isNotEmptyDir "${_new_data_dir}"; then
            if _isNotEmptyDir "${_new_data_dir}_bak"; then
                _warn "$FUNCNAME: Please clean up ${_new_data_dir}_bak first."
                return 1
            fi
            _eval "mv ${_new_data_dir} ${_new_data_dir}_bak"
        fi
    fi
    
    local _old_data_dir="$(pg_lsclusters -h | grep -P "^${_old_version}\s+${_old_cl_name}" | awk '{print $6}')"
    local _old_size="$(du -s $_old_data_dir | awk '{print $1}')"
    local _old_size_gb="echo $(( $_old_size / 1024 / 1024 ))"
    
    if [ $_old_size_gb -gt 0 ]; then
        if ! f_isEnoughDisk "$g_db_home" "$_old_size_gb" ; then
            _warn "$FUNCNAME: $g_db_home space is less than $_old_size_gb GB. Aborting..."
            return 1
        fi
    fi
    
    _eval "$_cmd" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: pg_upgradecluster failed."; return 1; fi
    local _return_rc=$?
    
    #if _isYes "$_drop_old"; then
    #    _eval "pg_dropcluster --stop ${_old_version} ${_old_cl_name}"
    #    _eval "apt-get remove --purge postgresql-9.1 postgresql-client-9.1 postgresql-contrib-9.1"
    #fi
    
    _eval "service postgresql restart"
    return $_return_rc
}

function f_addDbUser() {
    local __doc__="Add a PostgreSQL DB user.
NOTE: would not need to create an OS user when we create a new DB user. (if needed, use f_addOsUser)
keyword: createDbUser, setupDbUser"
    local _db_username="$1"
    local _db_password="$2"
    local _is_super="$3"
    local _is_readonly="$4"
    local _db_port="${5-$g_db_port}"
    
    local _db_user_chk="$(su - ${g_db_superuser} -c "psql -p ${_db_port} -xc \"SELECT rolname,rolsuper FROM pg_roles WHERE rolname='${_db_username}'\"" | grep -wo "${_db_username}")"
    if [ -n "$_db_user_chk" ]; then
        _warn "$FUNCNAME: DB user ${_db_user_chk} already exists. Skipping..."
        return 0
    fi
    
    local _cmd="createuser -p ${_db_port} -S -d -r ${_db_username}"
    if _isYes "$_is_super" ; then
        _cmd="createuser -p ${_db_port} -s ${_db_username}"
    elif _isYes "$_is_readonly" ; then
        _cmd="createuser -p ${_db_port} -S -D -R ${_db_username}"
    fi
    
    _eval "$_cmd" "" "${g_db_superuser}" || return 1
    
    if [ -n "$_db_password" ]; then
        f_changeDbPwd "${_db_username}" "${_db_password}"
    else
        _info "No password is given for ${_db_username}. Using script's default password."
        f_changeDbPwd "${_db_username}" "${g_default_password}"
    fi
    
    return $?
}

function f_setupDbArchive() {
    local __doc__="Setup Write Ahead Log mode to improve Performance and Reliability"
    
    if _isNotEmptyDir "${g_db_wal_dir}"; then
        _warn "$FUNCNAME: Archive log directory \"${g_db_wal_dir}\" is not empty. Skipping..."
        return 0
    fi
    
    _mkdir "$g_db_wal_dir"
    
    f_backup "${g_db_conf_dir%/}/postgresql.conf"
    f_setPostgreConf "archive_mode" "on"
    f_setPostgreConf "archive_command" "'test ! -f ${g_db_wal_dir%/}/%f && cp %p ${g_db_wal_dir%/}/%f'"
    #f_setPostgreConf "archive_timeout" "180"
}

function _setupDbReplicationCommon() {
    local __doc__="Create DB replication user and configure replication on local PostgreSQL instance.
Can be used on both Master and Slave."
    local _db_password="${1}"
    local _ip_range="${2}"
    local _number_of_slaves="${3}"
    local _is_using_archive="${4}"
    local _archive_command="${5}"
    local _max_wal_senders=$(( $_number_of_slaves + 1 ))
    local _min_segment_space=$(( $g_min_db_data_size_gb * 2 / 5 ))
    local _min_segment_num=$(( $_min_segment_space * 1024 / 16 ))    # = 5112
    if [ -z "$r_svn_url_build" ]; then
        r_svn_url_build="$g_svn_url_build"
    fi
    local _remote_url="${r_svn_url_build%/}/site/utils/utility-scripts/postgres_ssh.tar.gz"
    
    if ! f_isEnoughDisk "${g_db_data_dir}" "$_min_segment_space" ; then
        _warn "$FUNCNAME: Recommended free space for replication is $_min_segment_space GB."
    fi
    
    # Don't need to create an OS user for replication
    #f_addOsUser "${g_db_replicator}" "${_db_password}" "N" "Y" "" "${g_db_home%/}" "-g ${g_db_superuser}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Adding OS User for DB replication failed."; return 1; fi
    
    # FIXME: probably trust is not good.
    if [ -n "$_ip_range" ]; then
        local _tmp_ip_list
        _split "_tmp_ip_list" "$_ip_range"
        for _ip in "${_tmp_ip_list[@]}"; do
            if _isIpOrHostname "$_ip" ; then
                f_addDbAccess "${g_db_replicator}" "${_ip}" "trust" "replication" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Inserting access $_ip failed."; return 1; fi
            else
                _warn "$FUNCNAME: $_ip does not look like a valid value. Skipping..."
            fi
        done
    else
        _info "No _ip_range, so that not changing pg_hba.conf..."
    fi
    
    f_backup "${g_db_conf_dir%/}/postgresql.conf"
    
    if _isYes "$_is_using_archive"; then
        if [ ! -f "${g_db_home%/}/.ssh/id_rsa" ]; then
            _askSvnUser
            if [ $? -ne 0 ]; then
                _warn "$FUNCNAME: No SVN username. Exiting."; return 1
            fi
            
            # FIXME: should use f_getFromSvn
            _eval "curl --basic --user ${r_svn_user}:${r_svn_pass} '$_remote_url' -o ${g_db_home%/}/postgres_ssh.tar.gz" "N" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Downloading postgres keys faild."; return 1; fi
            _eval "tar xzf ${g_db_home%/}/postgres_ssh.tar.gz -C ${g_db_home%/}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Deploying postgres keys faild."; return 1; fi
        else 
            _info "$FUNCNAME: looks like postgres keys exist. Skipping download."
        fi
        
        if [ -z "$_archive_command" ]; then
            _critical "$FUNCNAME: Please provide archive_command (ex: rsync -av %p postgres@slave_ip:${g_db_wal_dir%/}/%f) for replication."
        else
            _archive_command="$(_escape_double_quote "$_archive_command")"
        fi
        
        f_setupDbArchive ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Setting up WAL Archive for replication failed."; return 1; fi
        f_setPostgreConf "archive_command" "'$_archive_command'"
    else
        f_setPostgreConf "archive_mode" "off"
        f_setPostgreConf "wal_keep_segments" "$_min_segment_num"
    fi
    
    f_setPostgreConf "wal_level" "hot_standby"
    f_setPostgreConf "max_wal_senders" "$_max_wal_senders"
    f_setPostgreConf "max_standby_archive_delay" "1800s"
    f_setPostgreConf "max_standby_streaming_delay" "1800s"
    return $?
}

function f_setupDbReplicationMaster() {
    local __doc__="Create DB replication user and configure replication on local PostgreSQL instance for Master.
Please check/change g_db_version (${g_db_version}}, g_db_cluster_name (${g_db_cluster_name}), g_db_port (${g_db_port})"
    local _db_password="${1-$g_default_password}"
    local _ip_range="${2-$r_db_client_ip_list}"
    local _number_of_slaves="${3-5}"
    local _is_using_archive="${4}"
    local _archive_command="${5}"
    local _is_generating_key="$6"
    local _db_user_chk=""
    
    g_db_conf_dir="/etc/postgresql/${g_db_version}/${g_db_cluster_name}"
    g_db_data_dir="${g_db_home%/}/${g_db_version}/${g_db_cluster_name}"
    
    _info "g_db_port     = $g_db_port"
    _info "g_db_conf_dir = $g_db_conf_dir"
    _info "g_db_data_dir = $g_db_data_dir"
    
    if _isYes "$_is_generating_key"; then
        if [ ! -f "${g_db_home%/}/.ssh/id_rsa" ]; then
            _eval "ssh-keygen -N '' -f ${g_db_home%/}/.ssh/id_rsa" "N" "$g_db_superuser" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Setting up keys failed."; return 1; fi
        fi
        
        _eval "diff ${g_db_home%/}/.ssh/authorized_keys ${g_db_home%/}/.ssh/id_rsa.pub &>/dev/null"
        if [ $? -ne 0 ] ; then
            # Not using '>>' but '>' to accept only this key, so that just in case, taking a backup
            f_backup "${g_db_home%/}/.ssh/authorized_keys"
            _eval "cat ${g_db_home%/}/.ssh/id_rsa.pub > ${g_db_home%/}/.ssh/authorized_keys" "N" "$g_db_superuser" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Setting up Authorized keys failed."; return 1; fi
            _eval "chmod 600 ${g_db_home%/}/.ssh/authorized_keys"
        fi
        
        _warn "$FUNCNAME: Please copy ${g_db_home%/}/.ssh/* to Slave servers"
    fi
    
    # note: _setupDbReplicationCommon backs up postgresql.conf
    _setupDbReplicationCommon "$_db_password" "$_ip_range" "$_number_of_slaves" "$_is_using_archive" "$_archive_command"
    
    _db_user_chk=$(su - ${g_db_superuser} -c "psql -tAc \"SELECT rolname,rolsuper FROM pg_roles WHERE rolname='${g_db_replicator}'\"" | grep -w "${g_db_replicator}")
    if [ -z "$_db_user_chk" ]; then
        _eval "su - ${g_db_superuser} -c \"psql -c \\\"CREATE ROLE ${g_db_replicator} LOGIN REPLICATION PASSWORD '${_db_password}'\\\"\"" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Adding OS User for DB replication failed."; return 1; fi
    else
        _warn "$FUNCNAME: DB role ${g_db_replicator} already exists."
    fi
    
    _warn "$FUNCNAME: Please run \"pg_ctlcluster ${g_db_version} ${g_db_cluster_name} restart\" later."
    return 0
}

function f_setupDbReplicationSlave() {
    local __doc__="Create DB replication user and configure replication on local PostgreSQL instance for Slave.
Please check/change g_db_version (${g_db_version}}, g_db_cluster_name (default is slave), g_db_port (${g_db_port})"
    local _master_ip="$1"
    local _master_port="${2-$g_db_port}"
    local _is_imporiting="$3"
    local _db_password="${4-$g_default_password}"
    local _ip_range="${5-$r_db_client_ip_list}"
    local _number_of_slaves="${5-5}"
    local _is_using_archive="${6}"
    local _archive_command="${7}"
    
    if [ "$g_db_cluster_name" = "main" ]; then
        g_db_cluster_name="slave"
    fi
    
    local _extra_msg="Please run \"pg_ctlcluster ${g_db_version} ${g_db_cluster_name} start\" later."
    
    g_db_conf_dir="/etc/postgresql/${g_db_version}/${g_db_cluster_name}"
    g_db_data_dir="${g_db_home%/}/${g_db_version}/${g_db_cluster_name}"
    
    _info "g_db_port     = $g_db_port"
    _info "g_db_conf_dir = $g_db_conf_dir"
    _info "g_db_data_dir = $g_db_data_dir"
    
    if [ -d "${g_db_conf_dir%/}" ] && [ ! -d "${g_db_data_dir}" ]; then
        _warn "${g_db_conf_dir%/} exists but ${g_db_data_dir%/} does not."
        _warn "Please clean up ${g_db_conf_dir%/} first."
        return 1
    fi
    
    if [ "$g_db_cluster_name" = "slave" ] && [ ! -d "$g_db_conf_dir" ]; then
        _warn "${g_db_conf_dir} does not exist. Creating..."
        f_createDbCluster "${g_db_cluster_name}" "Y"
        
        if [ $? -ne 0 ]; then
            _warn "$FUNCNAME: f_createDbCluster \"${g_db_cluster_name}\" \"Y\" failed."
            return 1
        fi
    fi
    
    if [ ! -d "$g_db_conf_dir" ]; then
        _warn "${g_db_conf_dir} does not exist. Please create cluster (f_createDbCluster \"${g_db_cluster_name}\" \"Y\") first."
        return 1
    fi
    
    if [ -z "$_master_ip" ]; then
        _warn "$FUNCNAME requires master IP address."
        return 1
    fi
    
    if [ -z "$_master_port" ]; then
        _master_port="$g_db_port"
    fi
    
    if [ -z "$_db_password" ] && [ -n "$g_default_password" ]; then
        _info "$FUNCNAME: using g_default_password for replication user $g_db_replicator password."
        _db_password="$g_default_password"
    fi
    
    if [ -z "$_ip_range" ] && [ -n "$r_db_client_ip_list" ]; then
        _info "$FUNCNAME: using $r_db_client_ip_list for IP range."
        _ip_range="$r_db_client_ip_list"
    fi
    
    if [ -z "$_number_of_slaves" ]; then
        _number_of_slaves=5
    fi
    
    # note: _setupDbReplicationCommon backs up postgresql.conf
    _setupDbReplicationCommon "$_db_password" "$_ip_range" "$_number_of_slaves" "$_is_using_archive" "$_archive_command"
    
    _eval "ssh -q -o StrictHostKeyChecking=no -o BatchMode=yes $_master_ip id 'SSH password less connection test.'" "Y" "$g_db_superuser" || (_warn "$FUNCNAME: testing ssh connection to $_master_ip failed. (Can't use archive mode)")
    
    f_setPostgreConf "hot_standby" "on"
    
    if [ -f "${g_db_conf_dir%/}/recovery.conf" ]; then
        f_backup "${g_db_conf_dir%/}/recovery.conf"
    else
        _eval "touch ${g_db_conf_dir%/}/recovery.conf" "" "${g_db_superuser}"
    fi
    
    f_setConfig "${g_db_conf_dir%/}/recovery.conf" "standby_mode" "on"
    f_setConfig "${g_db_conf_dir%/}/recovery.conf" "primary_conninfo" "'host=${_master_ip} port=${_master_port} user=${g_db_replicator} password=${_db_password}'"
    
    _eval "pg_ctlcluster ${g_db_version} ${g_db_cluster_name} stop"
    
    if _isYes "$_is_imporiting"; then
        _pg_basebackup "$_master_ip" "$_master_port" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Importing base data from $_master_ip failed."; return 1; fi
    else
        _extra_msg="Please import inital data BEFORE re-starting Postgresql."
    fi
    
    _eval "ln -s ${g_db_conf_dir%/}/recovery.conf ${g_db_data_dir%/}/recovery.conf" "" "${g_db_superuser}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: symlink to ${g_db_data_dir%/}/recovery.conf failed."; return 1; fi
    
    _warn "$FUNCNAME: Completed. $_extra_msg"
    return 0
}

function _pg_basebackup() {
    local _master_ip="$1"
    local _master_port="$2"
    local _target_dir="$3"
    
    if [ -z "$_master_port" ]; then 
        _master_port=$g_db_port
    fi
    
    if [ -z "$_target_dir" ]; then 
        _target_dir="$g_db_data_dir"
    fi
    
    if ! f_isEnoughDisk "${_target_dir}" "$g_min_db_data_size_gb" ; then
        _warn "$FUNCNAME: Not enough disk space (${g_min_db_data_size_gb}GB) Skipping pg_basebackup..."
        return 1
    fi
    
    if _isNotEmptyDir "${_target_dir}"; then
        if _isNotEmptyDir "${_target_dir}_bak"; then
            _warn "$FUNCNAME: Please clean up ${_target_dir}_bak first. Skipping pg_basebackup..."
            return 1
        fi
        
        _eval "mv ${_target_dir} ${_target_dir}_bak && mkdir -m 700 ${_target_dir} && chown ${g_db_superuser}:${g_db_superuser} ${_target_dir}"
        if [ $? -ne 0 ]; then
            _warn "$FUNCNAME: Please make sure PostgreSQL is not using ${_target_dir}."
            return 1
        fi
    fi
    _eval "pg_basebackup -h $_master_ip -p $_master_port -U ${g_db_replicator} -D \"$_target_dir\" --xlog --checkpoint=spread --progress" "" "${g_db_superuser}"
    local _last_rc=$?
    
    # Looks like 9.2 does not need below.
    if [ "$g_db_version" = "9.1" ]; then
        _eval "ln -s /etc/ssl/private/ssl-cert-snakeoil.key ${g_db_data_dir%/}/server.key"
        _eval "ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem ${g_db_data_dir%/}/server.crt"
    fi
    
    return $_last_rc
}

function f_setupDbReplicationPromoteSlave() {
    local __doc__="Promote this slave as a master"
    local _force="$1"
    local _data_dir="$2"
    local primary_conninfo=""
    local host=""
    local port=""
    local user=""
    local password=""
    local _tmp_conn=""
    
    g_db_conf_dir="/etc/postgresql/${g_db_version}/${g_db_cluster_name}"
    g_db_data_dir="${g_db_home%/}/${g_db_version}/${g_db_cluster_name}"
    
    _info "g_db_port     = $g_db_port"
    _info "g_db_conf_dir = $g_db_conf_dir"
    _info "g_db_data_dir = $g_db_data_dir"
    
    if [ -z "$_data_dir" ]; then _data_dir="$g_db_data_dir"; fi
    
    if ! _isNotEmptyDir "$_data_dir" ; then
        _warn "$FUNCNAME: Please make sure $_data_dir is Postgresql data dir."
        return 1
    fi
    
    if ! _isYes "$_force"; then
        _tmp_conn=`grep '^primary_conninfo' ${g_db_conf_dir%/}/recovery.conf` ; if [ $? -ne 0 ]; then _warn "$FUNCNAME: Please confirm ${g_db_conf_dir%/}/recovery.conf"; return 1; fi
        eval "$_tmp_conn" && eval "$primary_conninfo"
        if [ -z "$host" ]; then
            _warn "$FUNCNAME: Please confirm ${g_db_conf_dir%/}/recovery.conf"
            return 1
        fi
        
        if [ -z "$port" ]; then
            port="${g_db_port}"
        fi
        
        nc -z "$host" "$port" ; if [ $? -eq 0 ]; then _warn "$FUNCNAME: Please make sure Master DB has been stopped on $host"; return 1; fi
    fi
    
    f_backup "${g_db_conf_dir%/}/recovery.conf"
    f_setConfig "${g_db_conf_dir%/}/recovery.conf" "standby_mode" "off"
    #f_setPostgreConf "hot_standby" "on"

    _eval "/usr/lib/postgresql/${g_db_version}/bin/pg_ctl promote -D $_data_dir" "" "$g_db_superuser" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Promoting by using $_data_dir failed."; return 1; fi
    _eval "psql -p ${g_db_port} -x -c \"SELECT pg_is_in_recovery()\" | grep -w f >/dev/null" "N" "$g_db_superuser" ; if [ $? -ne 0 ]; then _warn "$FUNCNAME: Promoting by using $_data_dir might have failed."; return 1; fi
    _warn "$FUNCNAME: Please run f_setupDbReplicationDemoteMaster on *MASTER* DB to make it stand-by/Slave."
    return 0
}

function f_setupDbReplicationDemoteMaster() {
    local __doc__="Demote this Master DB to Slave. Recomend to use 'Y' for 2nd argument.
If the 2nd argument _is_imporiting is 'Y', it re-import base data from _new_master_ip."
    local _new_master_ip="$1"
    local _is_imporiting="$2"
    local _db_password="${3-$g_default_password}"
    
    if ! _isIpOrHostname "$_new_master_ip"; then
        _warn "$FUNCNAME requirs new master IP address as 1st argument."
        return 1
    fi
    
    _eval "pg_ctlcluster ${g_db_version} ${g_db_cluster_name} stop"
    
    if _isYes "$_is_imporiting"; then
        _pg_basebackup "$_new_master_ip" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: re-importing base data from $_new_master_ip failed."; return 1; fi
    else
        _extra_msg="Please import inital data BEFORE re-starting Postgresql."
    fi
    
    if [ -f "${g_db_conf_dir%/}/recovery.conf" ]; then
        f_backup "${g_db_conf_dir%/}/recovery.conf"
    else
        _eval "touch ${g_db_conf_dir%/}/recovery.conf" "" "${g_db_superuser}"
    fi
    
    f_setConfig "${g_db_conf_dir%/}/recovery.conf" "standby_mode" "on"
    f_setConfig "${g_db_conf_dir%/}/recovery.conf" "primary_conninfo" "'host=${_new_master_ip} port=${g_db_port} user=${g_db_replicator} password=${_db_password}'"
    f_setConfig "${g_db_conf_dir%/}/recovery.conf" "recovery_target_timeline" "'latest'"
    # NOTE: transaction's compress rate is very high, but if network is really fast, please remove '-C'. Also please add '2> /dev/null' if there are too many scp stderr outputs.
    f_setConfig "${g_db_conf_dir%/}/recovery.conf" "restore_command" "'scp -C ${g_db_superuser}@${_new_master_ip}:${g_db_data_dir}/pg_xlog/%f \"%p\"'"
    
    _eval "rm -f ${g_db_data_dir%/}/recovery.conf;rm -f ${g_db_data_dir%/}/recovery.done"
    _expect "su - ${g_db_superuser} -c \"scp -C ${g_db_superuser}@${_new_master_ip}:${g_db_data_dir}/pg_xlog/*.history ${g_db_data_dir}/pg_xlog/\"" "dummy" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: scp connection to $_new_master_ip failed."; return 1; fi
    
    _eval "ln -s ${g_db_conf_dir%/}/recovery.conf ${g_db_data_dir%/}/recovery.conf" "" "${g_db_superuser}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: symlink to ${g_db_data_dir%/}/recovery.conf failed."; return 1; fi
    _warn "$FUNCNAME: Configuration for demote completed. Please restart postgresql service."
}

function f_showDbReplicationStatus() {
    local __doc__="Display current replication status of this server.
Note: this function does not support non default installation."
    local _check_data="$1"
    local _tmp_path=""
    local _tmp_port=""
    local _tmp_data_dir=""
    
    pg_lsclusters -h | while read l; do
        _tmp_pass="`echo "$l" | awk '{print $1"/"$2}'`"
        _tmp_port="`echo "$l" | awk '{print $3}'`"
        grep -iP '^wal_level\s*=\s*hot_standby' /etc/postgresql/${_tmp_pass%/}/postgresql.conf &>/dev/null
        if [ $? -eq 0 ]; then
            grep -iP '^standby_mode\s*=\s*on' /etc/postgresql/${_tmp_pass%/}/recovery.conf &>/dev/null
            if [ $? -eq 0 ]; then
                echo "# SLAVE : $l"
                _eval "psql -p ${_tmp_port} -x -c \"select pg_is_in_recovery() as is_slave, pg_is_xlog_replay_paused() as is_paused, pg_last_xlog_receive_location() as receive_location, pg_last_xlog_replay_location() as replay_location, pg_xlog_location_diff(pg_last_xlog_receive_location(), pg_last_xlog_replay_location()) as diff_byte, pg_xlog_location_diff(pg_last_xlog_receive_location(), '0/0') as total_receive_byte, pg_last_xact_replay_timestamp() as replaytime, now()\" | grep -v '^-\[ RECORD '" "N" "$g_db_superuser"
            else
                echo "# MASTER: $l"
                _eval "psql -p ${_tmp_port} -x -c \"select pid, client_addr, client_port, state, pg_current_xlog_location() as master_location, pg_xlogfile_name_offset(pg_current_xlog_location()) as master_xlog, pg_xlogfile_name_offset(sent_location) as sent_xlog, pg_xlogfile_name_offset(replay_location) as replay_xlog, pg_xlog_location_diff(pg_current_xlog_location(), replay_location) as diff_byte, pg_xlog_location_diff(sent_location, '0/0') as total_sent_byte, backend_start, now() from pg_stat_replication\"" "N" "$g_db_superuser"
            fi
            _tmp_data_dir="`echo $l | awk '{print $6}'`"
            _eval "ls -lt ${_tmp_data_dir%/}/pg_xlog/ | head -n 5"
            _eval "ls -lt ${_tmp_data_dir%/}/pg_xlog/archive_status/ | head -n 5"
        fi
        echo ""
    done
    
    #TODO: not good enough.
    #SELECT nspname || '.' || relname AS "relation", pg_relation_size(C.oid) AS "size" FROM pg_class C LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace) WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') ORDER BY nspname, relname;
    #if [ -n "$r_db_name" ]; then
    #    local _tmp_busy_tables_list=()
    #    _split "_tmp_busy_tables_list" "$g_db_big_tables"
    #    
    #    for _table in "${_tmp_busy_tables_list[@]}"; do
    #        _eval "psql -p $g_db_port $r_db_name -P pager=off -c \"SELECT * from $_table order by 1 desc limit 5\"" "" "$g_db_superuser"
    #    done
    #fi
}

function f_setupMonitoring() {
    local __doc__="Schedule hourly job to restart postgresql/apache if there is any DB connection issue.
Also monitor diskspace and load avg."
    local _conf_file="/etc/cron.hourly/build-monitoring"
    
    if [ -s "$_conf_file" ]; then
        f_backup "$_conf_file"
    else
        if ! $g_is_dryrun ; then 
            echo '#!/bin/bash' > $_conf_file && chmod a+x $_conf_file
        fi
    fi
    
    # NOTE: job Should not output anything if OK
    if ! $g_is_dryrun ; then # f_appendLine can't handle complicated command
        grep -w 'uptime' $_conf_file >/dev/null || echo "n=\`uptime | cut -d ',' -f 5\`;[ \${n/.*} -ge 5 ] && echo \"Load Average \$n is too high\"" >> $_conf_file
    fi
    if ! $g_is_dryrun ; then # f_appendLine can't handle complicated command
        # FreeBSD df -lh -c | grep ^total | awk '{print $5}'
        grep 'Disk space critical' $_conf_file >/dev/null || echo "df -lh | grep ^/ | grep -v -P '(/media/|/mnt/)' | egrep '(100%|9[0-9]%)' && echo \"Disk space critical\"" >> $_conf_file
    fi
    f_appendLine "$_conf_file" "/usr/sbin/sysv-rc-conf --list postgresql | grep -w '3:on' >/dev/null && lsof -ni:${g_db_port} | grep -w LISTEN >/dev/null || echo \"PostgreSQL is down\""
    f_appendLine "$_conf_file" "/usr/sbin/sysv-rc-conf --list apache2 | grep -w '3:on' >/dev/null && lsof -ni:80 | grep -w LISTEN >/dev/null || echo \"Apache2 is down\""
    
    f_appendLine "$_conf_file" "exit 0"
    
    _eval "$_conf_file"
    return $?
}

function f_installObserviumAgent() {
    local _monitoring_server_id="${1-$g_mon_server_ip}"
    
    if [ -z "$_monitoring_server_id" ]; then
        _error "$FUNCNAME: Monitoring server IP is not set."
        return 1
    fi
    
    local _apt_get="apt-get"
    
    if _isYes "$r_aptget_with_y" ; then
        # Without --force-yes, installation started failing...
        _apt_get="apt-get -y --force-yes"
    fi
    
    _eval "$_apt_get install xinetd libdbd-pg-perl libwww-perl"
    
    if [ $? -ne 0 ]; then
        _error "$FUNCNAME: installing required package failed."
        return 1
    fi
    
    if [ ! -s "/home/${g_automation_user}/.ssh/id_rsa" ]; then
        _error "$FUNCNAME: this function requires Automation User."
        return 1
    fi
    
    _eval "rsync -zvP -e \"ssh -i /home/${g_automation_user}/.ssh/id_rsa -o StrictHostKeyChecking=no\" ${g_automation_user}@${_monitoring_server_id}:/data/sites/monitoring/webroot/scripts/observium_agent_xinetd /etc/xinetd.d/observium_agent"
    
    if [ $? -ne 0 ]; then
        _error "$FUNCNAME: Copying files from ${_monitoring_server_id} failed (1)."
        return 1
    fi
    
    _eval "rsync -zvP -e \"ssh -i /home/${g_automation_user}/.ssh/id_rsa -o StrictHostKeyChecking=no\" ${g_automation_user}@${_monitoring_server_id}:/data/sites/monitoring/webroot/scripts/observium_agent /usr/bin/observium_agent"
    
    if [ $? -ne 0 ]; then
        _error "$FUNCNAME: Copying files from ${_monitoring_server_id} failed (2)."
        return 1
    fi
    
    _eval "mkdir -p /usr/lib/observium_agent/local"
    
    if [ $? -ne 0 ]; then
        _error "$FUNCNAME: Making agent local dir failed."
        return 1
    fi
    
    _eval "rsync -rzvh -e \"ssh -i /home/${g_automation_user}/.ssh/id_rsa -o StrictHostKeyChecking=no\" ${g_automation_user}@${_monitoring_server_id}:/data/sites/monitoring/webroot/scripts/agent-local/* /usr/lib/observium_agent/local/"
    
    if [ $? -ne 0 ]; then
        _error "$FUNCNAME: Copying files from ${_monitoring_server_id} failed (3)."
        return 1
    fi
    
    #_eval "a2enmod status"
    #_eval "chmod a+x /usr/lib/observium_agent/local/*.pl"
    #_eval "chmod a+x /usr/lib/observium_agent/local/*.sh"
    _eval "service xinetd restart"
    
    if [ $? -ne 0 ]; then
        _error "$FUNCNAME: restarting xinetd failed."
        return 1
    fi
    
    # Test
    grep "${_monitoring_server_id}" /etc/xinetd.d/observium_agent &>/dev/null
    if [ $? -ne 0 ]; then
        _warn "$FUNCNAME: /etc/xinetd.d/observium_agent does not contain monitoring server IP:${_monitoring_server_id}"
    fi
    
    /usr/lib/observium_agent/local/apache &>/dev/null
    if [ $? -ne 0 ]; then
        _warn "$FUNCNAME: You might need to run 'a2enmod status'"
    fi
    
    _info "To monitor PostgreSQL, you need to change permission of postgresql.pl and edit postgresql.conf" 
    return 0
}

function f_addDbAccess() {
    local __doc__="Adding one line into pg_hba.conf file.
IP Range should be like '192.168.56.1/32'."
    local _db_user="$1"
    local _ip_range="$2"
    local _auth_type="${3-md5}"
    local _database="${4-all}"
    local _pg_hba="$5"
    
    if [ -z "$_pg_hba" ]; then
        _pg_hba="${g_db_conf_dir%/}/pg_hba.conf"
    fi
    
    if [ -z "$_ip_range" ]; then
        _warn "$FUNCNAME: No IP range. Skipping..."
        return 0
    fi
    
    f_backup "$_pg_hba"
    f_appendLine "${_pg_hba}" "hostssl    ${_database}    ${_db_user}    ${_ip_range}    ${_auth_type}" "${g_db_superuser}"
    return $?
}

function f_changeDbPwd() {
    local __doc__="Change database user's password.
keyword: changeDbPassword, modifyDbPassword"
    local _db_username="${1-$r_db_username}"
    local _db_password="${2-$r_db_password}"
    
    if [ -z "$_db_username" ]; then
        _warn "$FUNCNAME: can't use with empty username."
        return 1
    fi
    if [ -z "$_db_password" ]; then
        _warn "$FUNCNAME: can't use with empty password."
        return 1
    fi
    if [ -z "$g_db_superuser" ]; then
        _warn "$FUNCNAME: can't use with empty superuser name."
        return 1
    fi
    
    if $g_is_dryrun; then return 0; fi
    
    _eval "psql -p ${g_db_port} -c \"alter user ${_db_username} with password '${_db_password}'\"" "N" "${g_db_superuser}"
    return $?
}

function f_installPgadminDebugger() {
    local __doc__="Set up pgAdmin Debugger on server side."
    local _db_name="${1-template1}"
    local _is_clean_setup="$2"
    local _suppress_restart="$3"
    local _pwd="$PWD"
    
    if [ -z "$_db_name" ]; then
        _db_name="template1"
        _info "DB name is $_db_name"
    fi
    
    if [ -e "/usr/lib/postgresql/${g_db_version}/lib/plugin_debugger.so" ]; then
        _warn "$FUNCNAME: plugin_debugger.so already exists. Skipping download/compile part..."
    else
        if [ "$g_db_version" = "9.2" ]; then
            local _url="ftp://ftp.postgresql.org/pub/source/v9.2.4/postgresql-9.2.4.tar.bz2"
            local _exact_version="9.2.4"
        else
            local _url="ftp://ftp.postgresql.org/pub/source/v9.1.9/postgresql-9.1.9.tar.bz2"
            local _exact_version="9.1.9"
        fi
        
        local _file_name="`basename $_url`"
        
        local _wget_cmd="wget -q -t 2 "
        if [ -n "$r_svn_user" ]; then
            _wget_cmd="wget -q -t 2 --http-user=${r_svn_user} --http-passwd=${r_svn_pass} ${g_svn_url%/}/installers/trunk/$_file_name"
        fi
        
        if _isYes "$_is_clean_setup" || [ -z "$r_svn_user" ]; then
            _eval "apt-get install -y build-essential libreadline6-dev"
            cd /usr/local/src/ && $_wget_cmd && _eval "tar jxf $_file_name && cd postgresql-${_exact_version} && ./configure && make && cd /usr/local/src/postgresql-${_exact_version}/contrib/ && git clone git://git.postgresql.org/git/pldebugger.git && cd ./pldebugger && make"
        else
            # or download the already complied one from SVN
            _eval "mkdir -p '/usr/local/src/postgresql-${_exact_version}/contrib' && cd /usr/local/src/postgresql-${_exact_version}/contrib/" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Making contrib dir failed."; return 1; fi
             f_getFromSvn "/installers/trunk/pldebugger-${_exact_version}_compiled.tgz" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Downloading pldebugger-${_exact_version}_compiled.tgz failed"; return 1; fi
            _eval "tar zxf pldebugger-${_exact_version}_compiled.tgz && cd ./pldebugger" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Extracting pldebugger-${_exact_version}_compiled.tgz failed"; return 1; fi
        fi
        
        _eval "mkdir -p '/usr/lib/postgresql/${g_db_version}/lib'"
        _eval "mkdir -p '/usr/share/postgresql/${g_db_version}/extension'"
        #_eval "/bin/mkdir -p '/usr/share/postgresql/${g_db_version}/doc/extension'"
        _eval "cp ./plugin_debugger.so /usr/lib/postgresql/${g_db_version}/lib/plugin_debugger.so && chmod 644 /usr/lib/postgresql/${g_db_version}/lib/plugin_debugger.so"
        _eval "cp ./pldbgapi.control /usr/share/postgresql/${g_db_version}/extension/ && chmod 644 /usr/share/postgresql/${g_db_version}/extension/pldbgapi.control"
        _eval "cp ./pldbgapi--1.0.sql ./pldbgapi--unpackaged--1.0.sql /usr/share/postgresql/${g_db_version}/extension/ && chmod 644 /usr/share/postgresql/${g_db_version}/extension/pldbgapi*.sql"
        #_eval "/bin/sh ../../config/install-sh -c -m 644 ./README.pldebugger '/usr/share/postgresql/${g_db_version}/doc/extension/'"
    fi
    
    _eval "psql -p ${g_db_port} ${_db_name} -c 'CREATE EXTENSION IF NOT EXISTS pldbgapi;'" "" "${g_db_superuser}"
    
    f_backup "${g_db_conf_dir%/}/postgresql.conf"
    f_setPostgreConf "shared_preload_libraries" "'/usr/lib/postgresql/${g_db_version}/lib/plugin_debugger.so'"
    
    cd "$_pwd"
    
    # checking
    su - ${g_db_superuser} -c "psql -p ${g_db_port} ${_db_name} -c '\dx'" | grep pldbgapi
    if [ $? -ne 0 ]; then
        _warn "$FUNCNAME: set up completed but extension 'pldbgapi' does not exist."
        return 1
    fi
    
    _info "$FUNCNAME: PostgreSQL restart required."
    return 0
}

function f_copyDbForDev() {
    local __doc__="Copy one database from remote PostgreSql to local *directly* for Build Developer."
    local _db_entity="${1}"
    local _new_db_name="${2}"
    local _env_name="${3}"
    local _ad_login="${4-$r_db_ad_login}"
    local _exclude_big_tables="${5}"
    
    if [ -n "$r_server_type" ] && [ "$r_server_type" != "dev" ]; then
        _warn "$FUNCNAME can't run non Dev env."
        return 1
    fi
    
    if [ -z "$r_server_type" ]; then 
        _warn "No r_server_type, so that *assuming* this server is DEV environment..."
        r_server_type="dev"
    fi
    
    if [ -z "$_db_entity" ]; then
        if [ -n "$tmp_db_entity" ]; then
            f_ask "Is this correct?" "$tmp_db_entity" "tmp_db_entity" "" "Y"
        elif [ -z "$r_db_entity" ]; then
            f_ask "Is this correct?" "$g_default_entity_name" "tmp_db_entity" "" "Y"
        else
            f_ask "Is this correct?" "$r_db_entity" "tmp_db_entity" "" "Y"
        fi
        _db_entity="$tmp_db_entity"
        #r_db_entity="$_db_entity"
    fi
    
    if [ -z "$_new_db_name" ]; then
        if [ -n "$tmp_new_db_name" ]; then
            f_ask "New DB name for local" "$tmp_new_db_name" "tmp_new_db_name" "" "Y"
        elif [ -z "$g_db_new_name" ]; then
            local _tmp_tmp_new_db_name="dev_${_db_entity}_$(date +"%Y%m%d")"
            f_ask "New DB name for local" "$_tmp_tmp_new_db_name" "tmp_new_db_name" "" "Y"
        else
            f_ask "New DB name for local" "$g_db_new_name" "tmp_new_db_name" "" "Y"
        fi
        _new_db_name="$tmp_new_db_name"
        g_db_new_name="$tmp_new_db_name"
    fi
    
    if [ -z "$_env_name" ]; then
        if [ -n "$tmp_env_name" ]; then
            f_ask "Env name shown in Build home page" "$tmp_env_name" "tmp_env_name" "" "Y"
        else
            f_ask "Env name shown in Build home page" "$_new_db_name" "tmp_env_name" "" "Y"
        fi
        _env_name="$tmp_env_name"
        r_db_env_name="$_env_name"
    fi
    
    if [ -z "$_ad_login" ]; then
        if [ -n "$tmp_ad_login" ]; then
            f_ask "Your Windows AD username" "$tmp_ad_login" "tmp_ad_login" "" "Y"
        else
            # don't care if r_db_ad_login is empty.
            f_ask "Your Windows AD username" "$r_db_ad_login" "tmp_ad_login" "" "Y"
        fi
        _ad_login="$tmp_ad_login"
        r_db_ad_login="$_ad_login"
    fi
    
    if [ -z "$_exclude_big_tables" ]; then
        if [ -n "$tmp_exclude_big_tables" ]; then
            f_ask "Excluding tables" "${tmp_exclude_big_tables}" "tmp_exclude_big_tables"
        else
            f_ask "Excluding tables" "${g_db_big_tables}" "tmp_exclude_big_tables"
        fi
        _exclude_big_tables="$tmp_exclude_big_tables"
    fi
    
    # FIXME: hard-coding host/ip and port are bad
    if [ "$_db_entity" = "$g_default_entity_name" ] || [ "$_db_entity" = "main" ]; then
        r_db_import_server="192.168.0.11"
        r_db_import_server_port="5432"
        r_db_name_remote="db_production"
        r_db_password_remote="`f_getBuildConfigValueFromPhp "core.database.password" "bneidb01-prod"`"
    elif [ "$_db_entity" = "sub" ]; then
        r_db_import_server="192.168.0.12"
        r_db_import_server_port="5433"
        r_db_name_remote="db2_production"
        r_db_password_remote="`f_getBuildConfigValueFromPhp "core.database.password" "hdvidb01-prod"`"
    else
        _warn "$FUNCNAME requires '_db_entity'"
        return 1
    fi
    
    r_db_username_remote="pgsql"
    r_db_name="$_new_db_name"
    r_db_exclude_tables="$_exclude_big_tables"
    r_db_save_sql="N"
    if [ -z "$r_db_username" ]; then
        f_ask "Local database user name" "$r_db_username_remote" "tmp_r_db_username"
        r_db_username="$tmp_r_db_username"
    fi
    if [ -z "$r_db_password" ]; then
        f_ask "Local database password" "" "tmp_r_db_password" "Y"
        r_db_password="$tmp_r_db_password"
    fi
    f_copyDb || return 1
    
    f_setupDbForDev "$_new_db_name" "$r_db_username" "$r_db_password" "$_env_name" "$_ad_login"
    _info "You might want to run \"f_changeBuildUserNoAd\" to change Auth method and password."
    return 0
}

function f_copyDb() {
    local __doc__="Copy one database from remote PostgreSql instance to local *directly*. For example:
pg_dump -h 127.0.0.1 -Upgsql -C dev_db_latest | psql -h 127.0.0.1 -p 5433 -Upgsql template1"
    local _remote_server="${1-$r_db_import_server}"
    local _remote_db_name="${2-$r_db_name_remote}"
    local _remote_db_user="${3-$r_db_username_remote}"
    local _remote_db_pass="${4-$r_db_password_remote}"
    local _db_name="${5-$r_db_name}"
    local _db_user="${6-$r_db_username}"
    local _db_pass="${7-$r_db_password}"
    local _drop_db="${8-$r_db_drop}"
    local _exclude_tables="${9-$r_db_exclude_tables}"
    local _save_sql="${10-$r_db_save_sql}"
    local _try_ssh="${11}"
    local _remote_port="${r_db_import_server_port}"
    local _dummy_port="4${g_db_port}" #45432
    local _cmd=""
    
    if [ -z "$_remote_server" ]; then
        _warn "$FUNCNAME: No server specified to connect. Skipping..."
        return 1
    fi
    
    if [ -z "$_remote_port" ]; then
        _remote_port="${g_db_port}"
    fi
    
    if [ -z "$_remote_db_name" ]; then
        if [ -n "$_db_name" ]; then
            _remote_db_name="$_db_name"
            _info "$FUNCNAME: No remote database name specified. Using $_remote_db_name ..."
        else
            _warn "$FUNCNAME: No remote database name specified. Skipping..."
            return 1
        fi
    fi
    
    if [ -z "$_remote_db_user" ]; then
        if [ -n "$_db_user" ]; then
            # FIXME: this condition is not good enough as password can be empty.
            _remote_db_user="$_db_user"
            _remote_db_pass="$_db_pass"
            _info "$FUNCNAME: No remote user name specified. Using $_remote_db_user ..."
        else
            _remote_db_user="${g_db_username}"
            _info "$FUNCNAME: Remote DB User name is empty, so that using ${g_db_username}"
        fi
    fi
    
    if [ -z "$_db_name" ]; then
        _db_name="$_remote_db_name"
        _info "$FUNCNAME: Using $_remote_db_name for local database name."
        return 1
    fi
    
    if [ -z "$_db_user" ]; then
        if [ -n "$_remote_db_user" ]; then
            _db_user="$_remote_db_user"
            _db_pass="$_remote_db_pass"
        else
            _db_user="${g_db_username}"
        fi
        _info "Local DB User name is empty, so that using ${_db_user}"
    fi
    
    # checking if database is already existed
    if _isDbExist "$_db_name" ; then
        if ! _isYes "$_drop_db" ; then
            _warn "$FUNCNAME: ${_db_name} exists. Please run 'dropdb' first."
            return 1
        fi
    fi
    
    # Would need at least 10GB free space
    if ! f_isEnoughDisk "$g_db_home" "10" ; then
        _warn "$FUNCNAME: $g_db_home space is less than 10GB. Aborting..."
        return 1
    fi
    
    local _check_sql="SELECT pg_database_size('${_remote_db_name}');"
    local _remote_connect="-h ${_remote_server} -p ${_remote_port}"
    
    # FIXME: if we try, it is logged as FATAL on target server, so that not trying at this moment...
    _try_ssh="Y"
    # If try_ssh is not explicitly NO, test if ssh tunnel is needed.
    if [ -z "$_try_ssh" ]; then
        eval "PGPASSWORD=\"${_remote_db_pass}\" psql -x ${_remote_connect} -U ${_remote_db_user} ${_remote_db_name} -c \"$_check_sql\"" &>/dev/null
        if [ $? -ne 0 ]; then
            _try_ssh="Y"
        fi
    fi
    
    if _isYes "$_try_ssh" ; then
        _info "Creating SSH Tunnel to ${r_db_import_user}@${_remote_server}..."
        f_sshTunnel "$_remote_server" "$r_db_import_user" "$r_db_import_pass" "$_dummy_port" "$_remote_port" "Y" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not establish SSH connection to ${_remote_server}."; return 1; fi
        
        # re-confirming tunnel
        _eval "PGPASSWORD=\"${_remote_db_pass}\" psql -x -h 127.0.0.1 -p ${_dummy_port} -U ${_remote_db_user} ${_remote_db_name} -c \"$_check_sql\" >/dev/null" "N"
        if [ $? -ne 0 ]; then
            _warn "$FUNCNAME: Could not establish SSH connection to ${_remote_server}."
            return 1
        fi
        
        _remote_connect="-h 127.0.0.1 -p ${_dummy_port}"
    fi
    
    # Get remote server's DB size
    local _remote_size="$(PGPASSWORD="${_remote_db_pass}" psql -x ${_remote_connect} -U ${_remote_db_user} ${_remote_db_name} -c "$_check_sql" | grep "pg_database_size" | grep -o -P '\d+')"
    
    # Creating database
    _createDb "${_db_name}" "${_db_user}" "${_db_pass}" "$r_db_encoding" "$_drop_db" || _critical "$FUNCNAME: Creating database $_db_name failed."
    
    # Get remote server's DB encoding
    local _remote_encoding="$(PGPASSWORD="${_remote_db_pass}" psql ${_remote_connect} -U ${_remote_db_user} -l | grep -w $_remote_db_name | cut -d "|" -f 3)"
    _remote_encoding=`_trim "$_remote_encoding"`
    if [ -z "$_remote_encoding" ]; then
        _warn "$FUNCNAME: Could not determine the remote $_remote_db_name encoding. Assuming same as local ($r_db_encoding) ..."
        _remote_encoding="$r_db_encoding"
    else
        _info "$FUNCNAME: remote $_remote_db_name encoding is $_remote_encoding"
    fi
    
    local _iconv=""
    # FIXME: assuming remote is SQL_ASCII. would need more complex logic in here
    if [ "$r_db_encoding" != "$_remote_encoding" ]; then
        if [ "$_remote_encoding" = "SQL_ASCII" ]; then
            _info "Local DB encoding (r_db_encoding) is not same as remote and not SQL_ASCII. Using iconv -t UTF-8..."
            # FIXME: at this moment, we support only UTF-8 or SQL_ASCII, so that don't need extra 'if' but we might need more condition later
            _iconv="| iconv -f ISO-8859-1 -t UTF-8 "
        fi
    fi
    
    local _psql_cmd="psql -h 127.0.0.1 -p ${g_db_port} -U ${_db_user} ${_db_name}"
    local _pgdump_cmd="pg_dump ${_remote_connect} -U ${_remote_db_user} ${_remote_db_name}"
    
    if [ -n "$_exclude_tables" ]; then
        pg_dump --help | grep 'exclude-table-data' &>/dev/null
        if [ $? -eq 0 ]; then
            local _final_exclude_tables=""
            local _tmp_exclude_tables_list=()
            
            # If string includes comma or space, split
            if [[ "$_exclude_tables" =~ "," ]]; then
                _split "_tmp_exclude_tables_list" "$_exclude_tables"
            elif [[ "$_exclude_tables" =~ " " ]]; then
                _split "_tmp_exclude_tables_list" "$_exclude_tables" " "
            fi
            
            if [ ${#_tmp_exclude_tables_list[@]} -eq 0 ]; then
                _pgdump_cmd="$_pgdump_cmd --exclude-table-data=\"$_exclude_tables\""
            else
                for _ext_table in "${_tmp_exclude_tables_list[@]}"; do
                    _final_exclude_tables="$_final_exclude_tables --exclude-table-data=\"$_ext_table\""
                done
                _pgdump_cmd="${_pgdump_cmd}${_final_exclude_tables}"
            fi
        else
            _warn "$FUNCNAME: exclude-table-data is not available. Ignoring _exclude_tables..."
        fi
    fi
    
    _info "$_pgdump_cmd | $_psql_cmd"
    
    local _tmp_verbose="Y"
    if [ -n "$_db_pass" ]; then 
        _psql_cmd="PGPASSWORD=\"${_db_pass}\" ${_psql_cmd}";
        _tmp_verbose="N"
    fi
    
    if [ -n "$_remote_db_pass" ]; then 
        _pgdump_cmd="PGPASSWORD=\"${_remote_db_pass}\" $_pgdump_cmd"
        _tmp_verbose="N"
    fi
    
    # If _save_sql is empty and if there is plenty of disk space but low memory, just in case, saving SQL.
    if f_isEnoughDisk "/tmp" "6" ; then
        if [ -z "$_save_sql" ]; then
            _save_sql="Y"
        fi
    else
        if _isYes "$_save_sql" ; then
            _warn "$FUNCNAME: /tmp does not have enough space to save SQL. Aborting..."
            return 1
        fi
    fi
    
    if _isYes "$_save_sql" ; then
        local _file_path="/tmp/${_remote_db_name}_${_remote_server}_$(date +"%Y%m%d-%H%M%S").sql"
        _info "Saving SQL file to ${_file_path}..."
        if f_isEnoughMemory "4000" ; then
            _eval "$_pgdump_cmd $_iconv| tee $_file_path | $_psql_cmd" "$_tmp_verbose" 1>/tmp/f_copyDatabase_${g_pid}.tmp &
        else
            _eval "$_pgdump_cmd $_iconv > $_file_path && $_psql_cmd -f $_file_path" "$_tmp_verbose" 1>/tmp/f_copyDatabase_${g_pid}.tmp &
        fi
    else
        _eval "$_pgdump_cmd $_iconv| $_psql_cmd" "$_tmp_verbose" 1>/tmp/f_copyDatabase_${g_pid}.tmp &
    fi
    
    _bgProgress "DB Copy" "/tmp/f_copyDatabase_${g_pid}.tmp" "$g_db_expect_line"; wait $!
    grep -P '(WARN|ERROR)' /tmp/f_copyDatabase_${g_pid}.tmp || rm -f /tmp/f_copyDatabase_${g_pid}.tmp
    
    if _isYes "$_try_ssh" ; then
        _info "Cleaning up tunnel if exists..."
        _killByPort "${_dummy_port}"
        #_killByPort "${_mon_port}"
    fi
    
    # Test
    local _local_size="$(PGPASSWORD="${_db_pass}" psql -h 127.0.0.1 -p ${g_db_port} -U ${_db_user} ${_db_name} -x -c "SELECT pg_database_size('${_db_name}');" | grep "pg_database_size" | grep -o -P '\d+')"
    
    _echo "Remote DB size: $_remote_size"
    _echo "Local DB size : $_local_size"
    
    if [ "$_local_size" -lt "$_remote_size" ]; then
        _warn "Local DB size looks smaller than remote DB size."
    fi
    
    # g_last_rc does not guarantee to store previous _eval but anyway returning..
    return $g_last_rc
}

function f_sshTunnel() {
    local __doc__="Create a ssh tunnel."
    local _remote_server="$1"
    local _remote_user="$2"
    local _remote_pass="$3"
    local _local_port="$4"
    local _remote_port="$5"
    local _kill_process_first="${6-N}"
    
    if [ -z "$_remote_port" ]; then
        _remote_port="$_local_port"
    fi
    
    if _isYes "$_kill_process_first" ; then
        _killByPort "$_local_port"
    fi
    
    if _isSshTunneling "${_local_port}" "${_remote_server}"; then
        #_info "Tunnel is already exist. Skipping..."
        return 0
    fi
    
    if [ -z "$_remote_user" ]; then
        _remote_user="$g_automation_user"
        #_remote_user="$SUDO_USER"
    fi
    
    if [ "$_remote_user" = "$g_automation_user" ]; then
        f_copyAutomationUserRsaKey
        
        # buildautomation would not need password, would it?
        #if [ -z "$_remote_pass" ]; then
        #    _remote_pass="$(f_getBuildConfigValueFromSvn "core.automation.password")"
        #fi
    fi
    
    local _user_hostname="${_remote_user}@${_remote_server}"
    local _key_path="/home/${_remote_user}/.ssh/id_rsa"
    local _option=""
    if [ -s "$_key_path" ]; then
        _option="-i $_key_path"
    else
        _warn "Could not find the SSH key, but keep going..."
    fi
    
    # FIXME: not sure if 127.0.0.1 works with all OS.
    local _ssh_args="-C -N -L ${_local_port}:127.0.0.1:${_remote_port} ${_user_hostname}"
    
    ssh -q ${_option} -o StrictHostKeyChecking=no -o BatchMode=yes ${_user_hostname} 'echo "INFO: SSH connection test before ssh Tunneling."'
    if [ $? -eq 0 ]; then
        _eval "ssh ${_option} -f $_ssh_args"
    else
        _info "ssh ${_option} $_ssh_args"
        if $g_is_dryrun; then return 0; fi
        # FIXME: somehow below outputs "Stopped(SIGTTOU) _expect ..." but tunnel works.
        _expect "ssh ${_option} -o StrictHostKeyChecking=no $_ssh_args" "$_remote_pass" &
    fi
    
    sleep 1; lsof -nPi:${_local_port} | grep '127.0.0.1' &>/dev/null
    if [ $? -ne 0 ]; then
        sleep 2; lsof -nPi:${_local_port} | grep '127.0.0.1' &>/dev/null
        if [ $? -ne 0 ]; then
            # gave up and return error
            return 1
        fi
    fi
    
    return 0
}

function _isSshTunneling() {
    local _local_port="$1"
    local _remote_host="$2"
    
    local _pid=`lsof -nPi:$_local_port | grep -P "^ssh .+? 127.0.0.1:$_local_port \(LISTEN\)" | awk '{print $2}'`
    if [ -z "$_pid" ]; then
        return 1
    fi
    
    netstat -apn | grep -P "${_remote_host}:22\s+ESTABLISHED ${_pid}/ssh" &>/dev/null
    return $?
}

function _killByPort() {
    local _port="$1"
    local _force="$2"
    
    local _pids=`lsof -nPi:${_port} | grep 127.0.0.1 | awk '{print $2}'`
    if $g_is_dryrun; then
        return 0
    elif [ -n "$_pids" ]; then
        if _isYes "$_force"; then
            kill -9 $_pids
        else
            kill $_pids
        fi
    fi
    
    return $?
}

### Web server (Apache/PHP) setup functions ###################################
function f_installApacheAndPhp() {
    local __doc__="Install and set up Apache and PHP for Build."
    
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    _eval "$_apt_get install apache2 apache2-utils php5 libapache2-mod-php5 php5-mcrypt php5-imap php5-imagick php5-sqlite php5-pgsql php5-ldap php5-curl php5-cli php5-gd php5-svn php5-pspell php5-dev php-apc" || _critical "$FUNCNAME: Installing Apache and Php packages failed."
    return $?
}

function f_setupApache() {
    local __doc__="Set up Apache for Build including creating a virtual host with f_addApacheVirtualHost."
    local _user_conf_file="/etc/apache2/httpd.conf"
    
    local _hostname="$g_hostname"
    if [ -n "$r_new_hostname" ]; then _hostname="$r_new_hostname"; fi
    
    f_backup "$_user_conf_file"
    f_appendLine "$_user_conf_file" "ServerName $_hostname"
    
    f_backup "/etc/apache2/ports.conf"
    f_insertLine "/etc/apache2/ports.conf" "<IfModule mod_ssl.c>" "    NameVirtualHost *:443" "Y"
    
    # FIXME: appendline is better because it checks if the line already exist, but not sure if it works with multiple lines
    _eval "a2enmod headers"
    grep "text/css" $_user_conf_file || _eval "echo -e \"<Files *.css>\n  Header set Content-type \"text/css\"\n</Files>\" >> $_user_conf_file" || _critical "$FUNCNAME: Configuring Apache $_user_conf_file failed."
    grep "application/javascript" $_user_conf_file || _eval "echo -e \"<Files *.js>\n  Header set Content-type \"application/javascript\"\n</Files>\" >> $_user_conf_file" || _critical "$FUNCNAME: Configuring Apache $_user_conf_file failed."
    
    f_backup "/etc/apache2/mods-enabled/mime.conf"
    f_insertLine "/etc/apache2/mods-enabled/mime.conf" "</IfModule>" "AddType application/x-httpd-php .php .xul .css .js"
    
    f_addApacheVirtualHost
    
    # making sure disabling default as per request
    _eval "a2dissite default"
    _eval "service apache2 restart" || _critical "$FUNCNAME: Starting Apache failed."
    return $?
}

function f_addApacheVirtualHost() {
    local __doc__="Add/create a new virtual host. If no argument, will use r_apache_xxxx parameters.
'_document_root' is optional. If empty, it will be '${g_apache_data_dir%/}/_server_name/${g_apache_webroot_dirname}'"
    local _server_name="$1"
    local _env_website="$2"
    local _server_alias="${3-$_server_name}"
    local _document_root="$4"
    
    if [ -n "$_server_name" ]; then
        _info "Updating r_apache_server_name to $_server_name"
        r_apache_server_name="$_server_name"
        
        if [ -z "$_server_alias" ]; then
            _server_alias="$_server_name"
        fi
        if [ -z "$_document_root" ]; then
            _document_root="${g_apache_data_dir%/}/${_server_name}/${g_apache_webroot_dirname}"
        fi
    fi
    
    if [ -z "$r_apache_server_name" ]; then
        _warn "$FUNCNAME: No Server Name."
        return 0
    fi
    
    if [ -n "$_document_root" ]; then
        _info "Updating r_apache_document_root to $_document_root"
        r_apache_document_root="$_document_root"
    fi
    
    if [ -n "$_server_alias" ]; then
        _info "Updating r_apache_server_alias to $_server_alias"
        r_apache_server_alias="$_server_alias"
    fi
    
    # this condition would not be necessary but just in case...
    if [ -z "$r_apache_server_alias" ]; then
        _info "Updating r_apache_server_alias to r_apache_server_name $r_apache_server_name"
        r_apache_server_alias="$r_apache_server_name"
    fi
    
    if [ -n "$_env_website" ]; then
        _info "Updating r_apache_env_website to $_env_website"
        r_apache_env_website="$_env_website"
    fi
    
    local _vhost_config_path="/etc/apache2/sites-available/${r_apache_file_name}"
    
    if [ -n "${r_apache_document_root%/}" ]; then
        if [ ! -d "${r_apache_document_root%/}" ]; then
            _warn "$FUNCNAME: ${r_apache_document_root%/} does not exist but keep going... Please create it later."
        fi
    else
        _warn "$FUNCNAME: No document root specified but keep going... Please revew $_vhost_config_path later."
    fi
    
    if [ -s "$_vhost_config_path" ]; then
        _warn "$FUNCNAME: \"$_vhost_config_path\" exists. Skipping Apache configuration."
        return 1
    fi
    
    local _virtual_host_str="$(_generateVirtualHostStr)"
    _eval "echo -e '${_virtual_host_str}' > $_vhost_config_path && a2ensite $r_apache_file_name" || _critical "$FUNCNAME: Configuring Apache failed."
    
    if [ -n "$r_apache_server_alias" ]; then
        f_backup "/etc/hosts"
        f_setConfig "/etc/hosts" "127.0.0.1" "$r_apache_server_alias" "#" " " "Y" " " 
    fi
    
    if [ -z "$r_server_type" ] || [ "$r_server_type" = "dev" ]; then
        f_setupApacheSsl "$r_apache_server_name" "$g_default_domain" || _warn "$FUNCNAME: SSL set up for $g_default_domain failed."
    else
        f_setupApacheSsl "$r_apache_server_name" "$r_db_entity" || _warn "$FUNCNAME: SSL set up for $r_db_entity failed."
    fi
    
    _warn "$FUNCNAME: please run 'service apache2 reload'"
    return 0
}

function f_listApacheVirtualHost() {
    local __doc__="Output currently enabled or available virtual hosts/sites"
    local _show_available="$1"
    
    local _conf_dir="/etc/apache2/sites-enabled"
    if _isYes "$_show_available"; then
        local _conf_dir="/etc/apache2/sites-available"
    fi
    
    cd $_conf_dir &&  grep -oiHP '(ServerName\s+.+|ServerAlias\s+.+|WEBSITE\s+.+|DocumentRoot\s+.+)' * ; cd - &>/dev/null
}

function f_setupApacheSsl() {
    local __doc__="Set up SSL based on existing ServerName $r_apache_server_name.
If _domain is explicitly empty, use default-ssl (self-sert). 
Otherwise, use $g_default_domain, testdomain.com, morobejv.com"
    local _file_name="${1-$r_apache_file_name}"
    local _domain="${2-$g_default_domain}"
    local _ssl_dir_name="/etc/apache2/ssl"
    local _pwd="$PWD"
    
    _askSvnUser
    if [ $? -ne 0 ]; then
        _warn "$FUNCNAME: No SVN username. Exiting."; return 1
    fi
    
    _mkdir "$_ssl_dir_name"
    _eval "a2enmod ssl"
    
    # If not domain given, using default self-cert
    if [ -z "$_domain" ] ; then
        _eval "a2ensite default-ssl"
        return $?
    else
        # For name based virtual host
        _eval "a2dissite default-ssl"
    fi
    
    if [ "$_domain" = "$g_default_entity_name" ]; then
        _domain="testdomain.com"
    fi
    
    local _vhost_config_path="/etc/apache2/sites-available/${_file_name}-ssl"
    
    if [ -s "$_vhost_config_path" ]; then
        _warn "$FUNCNAME: $_vhost_config_path already exists. Skipping..."
        return 0
    fi
    
    cd $_ssl_dir_name || _critical "cd $_ssl_dir_name dir failed."
    
    if [ "$_domain" != "$g_default_domain" ]; then
        f_getFromSvn "/server-configurations/common/ssl_certificates/${_domain}_intermediate.crt" || _critical "$FUNCNAME: Downloading ${_domain}_intermediate.crt failed."
    fi
    
    f_getFromSvn "/server-configurations/common/ssl_certificates/${_domain}.crt" || _critical "$FUNCNAME: Downloading ${_domain}.crt failed."
    f_getFromSvn "/server-configurations/common/ssl_certificates/${_domain}.key" || _critical "$FUNCNAME: Downloading ${_domain}.key failed."
    
    _eval "chmod 400 ${_ssl_dir_name}/${_domain}*" || _critical "$FUNCNAME: chmod ${_domain} cert/key failed."
    
    cd $_pwd
    
    local _virtual_host_str="$(_generateVirtualHostStr "${_domain}" "Y")"
    _eval "echo -e '${_virtual_host_str}' > $_vhost_config_path && a2ensite ${_file_name}-ssl" || _critical "$FUNCNAME: Configuring Apache failed."
    return $?
}

function _generateVirtualHostStr() {
    # NOTE: this function should not output anything to STDOUT
    local _domain="$1"
    local _is_ssl="$2"
    local _server_name="${3-$r_apache_server_name}"
    local _server_alias="${4-$r_apache_server_alias}"
    local _document_root="${5-$r_apache_document_root}"
    local _env_website="${6-$r_apache_env_website}"
    local _server_type="${7-$r_server_type}"
    local _port=":80"
    
    if _isYes "$_is_ssl"; then
        _port=":443"
    fi
    
    local _apache_options="Options -Indexes FollowSymLinks MultiViews"
    if [ "$_server_type" = "dev" ]; then
        _apache_options="Options Indexes FollowSymLinks"
    fi
    
    if [ -z "$_server_name" ]; then
        _warn "$FUNCNAME: No ServerName, so that using hostname: $g_hostname"
        _server_name="$g_hostname"
    fi
    local _orig_server_name="$_server_name"
    
    if [ -z "$_server_alias" ]; then
        _server_alias="$_server_name"
    fi
    
    if [ -n "$_domain" ]; then
        _server_alias="${_server_alias} ${_server_alias}.${_domain}"
        #_server_name="${_orig_server_name}.${_domain}"
    fi
    
    # NOTE: don't forget escaping double-quote in _virtual_host_template or use _escape_double_quote which does not re-escape
    if _isYes "$_is_ssl"; then
        if [ ! -s "/etc/apache2/ssl/${_domain}.crt" ]; then
            _warn "$FUNCNAME: /etc/apache2/ssl/${_domain}.crt does not exist."
        fi
        if [ ! -s "/etc/apache2/ssl/${_domain}.key" ]; then
            _warn "$FUNCNAME: /etc/apache2/ssl/${_domain}.key does not exist."
        fi
        if [ "$_server_type" != "dev" ]; then
            if [ ! -s "/etc/apache2/ssl/${_domain}_intermediate.crt" ]; then
                _warn "$FUNCNAME: /etc/apache2/ssl/${_domain}_intermediate.crt does not exist."
            fi
        fi
        
        echo "<IfModule mod_ssl.c>"
    fi
    echo "<VirtualHost *${_port}>"
    echo "    ServerName ${_server_name}"
    echo "    ServerAlias ${_server_alias}"
    echo "    DocumentRoot ${_document_root%/}"
    if _isYes "$_is_ssl"; then
        # FIXME: what if _domain is empty?
        echo "    SSLEngine on"
        echo "    SSLCertificateFile    /etc/apache2/ssl/${_domain}.crt"
        echo "    SSLCertificateKeyFile /etc/apache2/ssl/${_domain}.key"
        if [ "$_server_type" != "dev" ]; then
            echo "    SSLCACertificateFile  /etc/apache2/ssl/${_domain}_intermediate.crt"
        fi
    fi
    echo "    SetEnv WEBSITE ${_env_website}"
    echo "    <Directory \"${_document_root%/}\">"
    echo "        ${_apache_options}"
    echo "        AllowOverride all"
    echo "        Order allow,deny"
    echo "        Allow from all"
    echo "        php_value auto_prepend_file ${_document_root%/}/xul/core_ui/bootstrap.php"
    echo "    </Directory>"
    echo "    BrowserMatch \"MSIE [2-6]\" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0"
    echo "    BrowserMatch \"MSIE [17-9]\" ssl-unclean-shutdown"
    if _isYes "$_is_ssl"; then
        echo '    <FilesMatch "\.(cgi|shtml|phtml|php)$">'
        echo "        SSLOptions +StdEnvVars"
        echo "    </FilesMatch>"
    fi
    echo "</VirtualHost>"
    if _isYes "$_is_ssl"; then
        echo "</IfModule>"
    fi
}

function f_setupPhp() {
    local __doc__="Set up PHP for Build."
    
    # don't care if the following command fails
    _eval "mv /etc/php5/cli/php.ini /etc/php5/cli/php_orig.ini && ln -s ${g_php_ini_path} /etc/php5/cli/php.ini"
    
    f_backup "${g_php_ini_path}"
    
    if [ -n "$r_date_timezone" ]; then
        f_setPhpIni "date.timezone" "\"${r_date_timezone}\""
    fi
    
    for _k in "${!g_php_ini_array[@]}"; do
        f_setPhpIni "$_k" "${g_php_ini_array[$_k]}"
    done
    
    f_backup "/etc/php5/conf.d/apc.ini"
    f_setConfig "/etc/php5/conf.d/apc.ini" "apc.shm_size" "256M" ";"

    _eval "touch ${g_php_ini_array['error_log']} && chmod 666 ${g_php_ini_array['error_log']}"
    
    if [ -n "${g_php_ini_array['session.save_path']}" ]; then
        #_mkdir "${g_php_ini_array['session.save_path']}" "700" && chown -R ${g_apache_user}:${g_apache_user} ${g_php_ini_array['session.save_path']}
        _eval "ln -s /var/lib/php5 ${g_php_ini_array['session.save_path']}"
    fi
    
    if [ "$r_server_type" = "dev" ]; then
        f_installPhpXDebug
    fi
    
    _eval "service apache2 restart" || _critical "$FUNCNAME: Starting Apache failed."
}

function f_installPhpXDebug() {
    local __doc__="Install and Setup PHP Xdebug. Do not use this on Production."
    local _conf_file="/etc/php5/conf.d/xdebug.ini"
    local _log_file="/var/log/xdebug_remote.log"
    local _apt_get="apt-get"
    if _isYes "$r_aptget_with_y" ; then
        _apt_get="apt-get -y"
    fi
    
    _eval "$_apt_get install php5-xdebug" ; if [ $? -ne 0 ]; then _error "Installing xdebug package failed."; return 1; fi
    _eval "touch $_log_file && chmod 666 $_log_file" ; if [ $? -ne 0 ]; then _warn "Creating xdebug log file failed."; return 1; fi
    
    #f_setConfig "$_conf_file" "zend_extension" "/usr/lib/php5/20090626/xdebug.so" ";"    # this is already there.hajime
    f_setConfig "$_conf_file" "xdebug.remote_port" "9000" ";"
    f_setConfig "$_conf_file" "xdebug.remote_handler" "dbgp" ";"
    f_setConfig "$_conf_file" "xdebug.remote_log" "$_log_file" ";"
    f_setConfig "$_conf_file" "xdebug.remote_enable" "on" ";"
    f_setConfig "$_conf_file" "xdebug.remote_autostart" "off" ";"
    f_setConfig "$_conf_file" "xdebug.remote_connect_back" "on" ";"
    f_setConfig "$_conf_file" "xdebug.remote_host" "192.168.56.1" ";" # for CLI debug
    #f_setPhpIni "html_errors" "On"    # FIXME: Do we need this?
    
    _info "Please restart apache service later."
    return 0
}

### Application contents import/commit functions #####################################
function f_startImportContents() {
    local __doc__="Importing Build source code, Build Admdocs, Build database."
    
    _info "Importing Build contents (source code/database/admdocs)..."
    f_importCode
    f_importDocs
    f_importDb
    
    wait
    
    cat /tmp/f_importCode_${g_pid}.out >> $g_command_output_log 2>/dev/null && rm -f /tmp/f_importCode_${g_pid}.out
    cat /tmp/f_importDocs_${g_pid}.out >> $g_command_output_log 2>/dev/null && rm -f /tmp/f_importDocs_${g_pid}.out
    
    if _isYes "$r_commit_etc"; then
        _info "Committing /etc to SVN and scheduling this daily."
        f_commitEtc
    fi
    
    if _isYes "$r_svn_update" && [ "$r_code_import" = "svn" ]; then
        _info "Scheduling SVN UPDATE ..."
        f_scheduleSvnUpdate
        _info "Scheduling MISC TASKS dailyMaintenance ..."
        f_scheduleMiscTasks "$r_apache_document_root" "$r_apache_env_website" "0" "dailyMaintenance"
        _info "Scheduling MISC TASKS hourlyMaintenance ..."
        f_scheduleMiscTasks "$r_apache_document_root" "$r_apache_env_website" "" "hourlyMaintenance"
    fi
}

function f_importCode() {
    local __doc__="Importing Build source code with ${r_code_import}.
'_code_import_from' can be an empty if code impor type is 'svn'"
    local _code_import_from="${1-$r_code_import_path}"
    local _code_import_target="${2-$r_code_import_target}"
    local _final_cmd="$r_code_import_cmd"
    
    if [ -z "$_code_import_target" ]; then
        _warn "$FUNCNAME: No import taget specified. Skipping..."
        return 1
    fi
    
    _mkdir "$_code_import_target"
    
    if [ "$r_code_import" = "svn" ]; then
        if [ -z "$_code_import_from" ]; then
            if [ -z "$r_svn_url_build" ]; then
                r_svn_url_build="$g_svn_url_build"
            fi
            _code_import_from="${r_svn_url_build%/}/site"
            _info "$FUNCNAME: No code import from, so that using $_code_import_from"
        fi
        
        _info "Running \"svn co $_code_import_from ${_code_import_target}\"..."
        f_svnCheckOut "$_code_import_from" "${_code_import_target}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: svn co failed."; return 1; fi
        f_modBuildPerms
    elif [ "$r_code_import" = "smb" ]; then
        if [ -z "$r_code_import_cred_path" ]; then
            r_code_import_cred_path="/root/.${r_code_import}_${r_code_import_server}"
        fi
        
        if [ -z "$_final_cmd" ]; then
            if [ -z "$_code_import_from" ]; then
                _warn "$FUNCNAME: No import from specified. Skipping..."
                return 1
            else
                _final_cmd="mount -t cifs ${_code_import_from} ${_code_import_target} -o credentials=${r_code_import_cred_path},${g_smbfs_options}"
                _info "$FUNCNAME: $_final_cmd"
            fi
        fi
        
        if [ -n "$r_code_import_cred_path" ]; then
            f_setConfig "$r_code_import_cred_path" "username" "$r_code_import_user"
            f_setConfig "$r_code_import_cred_path" "password" "$r_code_import_pass"
            f_setConfig "$r_code_import_cred_path" "domain" "$r_code_import_domain"
            chmod 1600 "$r_code_import_cred_path"
        fi
        _eval "$_final_cmd"
        f_insertLine "$g_startup_script_path" "exit 0" "$_final_cmd"
    elif [ "$r_code_import" = "ssh" ]; then
        if [ -z "$_final_cmd" ]; then
            if [ -z "$_code_import_from" ]; then
                _warn "$FUNCNAME: No import from specified. Skipping..."
                return 1
            else
                _final_cmd="sshfs -o ${g_sshfs_options} ${r_code_import_user}@${r_code_import_server}:${_code_import_from} ${_code_import_target}"
                _info "$FUNCNAME: $_final_cmd"
            fi
        fi
        
        if [ "$r_code_import_user" = "$g_automation_user" ]; then
            f_copyAutomationUserRsaKey
        else
            f_copyPubKey "${r_code_import_user}@${r_code_import_server}" "$r_code_import_pass" "$r_code_import_cred_path"
        fi
        
        f_insertLine "$g_startup_script_path" "exit 0" "$_final_cmd"
        _eval "$_final_cmd" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: ssh import command failed."; return 1; fi
    elif [ "$r_code_import" = "skip" ] || [ -z "$r_code_import" ]; then
        _warn "$FUNCNAME: As per import type '$r_code_import', Skipping..."
        return 0
    else
        _warn "$FUNCNAME: Unknown import type '$r_code_import', Skipping..."
        return 1
    fi
    
    # Not in use at thsi moment
    #if [ -n "$r_code_import_fstab" ]; then
    #    f_appendLine "/etc/fstab" "$r_code_import_fstab"
    #fi
    
    #if [ -z "$r_server_type" ] || [ "$r_server_type" = "dev" ]; then
    #    _info "Not running f_importSqlSchema"
    #else
        # not sure if this is necessary for all prod servers...
        #_info "Running f_importSqlSchema"
        #f_importSqlSchema
    #fi
    
    f_modBuildConfig
}

function f_svnCheckOut() {
    local __doc__="Execute SVN Checkout command (svn co)"
    local _svn_path="$1"
    local _target_dir="$2"
    local _svn_option="$3"
    local _is_background="$4"
    local _verbose="$g_is_verbose"
    
    if ! _isUrl "$_svn_path"; then
        _warn "$FUNCNAME: Given SVN URL \"${_svn_path}\" is not a URL. Skipping..."
        return 1
    fi
    
    if ! _isFilePath "$_target_dir"; then
        _warn "$FUNCNAME: Given target path \"${_target_dir}\" is not a file path. Skipping..."
        return 1
    fi
    
    if _isNotEmptyDir "$_target_dir"; then
        _warn "$FUNCNAME: Given target path \"${_target_dir}\" is not empty. Skipping..."
        return 0
    fi
    
    local _svn_cmd="svn co ${_svn_path%/}/ ${_target_dir%/}/ ${_svn_option}"
    local _final_svn_cmd="$(_getSvnFullCmd "$_svn_cmd")"
    
    #_info "Running \"$_svn_cmd\"..."
    # not running in background as it should not take long
    if [ -s /tmp/f_importCode_${g_pid}.out ]; then
        if _isYes "$_is_background"; then
            _eval "${_final_svn_cmd}" "N" 2>&1 | tee -a /tmp/f_importCode_${g_pid}.out &
        else
            _eval "${_final_svn_cmd}" "N" 2>&1 | tee -a /tmp/f_importCode_${g_pid}.out
        fi
    else
        if _isYes "$_is_background"; then
            _eval "${_final_svn_cmd}" "N" &
        else
            _eval "${_final_svn_cmd}" "N"
        fi
    fi
    
    return $?
}

function _getSvnFullCmd() {
    local _svn_cmd="$1"
    local _final_svn_cmd="$_svn_cmd --no-auth-cache --trust-server-cert --non-interactive"
    
    if [ -n "$r_svn_user" ]; then
        _final_svn_cmd="${_final_svn_cmd} --username $r_svn_user"
        
        if [ -n "$r_svn_pass" ]; then
            _final_svn_cmd="${_final_svn_cmd} --password $r_svn_pass"
        fi
    fi
    
    # FIXME: don't want to use echo
    echo "$_final_svn_cmd"
}

function f_importVendors() {
    local __doc__="Import vendors (third-party source code) from SVN"
    local _target_dir="$1"
    
    if [ -z "$_target_dir" ]; then
        _target_dir="${g_apache_data_dir%/}/vendors"
        _info "Using \"${_target_dir}\" as the target directory path."
    fi
    
    if [ "$r_code_import" = "ssh" ] && _isNotEmptyDir "${_target_dir}"; then
        _warn "$FUNCNAME: \"${_target_dir}\" already exists and not empty. Skipping..."
        return 0
    fi
    
    if [ "$r_code_import" = "smb" ] && _isNotEmptyDir "${_target_dir}"; then
        _warn "$FUNCNAME: \"${_target_dir}\" already exists and not empty. Skipping..."
        return 0
    fi
    
    if [ "$r_code_import" = "svn" ] && [[ "${r_code_import_cmd}" =~ /trunk/$ ]]; then
        _warn "$FUNCNAME: Import command looks like importing whole trunk. Skipping Vendors import..."
        return 0
    fi
    
    _mkdir "${_target_dir%/}"
    if [ -z "$r_svn_url_build" ]; then
        r_svn_url_build="$g_svn_url_build"
    fi
    f_svnCheckOut "${r_svn_url_build%/}/site/vendors/" "${_target_dir}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Vendors SVN CO failed."; return 1; fi
    
    if [ ! -n "$r_apache_document_root" ]; then 
        _warn "$FUNCNAME: No apache doc root."
        return 1
    fi
    
    if [ ! -d "$(dirname "$r_apache_document_root")" ]; then 
        _warn "$FUNCNAME: Parent directory of \"$r_apache_document_root\" does not exist."
        return 1
    fi
    
    # create a symlink to doc
    local _sym_target="$(dirname "$r_apache_document_root")/vendors"
    if [ -e "$_sym_target" ]; then
        _warn "$FUNCNAME: Symlink taregt \"${_sym_target}\" already exists."
        return 1
    fi
    
    _eval "ln -s ${_target_dir%/} ${_sym_target}"
    return $?
}

function f_importSqlSchema() {
    local __doc__="Import sql schema file from SVN for production server."
    local _target_dir="$1"
    local _db_entity="${2-$r_db_entity}"
    
    if [ -z "$_target_dir" ]; then
        _target_dir="/data/sql_svn"
        _info "Using \"${_target_dir}\" as the target directory path."
    fi
    
    if [ -z "$_db_entity" ]; then
        _warn "$FUNCNAME: no DB entity given. Skipping..."
        return 1
    fi
    
    _mkdir "${_target_dir%/}"
    if [ -z "$r_svn_url_build" ]; then
        r_svn_url_build="$g_svn_url_build"
    fi
    f_svnCheckOut "${r_svn_url_build%/}/sql/" "${_target_dir}" "--depth empty" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: svn co failed."; return 1; fi
    
    local _svn_cmd="svn up ${_db_entity}_production.schema.sql"
    local _final_svn_cmd="$(_getSvnFullCmd "$_svn_cmd")"
    
    _info "Running \"$_svn_cmd\"..."
    _eval "cd ${_target_dir} && ${_final_svn_cmd}; cd -" "N" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: svn up failed."; return 1; fi
    return 0
}

function f_modBuildConfig() {
    local __doc__="Modifying Build config.ini.php for this new web-site environment (Experimental)."
    
    if ! _isYes "$r_code_modify_config" ; then
        #_info "Not modifying Build config.ini.php."
        return 0
    fi
    
    _info "Modifying modifying Build config.ini.php."
    local _config_path="${r_apache_document_root%/}/xul/core_ui/config.ini.php"
    
    if [ ! -w "$_config_path" ]; then
        _warn "$FUNCNAME: $_config_path does not exit or not writable."
        return 1
    fi
    
    if [ -z "$r_db_entity" ]; then
        _warn "$FUNCNAME: System/DB entity type is empty."
        return 1
    fi
    
    local _entity="default"
    if [ "$r_db_entity" != "$g_default_entity_name" ]; then _entity="$r_db_entity"; fi
    if [ "$r_server_type" = "dev" ]; then _entity="dev-${_entity}"; fi
    
    local _full_website_label="[$r_apache_env_website : ${_entity}]"
    _info "Inserting ${_full_website_label} section..."
    f_insertLine "$_config_path" ";++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" "$_full_website_label"
    f_insertLine "$_config_path" ";++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" "core.database.name                        = ${r_db_name}"
    f_insertLine "$_config_path" ";++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" "core.database.user                        = ${r_db_username}"
    f_insertLine "$_config_path" ";++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" "core.database.password                    = ${r_db_password}"
    f_insertLine "$_config_path" ";++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" ""
    return 0
}

function f_modBuildPerms() {
    local __doc__="Modifying folder/file owner/permission. should be same as running perms.sh"
    
    if [ -z "${r_apache_document_root%/}" ]; then
        _warn "$FUNCNAME: document root (r_apache_document_root) is not set."
        return 1
    fi
    
    if [ ! -x "${r_apache_document_root%/}/xul/cronjobs/perms.sh" ]; then
        _warn "$FUNCNAME: ${r_apache_document_root%/}/xul/cronjobs/perms.sh is not executable."
        return 1
    fi
    
    _info "Creating Admdocs cache directory."
    local _adm_cache_dirname="$(basename "`dirname $r_apache_document_root`")"
    if [ -z "$_adm_cache_dirname" ]; then
        _adm_cache_dirname="production"
    fi
    _mkdir "/data/adm_cache/${_adm_cache_dirname%/}/"
    _eval "touch /data/adm_cache/${_adm_cache_dirname%/}/.admdocs_cache_path"
    _eval "chown -R ${g_automation_user}:${g_apache_user} /data/adm_cache"
    
    _info "Modifying folders/files owner/permissions..."
    _eval "${r_apache_document_root%/}/xul/cronjobs/perms.sh"
    return $?
}

function f_importDocs() {
    local __doc__="Importing Admdocs with ${r_docs_import}."
    local _tmp_file_list="/tmp/rsync_file_list_${g_pid}.out"
    local _final_cmd="$r_docs_import_cmd"
    
    if [ -z "$r_docs_import_cmd" ]; then
        _warn "$FUNCNAME: No importing command. Skipping..."
        return
    fi
    
    if [ -z "$r_docs_import_target" ]; then
        _warn "$FUNCNAME: No target dir path to import Admdoc. Skipping..."
        return
    fi
    
    _info "Importing Admdocs."
    
    _mkdir "$r_docs_import_target"
    #_eval "ln -s $r_docs_import_target ..."
    
    if [ "$r_docs_import" = "sync" ]; then
        f_importDocsMountRO ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not prepare Read-Only mount point to sync Admdocs."; return 1; fi
        
        if ! _isYes "$r_docs_import_full"; then
            # FIXME: should check if _final_cmd is rsync command.
            _final_cmd="${_final_cmd} --files-from=${_tmp_file_list} && rm -f $_tmp_file_list"
            _createImportFileList "${_tmp_file_list}" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Creating sync file list ${_tmp_file_list} from *local DB* failed."; return 1; fi
        fi
        
        _eval "$_final_cmd" 2>&1 | tee -a /tmp/f_importDocs_${g_pid}.out &
    elif [ "$r_docs_import" = "smb" ]; then
        if [ -n "$r_docs_import_cred_path" ]; then
            f_setConfig "$r_docs_import_cred_path" "username" "$r_docs_import_user"
            f_setConfig "$r_docs_import_cred_path" "password" "$r_docs_import_pass"
            f_setConfig "$r_docs_import_cred_path" "domain" "$r_docs_import_domain"
            _eval "chmod 1600 $r_docs_import_cred_path"
        fi
        _eval "$_final_cmd"
        f_insertLine "$g_startup_script_path" "exit 0" "$_final_cmd"
    elif [ "$r_docs_import" = "ssh" ]; then
        f_copyPubKey "${r_docs_import_user}@${r_docs_import_server}" "$r_docs_import_pass" "$r_docs_import_cred_path"
        _eval "$_final_cmd"
        f_insertLine "$g_startup_script_path" "exit 0" "$_final_cmd"
    elif [ "$r_code_import" = "skip" ] || [ -z "$r_code_import" ]; then
        _warn "$FUNCNAME: As per import type '$r_code_import', Skipping..."
        return 0
    else
        _warn "$FUNCNAME: Unknown import type '$r_code_import'"
        return 1
    fi
    
    return $?
}

function f_importDocsMountRO() {
    local __doc__="Mount specified location as Read-Only"
    
    if [ -z "$r_docs_import_user" ]; then _warn "$FUNCNAME requires r_docs_import_user."; return 1; fi
    if [ -z "$r_docs_import_server" ]; then _warn "$FUNCNAME requires r_docs_import_server."; return 1; fi
    if [ -z "$r_docs_import_path" ]; then _warn "$FUNCNAME requires r_docs_import_path."; return 1; fi
    if [ -z "$r_docs_import_pass" ]; then _warn "$FUNCNAME requires r_docs_import_pass."; return 1; fi
    
    local _ro_ssh_cmd="sshfs -o ${g_sshfs_options},ro ${r_docs_import_user}@${r_docs_import_server}:${r_docs_import_path} ${g_tmp_mnt_dir%/}"
    _mkdir "$g_tmp_mnt_dir"
    _expect "$_ro_ssh_cmd" "r_docs_import_pass"
    return $?
}

function f_mountSshfs() {
    local __doc__="Mount specified location with sshfs"
    local _local_path="$1"
    local _remote_server="$2"
    local _remote_path="$3"
    local _remote_username="${4-$g_automation_user}"
    local _remote_password="$5"
    local _save_to_rc_local="${6-Y}"
    local _is_readonly="${7-Y}"
    if [ -z "$_remote_username" ]; then
        _remote_username="$g_automation_user"
        #_remote_username="$SUDO_USER"
    fi
    local _id_key_path="${8-/home/${_remote_username}/.ssh/id_rsa}"
    
    if [ ! -e "$_local_path" ]; then
        _info "$FUNCNAME: creating $_local_path"
        _mkdir "$_local_path"
    fi
    
    if _isNotEmptyDir "$_local_path"; then
        _warn "$FUNCNAME: $_local_path is not empty directory."
        return 1
    fi
    
    local _options="${g_sshfs_options}"
    if _isYes "$_is_readonly"; then
        _options="${_options},ro"
    fi
    if _isYes "$_save_to_rc_local" || [ -n "$_id_key_path" ]; then
        _options="${_options},IdentityFile=${_id_key_path}"
    fi
    
    local _ssh_cmd="sshfs -o ${_options} ${_remote_username}@${_remote_server}:${_remote_path%/} ${_local_path%/}"
    
    if _isYes "$_save_to_rc_local" || [ -n "$_id_key_path" ]; then
        if ! $g_is_script_running && [ -z "$_remote_password" ] && [ "$_remote_username" != "$g_automation_user" ]; then
            echo "Please provide a password to connect to ${_remote_server} as ${_remote_username}"
            f_ask "Password" "" "_remote_password" "Y"
        fi
        
        if [ "$_remote_username" = "$g_automation_user" ]; then
            f_copyAutomationUserRsaKey
            # automation user should not use password, so commenting.
            #_remote_password="$(f_getBuildConfigValueFromSvn "core.automation.password")"
        else
            f_copyPubKey "${_remote_username}@${_remote_server}" "$_remote_password" "$_id_key_path" "Y"
        fi
        
        if _isYes "$_save_to_rc_local"; then
            _info "$FUNCNAME: updating $g_startup_script_path..."
            f_insertLine "$g_startup_script_path" "exit 0" "$_ssh_cmd"
        fi
        
        _eval "$_ssh_cmd"
    else
        _expect "$_ssh_cmd" "$_remote_password"
    fi
    return $?
}

function _createImportFileList() {
    local _output_path="$1"
    local _prefix="$(_escape_quote "$2")"
    local _db_name="${3-$r_db_name}"
    
    if [ -z "$_run_as" ]; then _run_as="$g_db_superuser"; fi
    
    # FIXME: not sure if excluding media_type is good
    local _sql="SELECT '${_prefix}'||CASE WHEN r.sub_dir IS NULL OR r.sub_dir = '' THEN substring(md5(r.id::text) from 1 for 2)||'/' ELSE r.sub_dir END||CASE WHEN r.file_name IS NULL OR r.file_name = '' THEN r.id::text||CASE WHEN f.type IS NULL OR f.type = '' THEN '' ELSE '.'||f.type END ELSE r.file_name END as file_path FROM tbladoc_file f join (select distinct on (file_id) file_id, id, sub_dir, file_name from tbladoc_file_revision where del_flag is false order by file_id, revision desc, id desc) r on r.file_id = f.id join tbladoc_document d on f.doc_id = d.id and d.del_flag is false where f.del_flag is false and d.media_type <> 'X'"
    
    _eval "psql -p ${g_db_port} -d ${_db_name} -t -A -F\",\" -c \"${_sql}\" > ${_output_path}" "" "$g_db_superuser"
    return $?
}

function f_importDb() {
    local __doc__="Importing database from server $r_db_import_server or $g_db_server_ip with ${r_db_import}.
'_db_env_name' is used in f_do_not_run_create_test_environment()."
    local _db_name="${1-$r_db_name}"
    local _db_entity="${2-$r_db_entity}"
    local _db_env_name="${3-$r_db_env_name}"
    local _working_dir="${4-/tmp}"
    
    # in case r_db_name is used in other function.
    if [ -n "$_db_name" ]; then
        r_db_name="$_db_name"
    fi
    
    # in case r_db_entity is used in other function.
    if [ -n "$_db_entity" ]; then
        if [ "$_db_entity" = "main" ]; then
            _db_entity="$g_default_entity_name"
        fi
        r_db_entity="$_db_entity"
    fi
    
    # in case r_db_entity is used in other function.
    if [ -n "$_db_env_name" ]; then
        r_db_env_name="$_db_env_name"
    fi
    
    if [ "$r_db_import" = "scp" ]; then
        f_importDbWithScp "$_db_name" "$_db_entity" "$_db_env_name" "$_working_dir"
    elif [ "$r_db_import" = "pgd" ]; then
        f_copyDb ; if [ $? -ne 0 ]; then _error "$FUNCNAME: f_copyDb failed."; return 1; fi
    elif [ "$r_db_import" = "skip" ] || [ -z "$r_db_import" ]; then
        _warn "$FUNCNAME: As per import type '$r_db_import', Skipping..."
        return 0
    else
        _critical "$FUNCNAME: Unknown import type '$r_db_import'"
    fi
    
    if [ "$r_server_type" = "dev" ]; then
        f_setupDbForDev "$r_db_name" "$r_db_username" "$r_db_password" "$r_db_env_name" "$r_db_ad_login"
        _warn "You might want to run \"f_changeBuildUserNoAd\" to stop using AD/LDAP and to change password."
    fi
    
    _info "$FUNCNAME completed."
}

function f_importDbWithScp() {
    local __doc__="Importing database from server $r_db_import_server or $g_db_server_ip with ${r_db_import}.
'_db_env_name' is used in f_do_not_run_create_test_environment()."
    local _db_name="${1-$r_db_name}"
    local _db_entity="${2-$r_db_entity}"
    local _db_env_name="${3-$r_db_env_name}"
    local _is_ascii="${4}"
    local _working_dir="${5-/tmp}"
    
    if [ -z "$r_db_import_server" ]; then
        r_db_import_server="$g_db_server_ip"
    fi
    
    if [ -n "$_db_name" ]; then
        # in case r_db_name is used in other function.
        r_db_name="$_db_name"
    else
        if [ -n "$r_db_name" ]; then
            _db_name="$r_db_name"
        else
            _warn "$FUNCNAME: Database name is required."
            return 1
        fi
    fi
    _info "Using \"$_db_name\" as database name."
    
    if [ -n "$_db_entity" ]; then
        if [ "$_db_entity" = "main" ]; then
            _db_entity="$g_default_entity_name"
        fi
        r_db_entity="$_db_entity"
        
        r_db_import_path="${g_db_backup_path}_${r_db_entity}/${r_db_entity}_build_production.7z"
    fi
    _info "Using \"$r_db_import_path\""
    
    if [ -n "$_db_env_name" ]; then
        r_db_env_name="$_db_env_name"
    fi
    
    local _extension="${r_db_import_path##*.}"

    local _file_basename="`basename $r_db_import_path .${_extension}`"
    local _username_hostname="${r_db_import_user}@${r_db_import_server}"
    if [ -z "$r_db_import_user" ]; then
        _username_hostname="${g_automation_user}@${r_db_import_server}"
    fi
    local _reuse=""
    
    if [ -s "${_working_dir%/}/${_file_basename}.sql" ]; then
        if _isYes "$r_db_import_reuse" ; then _reuse=".sql"; fi
    elif [ -s "${_working_dir%/}/${_file_basename}.${_extension}" ]; then
        if _isYes "$r_db_import_reuse" ; then _reuse=".${_extension}"; fi
    fi
    
    if [ -z "$_reuse" ]; then
        f_scp "${_username_hostname}:${r_db_import_path} ${_working_dir}" "${r_db_import_pass}"
        _checkLastRC "$FUNCNAME: SCP failed."
    fi
    
    if [ "$_reuse" != ".sql" ]; then
        if [ "$_extension" = "7z" ]; then
            _info "Extracting ./${_file_basename}.${_extension}..."
            _eval "cd ${_working_dir} && 7za e -y ./${_file_basename}.${_extension}; cd - >/dev/null" || _critical "$FUNCNAME: 7zip extract failed."
        elif [ "$_extension" = "gz" ]; then
            _info "Extracting ./${_file_basename}.${_extension}..."
            if [ -e "./${_file_basename}.sql" ]; then
                _eval "rm -f ./${_file_basename}.sql"
            fi
            _eval "cd ${_working_dir} && gunzip -c ./${_file_basename}.${_extension} > ./${_file_basename}.sql; cd - >/dev/null" || _critical "$FUNCNAME: gunzip extract failed."
        fi
    fi
    
    if _isYes "$_is_ascii" ; then
        if [ "$_reuse" != ".sql" ]; then
            _info "Converting ${_working_dir%/}/${_file_basename}.sql to UTF-8 ..."
            _eval "iconv -f ISO-8859-1 -t UTF-8 ${_working_dir%/}/${_file_basename}.sql > ${_working_dir%/}/${_file_basename}_utf8.sql && mv -f ${_working_dir%/}/${_file_basename}_utf8.sql ${_working_dir%/}/${_file_basename}.sql" || _critical "$FUNCNAME: Converting SQL dump from ASCII to UTF8 (default) failed."
        fi
    fi
    
    if [ ! -s "${_working_dir%/}/${_file_basename}.sql" ]; then
        _critical "$FUNCNAME: Could not generate ${_working_dir%/}/${_file_basename}.sql"
    else
        # FIXME: not secure (but anyway it seems Ubuntu default is 755 for all home dirs...)
        _eval "chmod a+r ${_working_dir%/}/${_file_basename}.sql"
    fi
    
    # run 'psql' command to import .sql file
    f_importDbFile "${_working_dir%/}/${_file_basename}.sql" "${_db_name}" "${r_db_username}" "${r_db_password}" "$r_db_encoding" "$r_db_drop"
    return $?
}

function _createDb() {
    local __doc__="Create a DB with encoding SQL_ASCII or UTF8"
    local _db_name="${1-$r_db_name}"
    local _db_username="${2-$r_db_username}"
    local _db_password="${3-$r_db_password}"
    local _db_encoding="${4}"
    local _db_drop="${5}"
    local _createdb_option="-E SQL_ASCII -T template0 --lc-collate=C --lc-ctype=C"
    
    if [ "$_db_encoding" != "SQL_ASCII" ]; then
        _createdb_option=""    # Use default option (which is none)
    fi
    
    if _isDbExist "$_db_name" ; then
        if _isYes "$_db_drop" ; then 
            _info "Dropping existing database '${_db_name}'..."
            _eval "dropdb ${_db_name}" "" "${g_db_superuser}" || _critical "$FUNCNAME: Dropdb failed."
        else
            _warn "$FUNCNAME: Database $_db_name already exists. Please run 'dropdb' first."
            return 1
        fi
    fi
    
    _eval "PGPASSWORD=\"${_db_password}\" createdb -U ${_db_username} -h 127.0.0.1 -p ${g_db_port} ${_db_name} ${_createdb_option}" "N" || _critical "$FUNCNAME: Createdb with '${_db_encoding}' encoding failed."
    local _rc=$?
    _info "Created database '${_db_name}' with '${_db_encoding}' encoding"
    return $_rc
}

function _isDbExist() {
    local _db_name="$1"
    su ${g_db_superuser} -c "psql -p ${g_db_port} -l" 2>/dev/null | grep -wi "${_db_name}" &>/dev/null
    return $?
}

function f_importDbFile() {
    # NOTE: can't use _critical in this function
    local __doc__="Import the given SQL (or 7z, gz) file."
    local _sql_file_path="$1"
    local _db_name="$2"
    local _db_username="${3-$r_db_username}"
    local _db_password="${4-$r_db_password}"
    local _db_encoding="${5-$r_db_encoding}"
    local _db_drop="${6-$r_db_drop}"
    local _working_dir="${7-/tmp}"
    
    if [ ! -s "$_sql_file_path" ] ; then
        _warn "$FUNCNAME: $_sql_file_path does not exist."
        return 1
    fi
    
    if [ -z "$_db_name" ]; then
        f_ask "New DB name" "$tmp_new_db_name" "tmp_new_db_name" "" "Y"
        _db_name="$tmp_new_db_name"
    fi
    if [ -z "$_db_username" ]; then
        if [ -z "$tmp_db_username" ]; then tmp_db_username="$g_db_username"; fi
        f_ask "Local database user name" "$tmp_db_username" "tmp_db_username" "" "Y"
        _db_username="$tmp_db_username"
    fi
    if [ -z "$_db_password" ]; then
        f_ask "Local database password" "$tmp_db_password" "tmp_db_password" "Y"
        _db_password="$tmp_db_password"
    fi
    
    # Would need at least 10GB free space
    if ! f_isEnoughDisk "$g_db_home" "10" ; then
        _warn "$FUNCNAME: $g_db_home space is less than 10GB. Aborting..."
        return 1
    fi
    
    # Would need at least 2GB free space
    if ! f_isEnoughDisk "$_working_dir" "2" ; then
        _warn "$FUNCNAME: $_working_dir space is less than 2GB. Aborting..."
        return 1
    fi
    
    local _extension="${_sql_file_path##*.}"
    local _file_basename="`basename $_sql_file_path .${_extension}`"
    local _target_file_path="${_sql_file_path}"
    
    # run 'createdb' command
    _createDb "${_db_name}" "${_db_username}" "${_db_password}" "$_db_encoding" "$_db_drop" || _critical "$FUNCNAME: Creating database $_db_name failed."
    
    if [ "$_extension" = "7z" ]; then
        _target_file_path="`ls -t ${_working_dir%/}/${_file_basename}*.sql | head -n1`"
        if [ -e "$_target_file_path" ] ; then
            _warn "$FUNCNAME: Please delete temp file(s) ${_working_dir%/}/${_file_basename}*.sql first."
            return 1
        fi
        
        _info "Extracting ${_file_basename}.${_extension}..."
        _eval "7za e -o${_working_dir} -y ${_sql_file_path}" || _critical "$FUNCNAME: 7zip extract failed."
        _target_file_path="`ls -t ${_working_dir%/}/${_file_basename}*.sql | head -n1`"
        if [ -z "$_target_file_path" ]; then
            _warn "$FUNCNAME: Could not determine the extracted file."
            return 1
        fi
        _warn "$FUNCNAME: Assuming $_target_file_path is correct file."
    elif [ "$_extension" = "gz" ]; then
        _target_file_path="${_working_dir%/}/${_file_basename}.sql"
        if [ -e "$_target_file_path" ] ; then
            _warn "$FUNCNAME: Please delete temp file $_target_file_path first."
            return 1
        fi
        
        _info "Extracting ${_file_basename}.${_extension}..."
        _eval "gunzip -c ${_sql_file_path} > ${_target_file_path}" || _critical "$FUNCNAME: gunzip extract failed."
    fi
    
    if [ ! -s "$_target_file_path" ] ; then
        _warn "$FUNCNAME: Could not create temp file $_target_file_path"
        return 1
    fi
    
    local _cmd="psql -h 127.0.0.1 -p ${g_db_port} -U${_db_username} ${_db_name} -f ${_target_file_path}"
    _info "$_cmd"
    _eval "PGPASSWORD=\"${_db_password}\" $_cmd" "N" 1>/tmp/${FUNCNAME}_${g_pid}.tmp &
    _bgProgress "DB Import" "/tmp/${FUNCNAME}_${g_pid}.tmp" "$g_db_expect_line"; wait
    
    if [ "$r_server_type" = "dev" ]; then
        _info "You should run \"f_setupDbForDev\" (and maybe \"f_changeBuildUserNoAd\")"
    fi
    
    grep -P '(WARN|ERROR)' /tmp/${FUNCNAME}_${g_pid}.tmp || (rm -f /tmp/${FUNCNAME}_${g_pid}.tmp; return 0)
    return 1
}

function f_setupDbForDev() {
    local __doc__="Modify local DB for Develop environment."
    local _db_name="${1-$r_db_name}"
    local _db_username="${2-$r_db_username}"
    local _db_password="${3-$r_db_password}"
    local _db_env_name="${4-$r_db_env_name}"
    local _db_ad_login="${5-$r_db_ad_login}"
    #local _db_ad_password="${6-$r_db_ad_password}"
    
    if [ "$r_server_type" != "dev" ]; then
        _warn "$FUNCNAME can run only on DEV environtment."
        return 1
    fi
    
    if [ -z "$_db_name" ]; then
        _warn "$FUNCNAME: DEV system requires 'r_db_name'"
        return 1
    fi
    
    if [ -z "$_db_username" ]; then
        _warn "$FUNCNAME: DEV system requires 'r_db_username'"
        return 1
    fi
    
    local _tmp_db_env_name="$(_escape_quote "$_db_env_name")"
    if [ -z "$_tmp_db_env_name" ]; then
        if [ -n "$r_apache_server_alias" ]; then
            _tmp_db_env_name="$(_escape_quote "$r_apache_server_alias")"
            _info "Using $_tmp_db_env_name as db_env_name"
        else 
            _warn "$FUNCNAME: DEV system requires 'r_db_env_name'"
            return 1
        fi
    fi
    
    local _tmp_db_ad_login="$(_escape_quote "$_db_ad_login")"
    if [ -z "$_tmp_db_ad_login" ]; then
        if _isEmail "$r_admin_mail" && [[ ! "$r_admin_mail" =~ "build" ]]; then
            _tmp_db_ad_login="$r_admin_mail"
            _info "Using $_tmp_db_ad_login as db_ad_login"
        else
            _warn "$FUNCNAME: DEV system requires 'r_db_ad_login'"
            return 1
        fi
    else
        if ! _isEmail "$_tmp_db_ad_login"; then
            _tmp_db_ad_login="${_tmp_db_ad_login}@testdomain.com"
        fi
    fi
    
    # If you don't want to run 'f_do_not_run_create_test_environment', just run the following command:
    # su postgres -c "psql -p ${g_db_port} ${r_db_name} -c \"update tbllib_property set prop_value='${r_db_env_name}', date_modified=now() where prop_name='testEnvironment'\""
    _cmd="psql -h 127.0.0.1 -p ${g_db_port} -U ${_db_username} ${_db_name} -c \"select * from f_do_not_run_create_test_environment('${_tmp_db_ad_login}', '${_tmp_db_env_name}')\""
    _info "$_cmd"
    _eval "PGPASSWORD=\"${_db_password}\" $_cmd" "N"
    if [ $? -ne 0 ]; then
        _warn "$FUNCNAME: Running f_do_not_run_create_test_environment failed."
        return 1
    fi
    
    return 0
}

function f_changeBuildUserNoAd() {
    local __doc__="Update tblper_persondetails to set 'auth_ads=false'.
If _uid is given, updates that user only, otherwise *ALL* users.
If _pass is given, updates password."
    local _db_name="${1-$r_db_name}"
    local _uid="$(_escape_quote "$2")"
    local _pass="$(_escape_quote "${3-$g_default_password}")"
    #local _db_username="${r_db_username-$g_db_superuser}"
    #local _db_password="${r_db_password}"
    
    if [ "$r_server_type" != "dev" ]; then
        _warn "$FUNCNAME can run only on DEV environtment."
        return 1
    fi
    
    if [ -z "$_db_name" ]; then
        _warn "$FUNCNAME requires database name as 1st argument."
        return 1
    fi
    
    local _where_uid=""
    if [ -n "$_uid" ]; then
        _where_uid="where uid ilike '${_uid}'"
        _info "$FUNCNAME: updating uid ${_uid} only"
    fi
    
    local _passwd=""
    if [ -n "$_pass" ]; then
        _passwd=", passwd=md5('${_pass}')"
        _info "$FUNCNAME: updating password as well."
    fi
    
    _eval "psql -p ${g_db_port} ${_db_name} -c \"alter table tblper_persondetails DISABLE TRIGGER all;update tblper_persondetails set auth_ads=false ${_passwd} ${_where_uid};alter table tblper_persondetails ENABLE TRIGGER all;\"" "" "$g_db_superuser" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Updating Build user ${_uid} password on ${_db_name} failed."; return 1; fi
    return $?
}

function f_commitEtc() {
    local __doc__="Commit /etc/* to SVN and schedule it daily"
    local _svn_reg_name="${1-$g_hostname}"
    local _acceptable_size="${2-20000}"
    local _etc_backup_dir="/usr/local/etc_svn_backup"
    local _conf_file="$g_build_crontab"
    local _random_min=$(( $RANDOM % 6 * 10 + $RANDOM % 10 ))
    local _how_often="${_random_min} 5 * * *"
    #local _conf_file="/etc/cron.daily/build-etc-commit"
    
    _svn_reg_name="$(echo "$_svn_reg_name" | awk '{print tolower($0)}')"
    
    _mkdir "${_etc_backup_dir%/}"
    
    if [ ! -e "${_etc_backup_dir%/}/.svn" ]; then
        local _svn_cp_cmd="svn cp \"${g_svn_url%/}/server-configurations/__skel/\" \"${g_svn_url%/}/server-configurations/${_svn_reg_name}/\" -m \"Creating the server configuration dir\""
        local _full_svn_cp_cmd="$(_getSvnFullCmd "$_svn_cp_cmd")"
        _info "Running SVN CP \"$_svn_cp_cmd\" command."
        _eval "$_full_svn_cp_cmd" "N"
    fi
    
    local _etc_size="$(du -s /etc | awk '{print $1}')"
    if [ $_etc_size -gt $_acceptable_size ]; then
        _warn "$FUNCNAME: /etc is bigger than $_acceptable_size byte. Please check /etc/."
        return 1
    fi
    
    f_svnCheckOut "${g_svn_url%/}/server-configurations/${_svn_reg_name}/" "${_etc_backup_dir%/}/"
    
    
    if [ -n "$r_apache_document_root" ]; then
        local _tmp_path="$(dirname "${r_apache_document_root}")"
    else
        local _tmp_path="/data/sites/production"
    fi
    
    if [ -s "${_tmp_path%/}/utils/backup-scripts/backup_etc_to_svn.sh" ]; then
        local _commit_script="${_tmp_path%/}/utils/backup-scripts/backup_etc_to_svn.sh"
    else
        local _commit_script="`ls -t /data/sites/*/utils/backup-scripts/backup_etc_to_svn.sh | head -n1`"
    fi
    
    if [ ! -s "$_commit_script" ]; then
        _critical "$FUNCNAME: SVN backup script does not exist. "
    fi
    
    if [ -s "$_conf_file" ]; then
        f_backup "$_conf_file"
    else
        _eval "touch $_conf_file"
    fi
    
    f_appendLine "$_conf_file" "${_how_often} root /bin/sh $_commit_script" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not create/edit \"$_conf_file\""; return 1; fi
    return $?
}

function f_scheduleSvnUpdate() {
    local __doc__="Schedule daily SVN Update against given path with 'svn_tasks.php'"
    local _root_dir="${1-$r_apache_document_root}"
    local _website="${2-$r_apache_env_website}"
    local _update_type="${3-$r_svn_update_type}"
    local _action="${4-updateIfMatch}"
    local _extra_cmd="$5"
    
    local _conf_file="$g_build_crontab"
    local _script_dir="${_root_dir%/}/xul/cronjobs"
    local _script_name="svn_tasks.php"
    local _random_min=$(( $RANDOM % 6 * 10 + $RANDOM % 10 ))
    local _how_often="*/10 * * * *"
    
    if [ -z "$_root_dir" ]; then
        _warn "$FUNCNAME: No SVN ROOT directory is given. Skipping..."
        return 0
    fi
    
    if [ ! -s "${_script_dir%/}/${_script_name}" ]; then
        _critical "$FUNCNAME: Could not find ${_script_dir%/}/${_script_name}."
    fi
    
    if [ -z "$_website" ]; then
        _critical "$FUNCNAME requires website (r_apache_env_website)"
    fi
    
    # FIXME: at this moment, same schedule for readonly/training
    if [ "$_update_type" = "readonly" ] ; then
        _action="updateIfNotMatchNone"
        _how_often="${_random_min} 08-16 * * 1-5"
    elif [ "$_update_type" = "training" ] ; then
        _action="updateIfNotMatchNone"
        _how_often="${_random_min} 08-16 * * 1-5"
    fi
    
    local _schedule_line="php ${_script_dir%/}/${_script_name} --action=${_action} --website=${_website} ${_extra_cmd}"
    
    grep "$_schedule_line" $_conf_file &>/dev/null ; if [ $? -eq 0 ]; then _warn "$FUNCNAME: looks like already scheduled. Skipping..."; return 0; fi
    
    if [ -s "$_conf_file" ]; then
        f_backup "$_conf_file"
    else
        _eval "touch $_conf_file"
    fi
    
    f_appendLine "$_conf_file" "${_how_often} root $_schedule_line" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not create/edit \"$_conf_file\""; return 1; fi
    return $?
}

function f_scheduleMiscTasks() {
    local __doc__="Schedule daily Misc Task job against given path with 'misk_tasks.php'
FIXME: Frequency delimiter is space only."
    local _root_dir="${1-$r_apache_document_root}"
    local _website="${2-$r_apache_env_website}"
    local _freqency="${3}"
    local _action="${4-dailyMaintenance}"
    local _extra_cmd="$5"
    
    local _conf_file="$g_build_crontab"
    local _script_dir="${_root_dir%/}/xul/cronjobs"
    local _script_name="misc_tasks.php"
    local _random_min=$(( $RANDOM % 6 * 10 + $RANDOM % 10 ))
    
    if [ -z "$_root_dir" ]; then
        _warn "$FUNCNAME: No SVN ROOT directory is given. Skipping..."
        return 0
    fi
    
    if [ ! -s "${_script_dir%/}/${_script_name}" ]; then
        _critical "$FUNCNAME: Could not find ${_script_dir%/}/${_script_name}."
    fi
    
    if [ -z "$_website" ]; then
        _critical "$FUNCNAME requires website (r_apache_env_website)"
    fi
    
    if [ -z "$_freqency" ]; then
        _how_often="${_random_min} * * * *"
    elif [[ "$_freqency" =~ ^[0-9][0-9]?$ ]] ; then
        # If only one number, assume it as minute (hourly job)
        # FIXME: should check between 0 and 24
        _how_often="$_freqency * * * *"
    else
        # If only four numbers, assume using random minute
        echo "$_freqency" | grep -P '^[0-9\*]{1,2} [0-9\*]{1,2} [0-9\*]{1,2} [0-7\*]$' &>/dev/null
        if [ $? -eq 0 ]; then
            _how_often="${_random_min} $_freqency"
        else
            _how_often="$_freqency"
        fi
    fi
    
    # validate _how_often
    echo "$_how_often" | grep -P '^[0-9\*]{1,2} [0-9\*]{1,2} [0-9\*]{1,2} [0-9\*]{1,2} [0-7\*]$' &>/dev/null
    if [ $? -ne 0 ]; then
        _error "$FUNCNAME: $_how_often is not a valid cron schedule"
        return 1
    fi
    
    # looks like no longer using uid
    #local _schedule_line="cd ${_script_dir} && php ${_script_name} --website=${_website} --action=${_action} --uid=${_website}-${_action} ${_extra_cmd}"
    local _schedule_line="php ${_script_dir%/}/${_script_name} --website=${_website} --action=${_action} --uid=${_website}-${_action} ${_extra_cmd}"
    
    grep "$_schedule_line" $_conf_file &>/dev/null ; if [ $? -eq 0 ]; then _warn "$FUNCNAME: looks like already scheduled. Skipping..."; return 0; fi
    
    if [ -s "$_conf_file" ]; then
        f_backup "$_conf_file"
    else
        _eval "touch $_conf_file"
    fi
    
    f_appendLine "$_conf_file" "${_how_often} root $_schedule_line" ; if [ $? -ne 0 ]; then _error "$FUNCNAME: Could not create/edit \"$_conf_file\""; return 1; fi
    return $?
}

function f_addBuildSite() {
    local __doc__="Add a new Build site (Apache Virtual Host), import code, and import DB (except Admdocs)"
    local _no_confirmation="$1"
    
    # FXIME: can't use local variable, so potentially name space conflict
    if ! _isYes "$_no_confirmation"; then
        _info "Currently available sites (including enabled sites)"
        f_listApacheVirtualHost
        echo ""
        
        f_ask "Server Name for Apache Virtual Host" "$r_apache_server_name" "tmp_apache_server_name" "N" "Y"
        f_ask "Server Alias for Apache Virtual Host" "$tmp_apache_server_name" "tmp_apache_server_alias" "N" "Y"
        local _import_target="${g_apache_data_dir%/}/${tmp_apache_server_name}"
        f_ask "Document Root for Apache Virtual Host" "${_import_target%/}/${g_apache_webroot_dirname}" "tmp_apache_document_root" "N" "Y"
        f_ask "Build WEBSITE environment variable" "$r_apache_env_website" "tmp_apache_env_website" "N" "Y"
        f_ask "Virtual Host file name" "${r_apache_server_name}" "tmp_apache_file_name" "N" "Y"
        
        f_ask "How to import Build source code {svn|smb|ssh|skip}" "$r_code_import" "tmp_code_import" "N" "Y"
        r_code_import="$tmp_code_import"
        if [ "$tmp_code_import" != "skip" ]; then
            if [ "$tmp_code_import" = "svn" ]; then
                if [ -z "$r_svn_url_build" ]; then
                    r_svn_url_build="$g_svn_url_build"
                fi
                f_ask "SVN CheckOut URL" "${r_svn_url_build%/}/site" "tmp_code_import_path" "N" "Y"
            else
                # smb or ssh at this moment
                f_interviewImportCommon "code" "$tmp_code_import"
                f_ask "Remote server path for importing *from*" "" "tmp_code_import_path" "N" "Y"
            fi
            f_ask "Import target path" "$_import_target" "tmp_code_import_target" "N" "Y"
        fi
        
        f_ask "Would you like copying DB?" "Y" "tmp_db_copy"
        if _isYes "$tmp_db_copy"; then
            f_ask "DB entity type" "$r_db_entity" "tmp_db_entity"
            r_db_entity="$tmp_db_entity"
            f_ask "New DB Name" "" "tmp_db_name"
            r_db_name="$tmp_db_name"
            if _isDbExist "$tmp_db_name" ; then
                f_ask "Run 'dropdb' before creating if exists?" "Y" "tmp_db_drop"
                r_db_drop="$tmp_db_drop"
            fi
            f_ask "Remote server IP/Host" "$r_db_import_server" "tmp_db_import_server"
            r_db_import_server="$tmp_db_import_server"
            f_ask "Remote database name" "$tmp_db_name" "tmp_db_name_remote"
            r_db_name_remote="$tmp_db_name_remote"
            f_ask "Remote database user name" "$r_db_username" "tmp_db_username_remote"
            r_db_username_remote="$tmp_db_username_remote"
            f_ask "Remote database password" "" "tmp_db_password_remote" "Y"
            r_db_password_remote="$tmp_db_password_remote"
            if [ "$r_server_type" = "dev" ]; then
                f_ask "Would you like to exclude some huge tables?" "Y"
                if _isYes; then
                    f_ask "Exclude table list" "${g_db_big_tables}" "tmp_db_exclude_tables"
                fi
            fi
            r_db_exclude_tables="$tmp_db_exclude_tables"
            f_ask "Would you like to save a dumped SQL?" "N" "tmp_db_save_sql"
            r_db_save_sql="$tmp_db_save_sql"
        fi
        
        r_apache_server_name="$tmp_apache_server_name"
        r_apache_server_alias="$tmp_apache_server_alias"
        r_apache_document_root="$tmp_apache_document_root"
        r_apache_env_website="$tmp_apache_env_website"
        r_apache_file_name="$tmp_apache_file_name"
        r_code_import_path="$tmp_code_import_path"
        r_code_import_target="$tmp_code_import_target"
        r_code_import_cmd="" # if empty, it sould be regenerated with new values
        
        f_ask "Would you like to start?" "Y"
        if ! _isYes; then
            echo
            _info "Use 'list resp' to see your *temporary* modified response."
            _exit
        fi
    fi
    
    local _apache_host_rc=0
    local _import_code_rc=0
    local _import_db_rc=0
    local _return_code=0
    
    f_importCode; _import_code_rc=$?
    f_addApacheVirtualHost; _apache_host_rc=$?
    
    if _isYes "$tmp_db_copy"; then
        f_copyDb; _import_db_rc=$?
    fi
    
    if [ $_apache_host_rc -ne 0 ]; then
        _warn "$FUNCNAME: f_addApacheVirtualHost failed."
        _return_code=1
    fi
    if [ $_import_code_rc -ne 0 ]; then
        _warn "$FUNCNAME: f_importCode failed."
        _return_code=1
    fi
    if [ $_import_db_rc -ne 0 ]; then
        _warn "$FUNCNAME: importing/copying db failed."
        _return_code=1
    fi
    
    if [ $_return_code -eq 0 ]; then
        _eval "service apache2 reload"
    fi
    return $_return_code
}

function _obfuscate() {
    local _str="$1"
    local _add_prefix="${2-Y}"
    local _key="$(f_getFromSvn "$g_build_config_svn_path" "-" | grep -P "^core.encryption.key\s*=" -m 1 | awk '{print $3}')"
    local _key_hex="$(echo -n "$_key" | xxd -p -c 256)"
    local _prefix=""
    
    _info "This function is experimental (TODO)"
    local _result="$(echo -n "${_str}" | openssl enc -e -aes-256-ecb -nosalt -base64 -K ${_key_hex})"
    
    if _isYes "$_add_prefix"; then
        # assuming we won't change prefix
        #_prefix="$(f_getFromSvn "$g_build_config_svn_path" "-" | grep -P "^core.encryption.prefix\s*=" -m 1 | awk '{print $3}')"
        _prefix="$g_obfuscate_prefix"
    fi
    
    echo "${_prefix}${_result}"
    return 0
}

function _deobfuscate() {
    local _str="$1"
    local _is_prefixed="${2-Y}"
    local _key="$(f_getFromSvn "$g_build_config_svn_path" "-" | grep -P "^core.encryption.key\s*=" -m 1 | awk '{print $3}')"
    local _key_hex="$(echo -n "$_key" | xxd -p -c 256)"
    local _prefix="$g_obfuscate_prefix"
    
    _info "This function is experimental (TODO)"
    if _isYes "$_is_prefixed"; then
        # assuming we won't change prefix
        #_prefix="$(f_getFromSvn "$g_build_config_svn_path" "-" | grep -P "^core.encryption.prefix\s*=" -m 1 | awk '{print $3}')"
        local _prefix_escaped="$(_escape "$_prefix")"
        
        if [[ "$_str" =~ ^${_prefix_escaped} ]]; then
            _str="${_str/$_prefix/}"
        fi
    fi
    
    local _result="$(echo "${_str}" | openssl enc -d -aes-256-ecb -nosalt -nopad -a -K ${_key_hex})"
    
    echo "${_prefix}${_result}"
    return 0
}

function f_failOverBuildCrontab() {
    local __doc__="Download build-crontab from SVN and replace hostname to new hostname and copy to /etc/cron.d/ if third argument '_over_writing' is Y."
    local _source_hostname="$1"
    local _target_hostname="$2"
    local _over_writing="$3"
    
    if ! _isIpOrHostname "$_source_hostname" ; then
        _warn "$FUNCNAME requeres source (original/old) hostname as the first argument"
        return 1
    fi
    
    if ! _isIpOrHostname "$_target_hostname" ; then
        _warn "$FUNCNAME requeres target (this/new) hostname as the second argument"
        return 1
    fi
    
    f_getFromSvn "/server-configurations/${_source_hostname}${g_build_crontab}" "/tmp/build-crontab_${_source_hostname}" "Y"
    
    if [ ! -s "/tmp/build-crontab_${_source_hostname}" ]; then
        _warn "$FUNCNAME: could not download ${_source_hostname}${g_build_crontab}"
        return 1
    fi
    
    sed "s/${_source_hostname}/${_target_hostname}/g" /tmp/build-crontab_${_source_hostname} > /tmp/build-crontab_${_target_hostname}
    
    if [ ! -s "/tmp/build-crontab_${_target_hostname}" ]; then
        _warn "$FUNCNAME: could not replace hostnames with sed."
        return 1
    else
        _info "Created /tmp/build-crontab_${_target_hostname}"
    fi
    
    if _isYes "$_over_writing"; then
        f_backup "$g_build_crontab"
        _eval "/etc/init.d/cron stop >/dev/null"
        _eval "mv /tmp/build-crontab_${_target_hostname} $g_build_crontab"
        if [ $g_last_rc -eq 0 ]; then
            _info "Successfully moved $g_build_crontab after taking a backup"
            _warn "Please run \"/etc/init.d/cron start\" manually"
        else
            _warn "Failed to move $g_build_crontab."
            _warn "Please run \"/etc/init.d/cron start\" manually"
        fi
    fi
    
    return $g_last_rc
}

### Validations ###############################################################
function f_validationPre() {
    local __doc__="To check if this system satisfies to run this script and if all mandatory questions are answered.
keyword: varidate, verify."
    local _is_OK=true
    local _question=""
    # FIXME: Add more validation such as 
    #     umount or at least check mount before using sshfs and mount
    #     SVN connection test
    #     ssh to remote DB server to check md5sum or file size before downloading
    
    echo ""
    echo "=== Validating your installation... ========================="
    echo ""
    
    if [ -z "$SUDO_USER" ]; then
        _warn "'sudo' is necessary to run ${g_script_name} (or 'sudo -s')"
        _is_OK=false
    elif [ $UID -ne 0 ]; then
        _warn "${g_script_name} must be run as root (or sudo)"
        _is_OK=false
    fi
    
    local _ubu_ver=`cat /etc/issue.net`
    if [[ ! $_ubu_ver =~ $g_supported_ubuntu_regex ]]; then
        _warn "'${_ubu_ver}' is not supported OS version."
        _is_OK=false
    fi
    
    local _uname_m="`uname -m`"
    if [ ${_uname_m} != 'x86_64' ]; then
        _warn "'${_uname_m}' is not supported architecture."
        _is_OK=false
    fi
    
    # Example of checking necessary command (but not in use now)
    #if ! _isCmd "curl" ; then
    #    _warn "'curl' is necessary."
    #    _is_OK=false
    #fi
    
    if ! f_isEnoughMemory "$g_min_memory_size_mb" ; then
        _warn "Recommended MINIMUM memory size is $g_min_memory_size_mb (or at least 10% free)"
        _is_OK=false
    fi
    
    if ! f_isEnoughDisk "/" "$g_min_db_data_size_gb" ; then
        _warn "Recommended MINIMUM disk size is $g_min_db_data_size_gb GB (or at least 10% free)"
        _is_OK=false
    fi
    
    _info "Checking mandatory parameters..."
    _checkMandatories "Y"
    _checkMandatories "\[.+\]"
    
    if ! $_is_OK; then
        f_ask "Would you like to ignore above WARNINGs?" "N"
        if ! _isYes; then _echo "Bye."; _exit 1; fi
    fi
}

function _checkMandatories() {
    local _regex="${1-(Y|\[.+\])}"
    local _tmp_file="/tmp/tmp_$FUNCNAME_$$.out"
    
    if _isYes "$_is_Yes_only"; then _regex="Y"; fi
    
    local _question=""
    local _r=""    # response(answer) name
    local _m=""    # is_mandatory flag
    local _answer=""
    
    # FIXME: "read" (f_ask) in "while read loop" does not work properly, so that separating commands.
    type f_interview | grep -oiP "f_ask \".+?\" \".*?\" \"r_.+?\" \".*?\" \"${_regex}\".*$" | sort | uniq > $_tmp_file
    
    for _r in `cat $_tmp_file | awk -F'" "' '{print $3}'`; do
        _question=`grep "$_r" -m 1 $_tmp_file`
        _m="$(echo "$_question" | awk -F'" "' '{print $5}')" && _m="${_m%\";}"
        
        if _isYes "$_m" && [ -z "${!_r}" ]; then
            _warn "Mandatory parameter '${_r}' is empty."
            f_ask "Would you like to type it now?" "Y"
            if _isYes ; then
                eval "$_question"
            else
                _is_OK=false
            fi
        fi
    done
    
    rm -f "$_tmp_file"
}

function f_validationPost() {
    local __doc__="Check if installation was successful."
    echo "" 1>&2
    echo "Validating your installation..." 1>&2
    echo "" 1>&2
    
    echo "=== System Information: =============================="
    echo "SUDO User:    $SUDO_USER"
    echo "Response:    $g_response_file"
    echo "Hostname:    `hostname`"
    echo "Uname -a:    `uname -a`"
    echo ""
    echo "=== Network Interface: ==============================="
    ifconfig | grep ^eth -A 1
    echo ""
    echo "=== Routing table: ==================================="
    netstat -rn
    echo ""
    echo "=== File System: ====================================="
    df -hTl | grep -P '^(Filesystem|/)'
    echo ""
    echo "=== Installed Virtual Host ==========================="
    f_listApacheVirtualHost
    echo ""
    echo "=== Installed Database ==============================="
    sudo -u $g_db_superuser psql -P pager=off -p "$g_db_port" -x -c '\l+'
    sudo -u $g_db_superuser psql -P pager=off -p "$g_db_port" -x -c 'select version()'
    echo ""
    echo "=== Checking Installation ============================"
    
    echo "Checking OS (Ubuntu)..." 1>&2
    for d in "${g_make_dir_list[@]}"; do
        [ -d "$d" ] || echo "WARN: Directory \"$d\" does not exist."
    done
    
    if [ -n "$r_new_hostname" ]; then
        [ "`hostname`" = "$r_new_hostname" ] || echo "WARN: Hostname has not been changed to $r_new_hostname"
    fi
    
    if _isEmail "$r_admin_mail"; then
        if [ "$_server_type" != "dev" ]; then
            grep "${g_non_delivery_mailuser}@" /etc/postfix/generic || echo "WARN: Non delivery mail address has not been set in /etc/postfix/generic."
            grep "${g_non_delivery_mailuser}@" /etc/aliases || echo "WARN: Non delivery mail address has not been set in /etc/alias."
        fi
        
        grep "$r_admin_mail" /etc/postfix/generic || echo "WARN: Admin(root) mail address has not been set in /etc/postfix/generic."
        grep "$r_admin_mail" /etc/aliases || echo "WARN: Admin(root) mail address has not been set in /etc/alias."
    fi
    
    if _isYes "$r_config_nic" && [ -n "$r_nic_address" ]; then
        ifconfig $r_nic_name | grep -w "$r_nic_address" &>/dev/null || echo "WARN: Network IP is different from $r_nic_address for $r_nic_name"
    fi
    
    if _isYes "$r_config_proxy"; then
        env | grep -i proxy | grep "$r_proxy_address" &>/dev/null || echo "WARN: Network Proxy is not set or different from $r_proxy_address"
    fi
    
    [ -s "/etc/cron.daily/ntp-update" ] || echo "WARN: NTP update might not be scheduled in cron."
    
    service postfix status &>/dev/null || echo "WARN: SMTP server Postfix is not running."
    
    if _isYes "$r_disable_ssh_pauth" ; then
        # buildsystemuser should not be able to access by ssh
        # FIXME: the following if condition is not perfect.
        if [ -s "/home/${g_system_user}/.ssh/id_rsa" ] || [ -s "/home/${g_system_user}/.ssh/id_dsa" ]; then
            echo "WARN: ${g_system_user} should not have private key."
        fi
        
        if [ -s "/home/${g_system_user}/.ssh/authorized_keys" ]; then
            echo "WARN: ${g_system_user} should not have authorized_keys entry."
        fi
        
        sudo -u ${g_system_user} ssh -q -o StrictHostKeyChecking=no -o BatchMode=yes 127.0.0.1 'echo "SSH connection test (you should not see this message)"'
        local _ssh_rc=$?
        if [ $_ssh_rc -eq 0 ]; then
            echo "WARN: ${g_system_user} should be a local system user and should not be able to access with SSH."
        elif [ $_ssh_rc -ne 255 ]; then
            echo "WARN: ${g_system_user} might not be configured properly SSH return code $_ssh_rc"
        fi
        
        if [ -s "/home/${g_automation_user}/.ssh/id_rsa" ]; then
            if [ "$r_server_type" != "dev" ]; then
                echo "WARN: A private key found for ${g_automation_user}. Not recommended for Production system."
            fi
            
            sudo -u ${g_automation_user} ssh -q -o StrictHostKeyChecking=no -o BatchMode=yes 127.0.0.1 'echo "SSH connection test"'
            if [ $? -ne 0 ]; then
                echo "WARN: ${g_automation_user} should be able to access this server with SSH without any prompt."
            fi
        fi
        # FIXME: buildmaintenance or itsupport should have limited permissions but testing this is hard.
    fi
    
    [ -s "$g_build_crontab" ] || echo "WARN: Build Crontab $g_build_crontab does not exist."
    
    grep -P '^[0-9]{1,2}\s+?[0]{1,2}\s+?.+?cron.daily' /etc/crontab &>/dev/null || echo "WARN: Please change /etc/crontab daily job to start at 0 AM."
    
    
    echo "Checking Postgresql settings..." 1>&2
    for _k in "${!g_db_conf_array[@]}"; do
        grep -P "^${_k}\s*?=\s*?${g_db_conf_array[$_k]}" ${g_db_conf_dir%/}/postgresql.conf &>/dev/null || echo "WARN: DB setting \"${_k}\" value \"${g_db_conf_array[$_k]}\" does not exist."
    done
    grep -i -P '^host.+\strust' ${g_db_conf_dir%/}/pg_hba.conf | grep -wv 'replication' && echo "WARN: ${g_db_conf_dir%/}/pg_hba.conf contains 'trust'. Please change it to 'md5'"
    
    echo "Checking Database service..." 1>&2
    sudo -u postgres -s psql -P pager=off -p ${g_db_port} template1 -c '\dx' | grep -w tablefunc &>/dev/null || echo "WARN: DB extension tablefunc is missing."
    
    if [ -n "$r_db_username" ]; then
        if [ -n "$r_db_name" ]; then
            PGPASSWORD="$r_db_password" psql -P pager=off -U "$r_db_username" -h 127.0.0.1 -p "$g_db_port" $r_db_name -c 'select version()' | grep "$g_db_version" &>/dev/null || echo "WARN: PG ver. $g_db_version, $r_db_name connection test on port $g_db_port as $r_db_username failed."
        else
            PGPASSWORD="$r_db_password" psql -P pager=off -U "$r_db_username" -h 127.0.0.1 -p "$g_db_port" template1 -c 'select version()' | grep "$g_db_version" &>/dev/null || echo "WARN: PG ver. $g_db_version connection test on port $g_db_port as $r_db_username failed."
        fi
    fi
    
    echo "Checking PHP settings..." 1>&2
    for _k in "${!g_php_ini_array[@]}"; do
        grep -P "^${_k}\s*?=\s*?${g_php_ini_array[$_k]}" ${g_php_ini_path} &>/dev/null || echo "WARN: PHP setting \"${_k}\" value \"${g_php_ini_array[$_k]}\" does not exist."
    done
    
    echo "Checking Web service (Apache/PHP)..." 1>&2
    service apache2 status &>/dev/null || echo "WARN: Web server apache2 is not running."
    
    local _url="$r_apache_server_name"
    if [ -z "$_url" ]; then
        _url="127.0.0.1"
    fi
    
    if [ -n "$_url" ]; then
        curl -s http://$_url/xul/info.php | grep -w PHP &>/dev/null || echo "WARN: PHP info didn't return correct information."
        curl -s -I -H 'Accept-Encoding: gzip,deflate' http://$_url/xul/info.php | grep -w gzip &>/dev/null || echo "WARN: Apache Compression might not be working."
        if [ -n "$r_apache_env_website" ]; then
            curl -s http://$_url/xul/info.php | grep -w WEBSITE | grep -w $r_apache_env_website &>/dev/null || echo "WARN: PHP info didn't return WEBSITE $r_apache_env_website"
        fi
        if [ -n "$r_code_import" ] && [ "$r_code_import" != "skip" ]; then
            curl -s http://$_url/xul/lite/index_redirected.php | grep 'All rights reserved' &>/dev/null || echo "WARN: Build lite on $_url is unreachable."
        fi
    fi
    
    if [ -n "$r_code_import_target" ] && [ "$r_code_import" = "svn" ]; then
        echo "Checking Build SVN repository..." 1>&2
        if [ ! -d "$r_code_import_target" ]; then
            echo "WARN: Code import directory $r_code_import_target does not exist."
        else
            if [ -n "$r_svn_user" ]; then
                local _svn_cmd="svn info ${r_code_import_target%/}/"
                local _final_svn_cmd="$(_getSvnFullCmd "$_svn_cmd")"
                $_final_svn_cmd || echo "WARN: SVN Info failed."
                _svn_cmd="svn st -u ${r_code_import_target%/}/"
                _final_svn_cmd="$(_getSvnFullCmd "$_svn_cmd")"
                $_final_svn_cmd || echo "WARN: SVN Status failed."
            fi
        fi
    fi
    
    if [ -n "$r_apache_env_website" ]; then
        echo "Checking Build crontab's website ID..." 1>&2
        local _line_num
        local _line
        
        # cat /etc/crontab | grep -vE '(^#|^\s*$)'
        local _cron_lines_with_ws="`grep -nE '(^[0-9]|^\*|^@)' /etc/cron.d/build-crontab | grep -w -- '--website'`"
        echo -e "$_cron_lines_with_ws" | while read l; do
            _line_num="`echo -e "$l" | cut -d":" -f 1`"
            _line="`echo -e "$l" | cut -d":" -f 2-`"
            echo -e "$_line" | grep -P -- "--website[ =]$r_apache_env_website" > /dev/null || echo -e "WARN: /etc/cron.d/build-crontab line:$_line_num may not use website ID \"${r_apache_env_website}\".\n      ${_line}"
        done
    fi
    
    if [ -s "${g_command_output_log}" ]; then
        echo "Greping WARN/ERROR from the last build script log file..." 1>&2
        echo ""
        echo "=== Greping command output log =========================="
        echo "${g_command_output_log}"
        grep -w WARN ${g_command_output_log} 2>/dev/null
        grep -w ERROR ${g_command_output_log} 2>/dev/null
    fi
    echo ""
    return 0
}

function f_isEnoughDisk() {
    local __doc__="Check if entire system or the given path has enough space with GB."
    local _dir_path="${1-/}"
    local _required_gb="$2"
    local _available_space_gb=""
    
    _available_space_gb=`_freeSpaceGB "${_dir_path}"`
    
    if [ -z "$_required_gb" ]; then
        echo "${_available_space_gb}GB free space"
        _required_gb=`_totalSpaceGB`
        _required_gb="`expr $_required_gb / 10`"
    fi
    
    if [ $_available_space_gb -lt $_required_gb ]; then return 1; fi
    return 0
}

function _freeSpaceGB() {
    local __doc__="Output how much space for given directory path."
    local _dir_path="$1"
    if [ ! -d "$_dir_path" ]; then _dir_path="-l"; fi
    df -P --total ${_dir_path} | grep -i ^total | awk '{gb=sprintf("%.0f",$4/1024/1024);print gb}'
}

function _totalSpaceGB() {
    local __doc__="Output how much space for given directory path."
    local _dir_path="$1"
    if [ ! -d "$_dir_path" ]; then _dir_path="-l"; fi
    df -P --total ${_dir_path} | grep -i ^total | awk '{gb=sprintf("%.0f",$2/1024/1024);print gb}'
}

function f_isEnoughMemory() {
    local __doc__="Check if this sytem has enough Physical RAM (and over 10% free memory)."
    local _required_physical_mb="$1"
    local _required_free_mb="$2"
    local _physical_mb
    local _free_mb
    
    _physical_mb=`_PhysicalRamMB`
    _free_mb=`_freeRamMB`
    
    if [ -z "$_required_free_mb" ]; then
        _required_free_mb="`expr $_physical_mb / 10`"
    fi
    
    if [ -n "$_required_physical_mb" ]; then
        if [ $_physical_mb -lt $_required_physical_mb ]; then return 1; fi
    fi
    
    if [ $_free_mb -lt $_required_free_mb ]; then return 1; fi
    return 0
}

function _PhysicalRamMB() {
    local __doc__="Output how much memory is available with MB."
    grep ^MemTotal /proc/meminfo | awk '{mb=sprintf("%.0f",$2/1024);print mb}'
}

function _freeRamMB() {
    local __doc__="Output how much memory is available with MB."
    grep ^MemFree /proc/meminfo | awk '{mb=sprintf("%.0f",$2/1024);print mb}'
}

function f_checkUpdate() {
    local __doc__="Check if newer script is available in SVN, then download."
    local _local_file_path="${1-$BASH_SOURCE}"
    local _file_name=`basename ${_local_file_path}`
    if [ -z "$r_svn_url_build" ]; then
        r_svn_url_build="$g_svn_url_build"
    fi
    g_script_url="${r_svn_url_build%/}/site/${g_script_partial_path}"
    local _remote_url="${2-${g_script_url}}"
    
    if [ ! -s "$_local_file_path" ]; then
        _warn "$FUNCNAME: could not check last modified time of $_local_file_path"
        return 1
    fi
    
    _askSvnUser
    if [ $? -ne 0 ]; then
        _warn "$FUNCNAME: No SVN username. Exiting."; return 1
    fi
    
    if ! _isCmd "curl"; then
        if [ "$0" = "$BASH_SOURCE" ]; then
            _warn "$FUNCNAME: No 'curl' command. Exiting."; return 1
        else
            f_ask "Would you like to install 'curl'?" "Y"
            if _isYes ; then
                _eval "DEBIAN_FRONTEND=noninteractive apt-get -y install curl &>/dev/null" "N"
            fi
        fi
    fi
    
    #wget -q -t 2 --http-user=${r_svn_user} --http-passwd=${r_svn_pass} -S --spider "${_remote_url}" 2>&1 | grep Last-Modified
    local _remote_last_mod="$(curl -s --basic --user ${r_svn_user}:${r_svn_pass} --head "${_remote_url}" | grep -i last-modified | cut -c16-)"
    if [ -z "$_remote_last_mod" ]; then _warn "$FUNCNAME: Unknown last modified."; return 1; fi

    local _remote_last_mod_ts=`date -d "${_remote_last_mod}" +"%s"`
    local _local_last_mod_ts=`stat -c%Y $_local_file_path`
    
    #_log "Remote: ${_remote_last_mod_ts} (gt) Local: ${_local_last_mod_ts}"
    if [ ${_remote_last_mod_ts} -gt ${_local_last_mod_ts} ]; then
        _info "Newer file is available."
        echo "$_remote_last_mod"
        f_ask "Would you like to download?" "Y"
        if ! _isYes; then return 0; fi
        f_backup "${_local_file_path}"
        
        if [[ "${_local_file_path}" =~ ^/data/sites/ ]]; then
            svn up ${_local_file_path}
        elif [[ "`pwd`" =~ ^/data/sites/ ]]; then
            svn up ${_local_file_path}
        else
            _eval "curl --basic --user ${r_svn_user}:${r_svn_pass} '$_remote_url' -o ${_local_file_path}" "N" || _critical "$FUNCNAME: Update faild."
        fi
        
        _info "Validating the downloaded script..."
        source ${_local_file_path} || _critical "Please contact the script author."
        changeLog
    fi
}

### Utility functions #########################################################

function _getSection() {
    local _start_section_regex="$1"
    local _next_section_regex="$2"
    local _file_path="${3-__STDIN__}"
    local _contents=""
    
    if [ "$_file_path" != "__STDIN__" ] && [ ! -s "$_file_path" ]; then return 1; fi
    
    if [ "$_file_path" = "__STDIN__" ]; then
        while read __x ; do _contents="${_contents}${__x}\n" ; done
    else
        _contents="$(cat $_file_path)"
    fi
    
    local _max_line_num=`echo -e "$_contents" | wc -l | awk '{print $1}'`
    local _start_line_num=`echo -e "$_contents" | grep -nm 1 -P "$_start_section_regex" | cut -d":" -f1`
    
    if [ -z "$_start_line_num" ]; then return 1; fi
    
    local _tmp_line_num=$(( $_start_line_num + 1 ))
    local _tmp_line_end_num=`echo -e "$_contents" | sed -n "${_tmp_line_num},${_max_line_num}p" | grep -nm 1 -P "${_next_section_regex}" | cut -d":" -f1`
    local _end_line_num=$(( $_start_line_num + $_tmp_line_end_num - 1 ))
    if [ -z "$_start_line_num" ]; then
        _end_line_num=$(( $_max_line_num - $_start_line_num ))
    fi
    echo -e "$_contents" | sed -n "${_start_line_num},${_end_line_num}p"
    return $?
}

function f_getBuildConfigValueFromSvn() {
    local __doc__="Search config.ini.php and return the value.
NOTE: This script may not work if there are multiple lines which matches given parameter."
    local _param_name="$1"
    local _website="$2"
    
    if [ -n "$_website" ]; then
        local _value="$(f_getFromSvn "$g_build_config_svn_path" "-" | _getSection "^\[\s*${_website}\s*:" "^\[" | grep -P "^${_param_name}\s*=" | tail -n 1 | awk '{print $3}')"
    else
        local _value="$(f_getFromSvn "$g_build_config_svn_path" "-" | grep -P "^${_param_name}\s*=" -m 1 | awk '{print $3}')"
    fi
    local _rc=$?
     # remove all double-quote
    _value="${_value//\"/}"
    # TODO: decrypt _value if it starts with 'ENC|'
    #_value="`_deobfuscate "$_value" "Y"`"
    
    echo -e "$_value"
    return $_rc
}

function f_getBuildConfigValueFromPhp() {
    local __doc__="Search config.ini.php and return the value.
NOTE: This script may not work if there are multiple lines which matches given parameter."
    local _param_name="$1"
    local _website="$2"
    local _pwd="$PWD"
    
    local _query_config_path="${r_apache_document_root%/}/xul/cronjobs/query_config.php"
    local _query_config_dir="${r_apache_document_root%/}/xul/cronjobs/"
    
    if [ ! -s "$_query_config_path" ]; then
        local _query_config_path="`ls -t /data/sites/*/webroot/xul/cronjobs/query_config.php | head -n1`"
        
        if [ ! -s "$_query_config_path" ]; then
            _warn "$FUNCNAME could not find $_query_config_path"
            return 1
        fi
    fi
    
    if [ -z "$_param_name" ]; then
        _warn "$FUNCNAME requires _param_name"
        return 1
    fi
    
    if [ -z "$_website" ]; then
        _warn "$FUNCNAME requires _website ID"
        return 1
    fi
    
    local _value=""
    
    local _dir_path="$(dirname ${_query_config_path})"
    cd $_dir_path
    if [ $? -ne 0 ]; then
        _warn "$FUNCNAME could not cd to $_dir_path"
        return 1
    fi
    
    php ./query_config.php --website="$_website" --key="$_param_name"
    return $?
}

function f_ask() {
    local __doc__="Ask one question and store the answer in a specified variable name.
If space is given and default value is not empty, use default instead of previous value."
    _log "$FUNCNAME: vars= $@ "
    local _question="$1"
    local _default="$2"
    local _var_name="$3"
    local _is_secret="$4"
    local _is_mandatory="$5"
    local _validation_func="$6"
    
    local _default_orig="$_default"
    local _cmd=""
    local _full_question="${_question}"
    local _trimmed_answer=""
    local _previous_answer=""
    
    if [ -z "${_var_name}" ]; then
        g_last_answer=""
        _var_name="g_last_answer"
    fi
    
    # currently only checking previous value of the variable name starting with "r_"
    if [[ "${_var_name}" =~ ^r_ ]]; then
        _previous_answer=`_trim "${!_var_name}"`
        if [ -n "${_previous_answer}" ]; then _default="${_previous_answer}"; fi
    fi
    
    if [ -n "${_default}" ]; then
        if _isYes "$g_force_default" ; then
            if [ "${_var_name}" = "g_last_answer" ]; then
                g_last_answer="${_default}"
            elif [[ "${_var_name}" =~ ^r_ ]]; then
                eval "${_var_name}=\"${_default}\"" || _critical "$FUNCNAME: invalid variable name '${_var_name}' or default value '${_default}'."
                
                # display result (and logging)
                if _isYes "$_is_secret" ; then
                    _echo "    $_question = \"*******\""
                else
                    _echo "    $_question = \"${!_var_name}\""
                fi
            fi
            
            return 0
        fi
        
        if _isYes "$_is_secret" ; then
            _full_question="${_question} [*******]"
        else
            _full_question="${_question} [${_default}]"
        fi
    fi
    
    _log "$FUNCNAME: Question: \"${_full_question}\"."
    
    if _isYes "$_is_secret" ; then
        local _temp_secret=""
        
        while true ; do
            read -p "${_full_question}: " -s "${_var_name}"; echo ""
            
            if [ -z "${!_var_name}" -a -n "${_default}" ]; then
                eval "${_var_name}=\"${_default}\""
                break;
            else
                read -p "${_question} (again): " -s "_temp_secret"; echo ""
                
                if [ "${!_var_name}" = "${_temp_secret}" ]; then
                    break;
                else
                    echo "1st value and 2nd value do not match."
                fi
            fi
        done
        
        _log "$FUNCNAME: Answer: ${_var_name}=\"******\"."
    else
        read -p "${_full_question}: " "${_var_name}"
        
        _trimmed_answer=`_trim "${!_var_name}"`
        
        if [ -z "${_trimmed_answer}" -a -n "${_default}" ]; then
            # if new value was only space, use original default value instead of previous value
            if [ -n "${!_var_name}" ]; then
                _info "Using default value \"$_default_orig\"."
                eval "${_var_name}=\"${_default_orig}\""
            else
                _log "$FUNCNAME: Using default value \"${_default}\" as per an empty input."
                eval "${_var_name}=\"${_default}\""
            fi
        else
            eval "${_var_name}=\"${_trimmed_answer}\""
        fi
        
        _log "$FUNCNAME: Answer: ${_var_name}=\"${!_var_name}\"."
    fi
    
    # if empty value, check if this is a mandatory field.
    if [ -z "${!_var_name}" ]; then
        if _isYes "$_is_mandatory" ; then
            _echo "'${_var_name}' is a mandatory parameter."
            f_ask "$@"
        fi
    else
        # if not empty and if a validation function is given, use function to check it.
        if _isValidateFunc "$_validation_func" ; then
            $_validation_func "${!_var_name}"
            if [ $? -ne 0 ]; then
                f_ask "Given value does not look like correct. Would you like to re-type?" "Y"
                if _isYes; then
                    f_ask "$@"
                fi
            fi
        fi
    fi
}

function _isValidateFunc() {
    local _function_name="$1"
    
    # FIXME: not good way
    if [[ "$_function_name" =~ ^_is ]]; then
        typeset -F | grep "^declare -f $_function_name$" &>/dev/null
        return $?
    fi
    return 1
}

function f_loadResp() {
    local __doc__="Load responses(answers) from given file path or from default location."
    local _file_path="${1-$g_response_file}"
    local _used_7z=false
    
    if [ -z "$_file_path" ]; then
        _file_path="$g_default_response_file";
    fi
    
    local _actual_file_path="$_file_path"
    if [ ! -r "${_file_path}" ]; then
        if [ ! -r "${_file_path}.7z" ]; then
            _critical "$FUNCNAME: Not readable response file. ${_file_path}" 1;
        else
            _actual_file_path="${_file_path}.7z"
        fi
    fi
    
    g_response_file="$_file_path"
    
    local _extension="${_actual_file_path##*.}"
    if [ "$_extension" = "7z" ]; then
        local _dir_path="$(dirname ${_actual_file_path})"
        cd $_dir_path && 7za e ${_actual_file_path} || _critical "$FUNCNAME: 7za e error."
        cd - >/dev/null
        _used_7z=true
    fi
    
    # Note: somehow "source <(...)" does noe work, so that created tmp file.
    grep -P -o '^r_.+[^\s]=\".*?\"' ${_file_path} > /tmp/f_loadResp_${g_pid}.out && source /tmp/f_loadResp_${g_pid}.out
    
    # clean up
    rm -f /tmp/f_loadResp_${g_pid}.out
    if $_used_7z ; then rm -f ${_file_path}; fi
    
    if [ -n "${r_svn_user}" ]; then
        f_checkUpdate
        return $?
    fi
    return $?
}

function f_saveResp() {
    local __doc__="Save current responses(answers) into the specified file path or into the default location."
    local _file_path="${1-$g_response_file}"
    local _is_encrypting="$2"
    
    if [ -z "$_file_path" ]; then _file_path="$g_default_response_file"; fi
    
    if [ ! -e "${_file_path}" ]; then
        _makeBackupDir
        touch ${_file_path}
    elif ! _isYes "$_is_encrypting"; then
        # FIXME: not taking backup if encrypting...
        f_backup "${_file_path}"
    fi
    
    if [ ! -w "${_file_path}" ]; then
        _critical "$FUNCNAME: Not writeable response file. ${_file_path}" 1
    fi
    
    # clear file (no warning...)
    cat /dev/null > ${_file_path}
    
    for _v in `set | grep -P -o "^r_.+?[^\s]="`; do
        _new_v="${_v%=}"
        echo "${_new_v}=\"${!_new_v}\"" >> ${_file_path}
    done
    
    # trying to be secure as much as possible
    if [ -n "$SUDO_USER" ]; then
        chown $SUDO_UID:$SUDO_GID ${_file_path}
    fi
    chmod 1600 ${_file_path}
    
    if _isYes "$_is_encrypting" ; then
        echo ""
        f_ask "Response file password" "" "_response_pass" "Y" "Y"
        
        if ! _isCmd "7za"; then
            _eval "DEBIAN_FRONTEND=noninteractive apt-get -y install p7zip-full >/dev/null" "N" || _critical "$FUNCNAME requirs p7zip-full package"
        fi
        
        # taking resp.7z file if exist then delete, otherwise 7za command fails
        f_backup "${_file_path}.7z" &>/dev/null && _eval "rm -f ${_file_path}.7z"
        _eval "7za a ${_file_path}.7z ${_file_path} -p${_response_pass} >/dev/null" "N" || _critical "$FUNCNAME: ecrypting ${_file_path} failed."
        _response_pass=""
        
        if [ -s "${_file_path}.7z" ]; then
            _eval "rm -f ${_file_path}" "N"
        fi
    fi
    
    _info "Saved ${_file_path}"
}

function f_backup() {
    local __doc__="Backup the given file path into the backup directory."
    local _file_path="$1"
    local _file_name="`basename $_file_path`"
    local _force="$2"
    local _new_file_name=""
    
    if [ ! -e "$_file_path" ]; then
        _warn "$FUNCNAME: No taking a backup as $_file_path does not exist."
        return 1
    fi
    
    if _isYes "$_force"; then
        local _mod_dt="`stat -c%y $_file_path`"
        local _mod_ts=`date -d "${_mod_dt}" +"%Y%m%d-%H%M%S"`
        
        if [[ ! $_file_name =~ "." ]]; then
            _new_file_name="${_file_name}_${_mod_ts}"
        else
            _new_file_name="${_file_name/\./_${_mod_ts}.}"
        fi
    else
        if [[ ! $_file_name =~ "." ]]; then
            _new_file_name="${_file_name}_${g_start_time}"
        else
            _new_file_name="${_file_name/\./_${g_start_time}.}"
        fi
        
        if [ -e "${g_backup_dir}${_new_file_name}" ]; then
            _info "$_file_name already backed up. Skipping..."
            return 0
        fi
    fi
    
    _makeBackupDir
    _eval "cp -p ${_file_path} ${g_backup_dir}${_new_file_name}" || _critical "$FUNCNAME: failed to backup {_file_path}"
}

function f_setPostgreConf() {
    local __doc__="Modify PostgreSQL config file."
    local _param_name="$1"
    local _param_val="$2"
    local _conf_path="$3"
    
    if [ -z "$_conf_path" ]; then
        _conf_path="${g_db_conf_dir%/}/postgresql.conf"
    fi
    
    f_setConfig "$_conf_path" "$_param_name" "$_param_val" "#" "=" "" "" "$g_db_superuser"
}

function f_setPhpIni() {
    local __doc__="Modify PHP config file."
    local _param_name="$1"
    local _param_val="$2"
    f_setConfig "${g_php_ini_path}" "$_param_name" "$_param_val" ";"
}

function f_setConfig() {
    # FIXME: very fragile
    local __doc__="Modify the given file with given parameter name and value."
    local _conf_file_path="$1"
    local _param_name="$(_escape "$2")"
    local _param_val="$(_escape "$3")"
    local __param_name_sed="$(_escape_sed "$2")"
    local __param_val_sed="$(_escape_sed "$3")"
    local _comment_char="${4-#}"
    local _between_char="${5-=}"
    local _is_appending="$6"
    local _append_between_char="${7-$_between_char}"
    local _run_as="$8"
    
    local _match_line=""
    local _grep_result=""
    local _comment=""
    local _non_comment=""
    local _replace_sed="${__param_name_sed}${_between_char}${__param_val_sed}"
    local _replace="${_param_name}${_between_char}${_param_val}"
    local __insert="$(_escape_double_quote "${2}${_between_char}${3}")"
    
    if [ ! -w $_conf_file_path ]; then
        # not creating a file but just die.
        _critical "$FUNCNAME: ${_conf_file_path} is not writable."
    fi
    
    # trying to pick up the last one
    _match_line="$(grep -P "^\s*${_param_name}" ${_conf_file_path} | tail -n1)"
    
    # trying to pick up the last commented one ('#xxxx=yyyy' or '# xxxxx = yyyy')
    if [ -z "$_match_line" ]; then 
        _match_line="$(grep -P "^${_comment_char}\s{0,1}${_param_name}\s*${_between_char}\s*.+?\s*$" ${_conf_file_path} | sort | tail -n1)"
    fi
    
    if [ -z "$_match_line" ]; then 
        _match_line="$(grep -P "^\s*${_comment_char}\s*${_param_name}\s*${_between_char}\s*.+?\s*$" ${_conf_file_path} | sort | tail -n1)"
    fi
    
    if [ -z "$_match_line" ]; then 
        # FIXME: trying to pick up right one (the line with less spaces first). 'sort -n' seems to work but not perfect and lazy way.
        _match_line="$(grep -P "^\s*${_comment_char}\s*${_param_name}" ${_conf_file_path} | sort | tail -n1)"
    fi
    
    if [ -z "$_match_line" ]; then 
        _info "No matching for ${_param_name}, so that inserting in the end of file..."
        _eval "echo \"${__insert}\" >> ${_conf_file_path}" "" "$_run_as"
        grep -P "^${__insert}$" ${_conf_file_path} &>/dev/null || _critical "$FUNCNAME: didn't find \"${__insert}\" in ${_conf_file_path}."
        return 0
    fi
    
    # check if already set or not
    if _isYes "$_is_appending"; then
        echo "$_match_line" | grep -P "^${_param_name}\s*${_between_char}.*${_param_val}" 2>/dev/null
        if [ $? -eq 0 ]; then
            _info "looks like the value is already set. Skipping..."
            return 0
        fi
    else
        echo "$_match_line" | grep -P "^${_param_name}\s*${_between_char}\s*${_param_val}" 2>/dev/null
        if [ $? -eq 0 ]; then
            _info "looks like the value is already set. Skipping..."
            return 0
        fi
    fi
    
    # # pname = xxxx # comment
    _grep_result=`echo "$_match_line" | grep -P "^${_comment_char}\s*${_param_name}[\s${_between_char}].*?${_comment_char}.*$"`
    if [ -n "$_grep_result" ]; then
        # grepping again to preserve extra spaces
        _comment=`echo "$_grep_result" | cut -d"${_comment_char}" -f 2- | grep -oP "\s*${_comment_char}.*$"`
        if _isYes "$_is_appending" ; then
            _non_comment=`echo "$_grep_result" | cut -d"${_comment_char}" -f 2`
            _replace_sed="${_non_comment}${_append_between_char}${__param_val_sed}"
            _replace="${_non_comment}${_append_between_char}${_param_val}"
        fi
        _grep_result_escaped="$(_escape_sed "$_grep_result")"
        _eval "sed -i \"s/^${_grep_result_escaped}$/${_replace_sed}${_comment}/\" ${_conf_file_path}" "" "$_run_as"
        grep -P "^${_replace}" ${_conf_file_path} &>/dev/null || _critical "$FUNCNAME: didn't find \"${_replace}\" in ${_conf_file_path}."
        return 0
    fi
    
    # pname = xxxx # comment
    _grep_result=`echo "$_match_line" | grep -P "^\s*${_param_name}[\s${_between_char}].*?${_comment_char}.*$"`
    if [ -n "$_grep_result" ]; then
        _comment=`echo "$_grep_result" | grep -oP "\s*${_comment_char}.*$"`
        if _isYes "$_is_appending" ; then
            _non_comment=`echo "$_grep_result" | cut -d"${_comment_char}" -f 1`
            _replace_sed="${_non_comment}${_append_between_char}${__param_val_sed}"
            _replace="${_non_comment}${_append_between_char}${_param_val}"
        fi
        _grep_result_escaped="$(_escape_sed "$_grep_result")"
        _eval "sed -i \"s/^${_grep_result_escaped}$/${_replace_sed}${_comment}/\" ${_conf_file_path}" "" "$_run_as"
        grep -P "^${_replace}" ${_conf_file_path} &>/dev/null || _critical "$FUNCNAME: didn't find \"${_replace}\" in ${_conf_file_path}."
        return 0
    fi
    
    # #? pname = xxxx
    _grep_result=`echo "$_match_line" | grep -P "^${_comment_char}?\s*${_param_name}[\s${_between_char}].*$"`
    if [ -n "$_grep_result" ]; then
        if _isYes "$_is_appending" ; then
            _non_comment=`echo "$_grep_result" | grep -oP "${_param_name}[\s${_between_char}].*$"`
            _replace_sed="${_non_comment}${_append_between_char}${__param_val_sed}"
            _replace="${_non_comment}${_append_between_char}${_param_val}"
        fi
        _grep_result_escaped="$(_escape_sed "$_grep_result")"
        _eval "sed -i \"s/^${_grep_result_escaped}$/${_replace_sed}/\" ${_conf_file_path}" "" "$_run_as"
        grep -P "^${_replace}" ${_conf_file_path} &>/dev/null || _critical "$FUNCNAME: didn't find \"${_replace}\" in ${_conf_file_path}."
        return 0
    fi
    
    # #? pname$ (parameter name only)
    _grep_result=`echo "$_match_line" | grep -P "^${_comment_char}?\s*${_param_name}$"`
    if [ -n "$_grep_result" ]; then
        _grep_result_escaped="$(_escape_sed "$_grep_result")"
        _eval "sed -i \"s/^${_grep_result_escaped}$/${_replace_sed}/\" ${_conf_file_path}" "" "$_run_as"
        grep -P "^${_replace}" ${_conf_file_path} &>/dev/null || _critical "$FUNCNAME: didn't find \"${_replace}\" in ${_conf_file_path}."
        return 0
    fi
    
    # could not do anything.
    return 1
}

function f_insertLine() {
    local __doc__="Insert one line into before/after the target line in the given file.\n'_is_ignoring_same' ignores if same line exist in different location.\n'_is_appending_target' adds the target line if it does not exist."
    local _file_path="$1"
    #local _target_line_grep="$(_escape "$2")"  #Not using regex in this function yet
    local _target_line="$(_escape_sed "$2")"
    #local _insert_line_grep="$(_escape "$3")"  #Not using regex in this function yet
    local _insert_line="$(_escape_sed "$3")"
    local _is_after_target="$4"
    local _is_ignoring_same="$5"   # Ignores if _insert_line already exists.
    local _is_appending_target="$6"   # Add target line if does not exist
    local _run_as="$7"
    
    local _sed_opt="i"
    local _grep_opt="-B 1"
    
    if _isYes "$_is_after_target" ; then
        _sed_opt="a"
        _grep_opt="-A 1"
    fi
    
    if _isYes "$_is_ignoring_same"; then
        _eval "grep \"^${_target_line}\" ${_grep_opt} ${_file_path} | grep \"^${_insert_line}\" >/dev/null" "" "$_run_as"
    else
        # does not allow any same line even it's not in before/after taget line.
        _eval "grep \"^${_insert_line}\" ${_file_path} >/dev/null" "" "$_run_as"
    fi
    
    if [ $g_last_rc -ne 0 ]; then
        _eval "grep \"^$_target_line\" $_file_path >/dev/null" "" "$_run_as"
        if [ $? -ne 0 ]; then
            if _isYes "$_is_appending_target"; then
                _eval "echo -e \"$_insert_line\" >> $_file_path" "" "$_run_as"
                _eval "echo -e \"$_target_line\" >> $_file_path" "" "$_run_as"
            fi
        else
            local _tmp_line="\\${_insert_line}"
            _eval "sed -i \"/^${_target_line}/${_sed_opt} ${_tmp_line}\" ${_file_path}" "" "$_run_as"
        fi
    
        grep "^$_insert_line" $_file_path &>/dev/null || _critical "$FUNCNAME: didn't find \"${_insert_line}\" in ${_file_path}."
        return 0
    else
        _info "Found \"${_insert_line}\" in ${_file_path}. Skipping..."
        return 0
    fi
}

function f_appendLine() {
    local __doc__="Append one line in the end of the given file.
Note that this function can't handle some non alphabet characters."
    local _file_path="$1"
    local _line="$(_escape_double_quote "$2")"
    local __line_grep="$(_escape "$2")"
    local _run_as="$3"
    #local _comment_char="${4-#}"
    
    _eval "grep \"^$_line\" $_file_path &>/dev/null" "" "$_run_as"
    if [ $? -ne 0 ]; then
        _eval "echo -e \"$_line\" >> $_file_path" "" "$_run_as"
        grep -P "^$__line_grep" $_file_path &>/dev/null || _critical "$FUNCNAME: didn't find ${__line_grep} in ${_file_path}."
        return 0
    else
        _info "Found \"${_line}\" in ${_file_path}. Skipping..."
        return 0
    fi
}

function f_getFromSvn() {
    local __doc__="Download single file from SVN repo ${g_svn_url%/} with wget"
    local _file_path="$1"
    local _output_path="$2"
    local _overwriting="${3-Y}"
    
    if [ -z "$_svn_user" ]; then
        if ! _askSvnUser ; then
            _warn "$FUNCNAME: No SVN username. Exiting."; return 1
        fi
    fi
    
    local _file_name=`basename $_file_path`
    if [ -z "$_output_path" ]; then
        _output_path="./${_file_name}"
    fi
    
    if [ -e "$_output_path" ]; then
        if _isYes "$_overwriting"; then
            _info "${_file_name} exists. Deleting..."
            _eval "rm -f $_output_path" "N"
        else
            _info "${_file_name} exists. Moving into /tmp/..."
            _eval "mv $_output_path /tmp/" "N"
        fi
    fi
    
    _info "wget -q -t 2 --http-user=${r_svn_user} --http-passwd=xxxxxxxxxx \"${g_svn_url%/}${_file_path}\" -O $_output_path"
    _eval "wget -q -t 2 --http-user=${r_svn_user} --http-passwd=${r_svn_pass} \"${g_svn_url%/}${_file_path}\" -O $_output_path" "N"
}

### Special functions for help/debug ##########################################

function list() {
    local _name="$1"
    local _width=$(( $(tput cols) - 2 ))
    
    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep '^declare -f f_' | cut -d' ' -f3`; do
            eval "echo \"--[ $_f ]\" | sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            help "$_f" "Y"
            echo ""
        done) | less
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | grep '^declare -f f_' | cut -d' ' -f3 | less
    elif [[ "$_name" =~ ^var ]]; then
        set | grep ^[gr]_ | less
    elif [[ "$_name" =~ ^glob ]]; then
        set | grep ^[g]_ | less
    elif [[ "$_name" =~ ^resp ]]; then
        set | grep ^[r]_ | less
    fi
}

function help() {
    local _function_name="$1"
    local _doc_only="$2"
    
    if [ -z "$_function_name" ]; then usage | less; return; fi
    
    if [[ "$_function_name" =~ ^f_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            _echo "Function name '$_function_name' does not exist."
            if ! _isYes "$_doc_only"; then
                echo ""
                usage | less
            fi
            return 1
        fi
        
        local _eval="$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        eval "$_eval"
        
        if [ -z "$__doc__" ]; then
            echo "No help information in function name '$_function_name'."
        else
            echo -e "$__doc__"
        fi
        
        if ! _isYes "$_doc_only"; then
            local _params="$(type $_function_name 2>/dev/null | grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v awk)"
            if [ -n "$_params" ]; then
                echo ""
                echo "Parameters:"
                echo -e "$_params"
            fi
        
            echo ""
            f_ask "Show source code?" "N"
            if _isYes ; then
                echo ""
                echo -e "${_code}" | less
            fi
        fi
    else
        _echo "Unsupported Function name '$_function_name'."
        if ! _isYes "$_doc_only"; then
            echo ""
            usage | less
        fi
        return 1
    fi
}

### Functions should not be used directly #####################################

function _isCmd() {
    local _cmd="$1"
    
    if command -v "$_cmd" &>/dev/null ; then
        return 0
    else
        return 1
    fi
}

function _mkdir() {
    local _target="$1"
    local _mode="${2-$g_default_dir_perm}"
    local _mkdir="mkdir -p"
    
    if [ -n "$_mode" ]; then
        _mkdir="${_mkdir} -m ${_mode}"
    fi
    
    if [ -z "$_target" ]; then
        _warn "$FUNCNAME: Empty target. Skipping..."
        return 1
    fi
    
    if [ -d "$_target" ]; then
        _info "$FUNCNAME: $_target does exist. Skipping..."
        return 0
    fi
    
    _eval "${_mkdir} \"${_target}\""
}

function _bgProgress() {
    local _label="$1"
    local _tmp_file_path="$2"
    local _expect_line="$3"
    local _current_line
    local _percent
    local _prev_line=0
    local _last_bg_pid="$!"
    
    while kill -0 $_last_bg_pid 2>/dev/null ; do
        sleep 10
        _current_line="$(cat $_tmp_file_path 2>/dev/null | wc -l)"
        if [ $_current_line -eq 0 ] && [ $_prev_line -gt 0 ]; then
            # if it's already started but somehow line becomes 0 (ex: another process did 'rm'), exit
            break
        fi
        
        if [ $_current_line -gt $_prev_line ]; then
            _percent=$(echo "$_current_line" "$_expect_line" | awk '{p=sprintf("%.0f", $1/$2*100); print p}')
            if [[ $_percent -gt 99 ]]; then 
                # Stop monitoring if more than 99%
                break;
            fi
            
            echo ""
            echo -n "INFO: ${_label} progress ${_percent}%."
            _prev_line=$_current_line
        else
            echo -n "."
        fi
    done
    
    echo ""
}

function _echo() {
    local _msg="$1"
    local _verbose="$2"
    local _stderr="$3"
    
    if [ -z "$_verbose" ]; then
        _verbose="$g_is_verbose"
    fi
    
    # not loging if verbose is Yes because, at this moment, main() redirects STDOUT/ERR to a log file.
    if _isYes "$_verbose" ; then
        if _isYes "$_stderr" ; then
            echo -e "$_msg" 1>&2
        else 
            echo -e "$_msg"
        fi
    else 
        _log "$_msg"
    fi
}

function _log() {
    local _msg="$1"
    # don't want source-then-run-a-function to generate each log file.
    if $g_is_script_running; then
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] ${_msg}" >> ${g_command_output_log}
    fi
}

function _eval() {
    # FIXME: currently not re-escaping double-quote
    local _cmd="$1"
    local _verbose="$2"
    local _run_as="$3"
    local _use_sudo="$4"
    local _tmp_rc=0
    
    if [ -z "$_verbose" ]; then
        _verbose="$g_is_verbose"
    fi
    
    # if False, not output, not logging
    if _isYes "$_verbose" ; then
        if [ -n "$_run_as" ]; then 
            _echo "${_run_as}@${g_hostname}:$ $_cmd"
        else
            _echo "${USERNAME}@${g_hostname}:# $_cmd"
        fi
    fi
    
    if $g_is_dryrun ; then 
        g_last_rc=0
        return 0
    fi
    
    if [ -n "$_run_as" ]; then
        if _isYes "$_use_sudo"; then
            sudo -u ${_run_as} $_cmd    # FIXME: this does not work somehow
        else
            su - ${_run_as} -c "$_cmd"
        fi
    else
        eval "$_cmd"
    fi
    
    _tmp_rc=$?
    g_last_rc=$_tmp_rc
    return ${_tmp_rc}
}

# _checkLastRC() forces to finish the script
# Used with _eval to share 'g_last_rc'
function _checkLastRC() {
    local _err_msg="$1"
    if [ ${g_last_rc} -ne 0 ]; then
        _critical "${_err_msg}" ${g_last_rc}
    fi
    return ${g_last_rc}
}
function _debug() {
    local _msg="$1"
    local _is_verbose="$2"
    
    if $g_is_debug ; then 
        _echo "DEBUG: ${_msg}" "$_is_verbose" "Y"
    fi
}
function _info() {
    # At this moment, not much difference from _echo and _warn, might change later
    local _msg="$1"
    _echo "INFO : ${_msg}" "Y"
}
function _warn() {
    local _msg="$1"
    _echo "WARN : ${_msg}" "Y" "Y"
}
function _error() {
    local _msg="$1"
    _echo "ERROR: ${_msg}" "Y" "Y"
}
function _critical() {
    local _msg="$1"
    local _exit_code=${2-$g_last_rc}
    
    if [ -z "$_exit_code" ]; then _exit_code=1; fi
    
    _echo "ERROR: ${_msg} (${_exit_code})" "Y" "Y"
    # FIXME: need to test this change
    if $g_is_dryrun ; then return ${_exit_code}; fi
    _exit ${_exit_code}
}
function _exit() {
    local _exit_code=$1
    local _exit_code=$1
    
    if $g_is_script_running; then
        echo ""
        echo ${g_end_msg}
    fi
    
    # Forcing not to go to next step.
    echo "Please press 'Ctrl-c' to exit."
    tail -f /dev/null
    
    if $g_is_script_running; then
        exit $_exit_code
    fi
    return $_exit_code
}

function _isYes() {
    # Unlike other languages, 0 is nearly same as True in shell script
    local _answer="$1"
    
    if [ $# -eq 0 ]; then
        _log "$FUNCNAME: using g_last_answer:${g_last_answer}."
        _answer="${g_last_answer}"
    fi

    if [[ "${_answer}" =~ $g_yes_regex ]]; then
        #_log "$FUNCNAME: \"${_answer}\" matchs."
        return 0
    elif [[ "${_answer}" =~ $g_test_regex ]]; then
        eval "${_answer}" && return 0
    fi
    
    return 1
}

function _isEmail() {
    local _email="$1"
    
    if [ -z "$_email" ]; then
        # empty string is not an e-mail
        return 1
    fi
    
    if [[ "${_email}" =~ @ ]]; then
        return 0
    fi
    return 1
}

function _isUrl() {
    local _url="$1"
    
    if [ -z "$_url" ]; then
        return 1
    fi
    
    if [[ "$_url" =~ $g_url_regex ]]; then
        return 0
    fi
    
    return 1
}

function _isFilePath() {
    local _file_path="$1"
    
    if [ -z "$_file_path" ]; then
        # empty string is not a file path
        return 1
    fi
    
    # FIXME: not good
    if [[ "${_file_path}" =~ / ]]; then
        return 0
    fi
    return 1
}

function _isNotEmptyDir() {
    local _dir_path="$1"
    
    if [ -z "$_dir_path" ]; then return 1; fi
    
    if [ ! -d "$_dir_path" ]; then return 1; fi
    
    if [ "$(ls -A ${_dir_path})" ]; then
        return 0
    else
        return 1
    fi
}

function _isIp() {
    local _ip="$1"
    
    if [ -z "$_ip" ]; then
        return 1
    fi
    
    if [[ "${_ip}" =~ $g_ip_range_regex ]]; then
        return 0
    else
        return 1
    fi
}

function _isIpOrHostname() {
    local _ip_or_hostname="$1"
    
    if [ -z "$_ip_or_hostname" ]; then
        return 1
    fi
    
    if [[ "${_ip_or_hostname}" =~ $g_ip_range_regex ]]; then
        return 0
    elif [[ "${_ip_or_hostname}" =~ $g_hostname_regex ]]; then
        return 0
    else
        return 1
    fi
}

function _isSvnCredential() {
    local _password="${1-$r_svn_pass}"
    wget -q -t 2 --http-user=${r_svn_user} --http-passwd=${_password} ${g_svn_url%/}/build/ -O /dev/null 2>/dev/null
    return $?
}

function _makeBackupDir() {
    if [ ! -d "${g_backup_dir}" ]; then
        mkdir -p -m 700 "${g_backup_dir}"
        if [ -n "$SUDO_USER" ]; then
            chown $SUDO_UID:$SUDO_GID ${g_backup_dir}
        fi
    fi
}

function _split() {
    local _rtn_var_name="$1"
    local _string="$2"
    local _delimiter="${3-,}"
    local _original_IFS="$IFS"
    eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
    IFS="$_original_IFS"
}

function _trim() {
    local _string="$1"
    echo "${_string}" | sed -e 's/^ *//g' -e 's/ *$//g'
}

function _escape() {
    local _str="$1"
    local _escape_single_quote="$2"
    
    if _isYes "$_escape_single_quote" ; then
        local _str2="$(_escape_quote "$_str")"
        echo "$_str2" | sed 's/[][()\.^$?*+\/|{}&]/\\&/g'
    else
        echo "$_str" | sed 's/[][()\.^$?*+\/|{}&"]/\\&/g'
    fi
}

function _escape_sed() {
    local _str="$1"
    local _escape_single_quote="$2"
    
    if _isYes "$_escape_single_quote" ; then
        local _str2="$(_escape_quote "$_str")"
        echo "$_str2" | sed "s/[][\.^$*\/&]/\\&/g"
    else
        echo "$_str" | sed 's/[][\.^$*\/"&]/\\&/g'
    fi
}

function _escape_double_quote() {
    local _str="$1"
    if [[ "$_str" =~ [^\\]\" ]]; then
        echo "$_str" | sed 's/"/\\"/g'
    else
        echo "$_str"
    fi
}

function _escape_quote() {
    local _str="$1"
    if [[ "$_str" =~ [^\\]\' ]]; then
        echo "$_str" | sed "s/'/\\\'/g"
    else
        echo "$_str"
    fi
}

###############################################################################
# Read command options (don't forget updating 'usage')
###############################################################################

while getopts "r:acmnh" opts; do
    case $opts in
        a)
            g_force_default=false
            ;;
        c)
            g_response_file="$g_default_response_file"
            ;;
        m)
            g_force_default=true
            ;;
        n)
            g_not_send_email=true
            ;;
        r)
            g_response_file="$OPTARG"
            ;;
        h)
            usage | less
            exit 0
    esac
done

###############################################################################
# Call main
###############################################################################

if [ "$0" = "$BASH_SOURCE" ]; then
    echo "
Welcome to Dev Server configurator.
"
    main
fi
