#!/bin/env bash
#
# Collection of functions to triage HDP related issues
# Tested on CentOS 6.6
# @author Hajime
#
# Each function should work individually
#

# GLOBAL variables
_WORK_DIR="./hwx_triage"
_PID=""
_LOG_DIR=""
_LOG_DAY="1"
_FUNCTION_NAME=""
set -o posix


# Public functions
usage() {
    echo "This script is for collecting OS command outputs, and if PID is provided, collecting PID related information.

Example 1: Collect Kafka PID related information
    $BASH_SOURCE -p \"\`cat /var/run/kafka/kafka.pid\`\"

Example 2: Collect Kafka PID related information with Kafka log (for past 1 day)
    $BASH_SOURCE -p \"\`cat /var/run/kafka/kafka.pid\`\" -l \"/var/log/kafka\" [-d 1]

Available options:
    -p PID     This PID will be checked
    -l PATH    A log directory path
    -d NUM     If -l is given, collect past x days of logs (default 1 day)
    -v         Verbose mode
    -h         Show this message

Available functions:
"
_list
echo "
Get more help for a function
    $BASH_SOURCE -f <functionname>
"
}

function f_check_system() {
    local __doc__="Execute OS commands for performance issue"
    [ -z "$_WORK_DIR" ] && _WORK_DIR="."
    echo "INFO" "Collecting OS related information..." >&2

    uname -a &> ${_WORK_DIR%/}/uname-a.out
    hdp-select &> ${_WORK_DIR%/}/hdp-select.out
    ls -l /usr/hdp/current/ &>> ${_WORK_DIR%/}/hdp-select.out
    ls -l /etc/security/keytabs/ &> ${_WORK_DIR%/}/ls-keytabs.out
    getenforce &> ${_WORK_DIR%/}/getenforce.out
    iptables -t nat -L &> ${_WORK_DIR%/}/iptables.out
    (which timeout && (timeout 3 time head -n 1 /dev/urandom > /dev/null;echo '-';timeout 3 time head -n 1 /dev/random > /dev/null)) &> ${_WORK_DIR%/}/random.out
    vmstat 1 3 &> ${_WORK_DIR%/}/vmstat.out &
    vmstat -d &> ${_WORK_DIR%/}/vmstat_d.out &
    pidstat -dl 3 3 &> ${_WORK_DIR%/}/pstat.out &
    sysctl -a &> ${_WORK_DIR%/}/sysctl.out
    top -b -n 1 -c &> ${_WORK_DIR%/}/top.out
    ps auxwwwf &> ${_WORK_DIR%/}/ps.out
    netstat -aopen &> ${_WORK_DIR%/}/netstat.out
    netstat -s &> ${_WORK_DIR%/}/netstat_s.out
    ifconfig &> ${_WORK_DIR%/}/ifconfig.out
    nscd -g &> ${_WORK_DIR%/}/nscd.out
    getent ahostsv4 `hostname -f` &> ${_WORK_DIR%/}/getent_from_name.out
    getent hosts `hostname -I` &> ${_WORK_DIR%/}/getent_from_ip.out
    python -c 'import socket;print socket.getfqdn()' &> ${_WORK_DIR%/}/python_getfqdn.out
    mount &> ${_WORK_DIR%/}/mount_df.out
    df -h &> ${_WORK_DIR%/}/mount_df.out
    sar -qrbd &> ${_WORK_DIR%/}/sar_qrbd.out
    cat /proc/net/dev &> ${_WORK_DIR%/}/net_dev.out
    cat /proc/cpuinfo &> ${_WORK_DIR%/}/cpuinfo.out
    cat /proc/meminfo &> ${_WORK_DIR%/}/meminfo.out
    wait
}

function f_check_process() {
    local __doc__="Execute PID related commands (jstack, jstat, jmap)"
    local _p="$1"	# Java PID ex: `cat /var/run/kafka/kafka.pid`
    [ -z "$_WORK_DIR" ] && _WORK_DIR="."

    if [ -z "$_p" ]; then
        echo "ERROR" "No PID" >&2; return 1
    fi

    local _user="`stat -c '%U' /proc/${_p}`"
    local _cmd_dir="$(dirname `readlink /proc/${_p}/exe`)" 2>/dev/null
    # In case, java is JRE, use JAVA_HOME
    if [ ! -x "${_cmd_dir}/jstack" ] && [ -d "$JAVA_HOME" ]; then
        _cmd_dir="$JAVA_HOME/bin" 2>/dev/null
    fi

    echo "INFO" "Collecting PID related information..." >&2
    su - $_user -c 'klist -eaf' &> ${_WORK_DIR%/}/klist_${_user}.out

    cat /proc/${_p}/limits &> ${_WORK_DIR%/}/proc_limits_${_p}.out
    cat /proc/${_p}/status &> ${_WORK_DIR%/}/proc_status_${_p}.out
    date > ${_WORK_DIR%/}/proc_io_${_p}.out; cat /proc/${_p}/io >> ${_WORK_DIR%/}/proc_io_${_p}.out
    cat /proc/${_p}/environ | tr '\0' '\n' > ${_WORK_DIR%/}/proc_environ_${_p}.out
    lsof -nPp ${_p} &> ${_WORK_DIR%/}/lsof_${_p}.out

    if [ -d "$_cmd_dir" ]; then
        local _java_home="$(dirname $_cmd_dir)"
        zipgrep CryptoAllPermission "$_java_home/jre/lib/security/local_policy.jar" &> ${_WORK_DIR%/}/jce_${_p}.out
        grep "^securerandom.source=" "$_java_home/jre/lib/security/java.security" &> ${_WORK_DIR%/}/java_random_${_p}.out

        # NO heap dump at this moment
        [ -x "${_cmd_dir}/jmap" ] && sudo -u ${_user} ${_cmd_dir}/jmap -histo ${_p} &> ${_WORK_DIR%/}/jmap_histo_${_p}.out
        top -Hb -n 3 -d 3 -p ${_p} &> ${_WORK_DIR%/}/top_${_p}.out &    # printf "%x\n" [PID]
        [ -x "${_cmd_dir}/jstack" ] && for i in {1..3};do sudo -u ${_user} ${_cmd_dir}/jstack -l ${_p}; sleep 3; done &> ${_WORK_DIR%/}/jstack_${_p}.out &
        [ -x "${_cmd_dir}/jstat" ] && sudo -u ${_user} ${_cmd_dir}/jstat -gccause ${_p} 1000 9 &> ${_WORK_DIR%/}/jstat_${_p}.out &
    fi

    #ps -eLo user,pid,lwp,nlwp,ruser,pcpu,stime,etime,args | grep -w "${_p}" &> ${_WORK_DIR%/}/pseLo_${_p}.out
    pmap -x ${_p} &> ${_WORK_DIR%/}/pmap_${_p}.out
    wait
    date >> ${_WORK_DIR%/}/proc_io_${_p}.out; cat /proc/${_p}/io >> ${_WORK_DIR%/}/proc_io_${_p}.out
}

function f_collect_config() {
    local __doc__="Collect HDP all config files and generate tgz file"
    [ -z "$_WORK_DIR" ] && _WORK_DIR="."

    echo "INFO" "Collecting HDP config files ..." >&2
    # no 'v' at this moment
    tar czhf ${_WORK_DIR%/}/hdp_all_conf_$(hostname)_$(date +"%Y%m%d%H%M%S").tgz /usr/hdp/current/*/conf /etc/{ams,ambari}-* /etc/ranger/*/policycache /etc/hosts /etc/krb5.conf 2>/dev/null
}

function f_collect_log_files() {
    local __doc__="Collect log files for past x days (default is 1 day) and generate tgz file"
    local _path="$1"
    local _day="${2-1}"
    [ -z "$_WORK_DIR" ] && _WORK_DIR="."

    if [ -z "$_path" ] || [ ! -d "$_path" ]; then
        echo "ERROR" "$_path is not a directory" >&2; return 1
    fi

    echo "INFO" "Collecting log files under ${_path} for past ${_day} day(s) ..." >&2

    tar czhf ${_WORK_DIR%/}/hdp_log_$(hostname).tar.gz `find -L "${_path}" -type f -mtime -${_day}` 2>&1 | grep -v 'Removing leading'
    # grep -i "killed process" /var/log/messages* # TODO: should we also check OOM Killer?
}

function f_collect_webui() {
    local __doc__="TODO: Collect Web UI with wget"
    local _url="$1"
    [ -z "$_WORK_DIR" ] && _WORK_DIR="."

    if ! which wget &>/dev/null ; then
        echo "ERROR" "No wget in the PATH." >&2; return 1
    fi

    local _d="collect_webui"
    mkdir ${_WORK_DIR%/}/$_d
    wget -r -P${_WORK_DIR%/}/$_d -X logs -l 3 -t 1 -k --restrict-file-names=windows -E --no-check-certificate -o ${_WORK_DIR%/}/$_d/collect_webui_wget.log "$_url"
}

function f_collect_host_info_from_ambari() {
    local __doc__="Access to Ambari API to get the host (and component) information"
    local _admin="${1-admin}"      # Ambari Admin username
    local _admin_pass="$2"         # If no password, each curl command will ask you to type
    local _comp="${3}"             # host_component eg: DATANODE, HBASE_REGIONSERVER
    local _node="${4}"             # node name = hostname
    local _date_start_string="$5"  # eg: "4 hours ago"
    local _date_end_string="$6"    # eg: "now" (or blank = now)
    local _protocol="${7-http}"    # if https, change to https
    local _ambari_port="${8-8080}" # if no default port

    local _cmd_opts="-s -k -u ${_admin}"
    [ -z "${_admin_pass}" ] || _cmd_opts="${_cmd_opts}:${_admin_pass}"
    [ -z "$_node" ] && _node="`hostname -f`"
    [ -z "$_date_start_string" ] && _date_start_string="4 hours ago"
    [ -z "$_date_end_string" ] && _date_end_string="now"
    [ -z "$_protocol" ] && _protocol="http"
    [ -z "$_ambari_port" ] && _ambari_port="8080"
    [ -z "$_WORK_DIR" ] && _WORK_DIR="."
    echo "INFO" "Collecting this host information from Ambari..." >&2

    local _ambari="`grep '^hostname=' /etc/ambari-agent/conf/ambari-agent.ini | cut -d= -f2`"
    if [ -z "$_ambari" ]; then
        echo "ERROR" "No hostname= in ambari-agent.ini" >&2
        return 1
    fi

    local _href="`curl ${_cmd_opts} ${_protocol}://${_ambari}:${_ambari_port}/api/v1/clusters/ | grep -oE 'http://.+/clusters/[^"/]+'`"
    if [ -z "$_href" ]; then
        echo "ERROR" "No href from ${_protocol}://${_ambari}:${_ambari_port}/api/v1/clusters/" >&2
        return 2
    fi

    # Looks like Ambari 2.5.x doesn't care of the case (lower or upper or mix) for hostname
    curl ${_cmd_opts} "${_href}/hosts/${_node}" -o ${_WORK_DIR%/}/ambari_${_node}.json

    # If no python, not collecting detailed metrics at this moment
    which python &>/dev/null || return

    local _S="`date '+%s' -d"${_date_start_string}"`"
    local _E="`date '+%s' -d"${_date_end_string}"`"
    local _s="15"
    local _script="import sys,json
a=json.loads(sys.stdin.read())
r=[]
for k,v in a['metrics'].iteritems():
  if isinstance(v,dict):
    for k2 in v:
      r+=['metrics/%s/%s["${_S}","${_E}","${_s}"]' % (k, k2)]
print ','.join(r)"

    local _fields="`cat ${_WORK_DIR%/}/ambari_${_node}.json | python -c "${_script}"`"
    [ -z "$_fields" ] || curl ${_cmd_opts} "${_href}/hosts/${_node}" -G --data-urlencode "fields=${_fields}" -o ${_WORK_DIR%/}/ambari_${_node}_metrics.json

    if [ ! -z "$_comp" ]; then
        curl ${_cmd_opts} "${_href}/hosts/${_node}/host_components/${_comp^^}" -o ${_WORK_DIR%/}/ambari_${_node}_${_comp}.json
        _fields="`cat ${_WORK_DIR%/}/ambari_${_node}_${_comp}.json | python -c "${_script}"`"
        [ -z "$_fields" ] || curl ${_cmd_opts} "${_href}/hosts/${_node}/host_components/${_comp^^}" -G --data-urlencode "fields=${_fields}" -o ${_WORK_DIR%/}/ambari_${_node}_${_comp}_metrics.json
    fi
}

#function f_test_network() {
#    local __doc__="TODO: Test network speed/error"
#}

function f_tar_work_dir() {
    local __doc__="Create tgz file from work dir and remove work dir"
    local _file_path="$1"

    if [ -z "$_file_path" ]; then
        _file_path="./hdp_triage_$(hostname)_$(date +"%Y%m%d%H%M%S").tgz"
    fi

    echo "INFO" "Creating ${_file_path} file ..." >&2

    tar --remove-files -czf ${_file_path} ${_WORK_DIR%/}/* 2>&1 | grep -v 'Removing leading'
}



help() {
    local _function_name="$1"
    local _doc_only="$2"

    if [ -z "$_function_name" ]; then
        usage; return
    fi

    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            echo "ERROR" "Function name '$_function_name' does not exist." >&2; return 1
        fi

        local _eval="$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        eval "$_eval"

        if [ -z "$__doc__" ]; then
            echo "INFO" "No help information in function name '$_function_name'." >&2
        else
            echo -e "$__doc__"
            [[ "$_doc_only" =~ (^y|^Y) ]] && return
        fi

        local _params="$(type $_function_name 2>/dev/null | grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | grep -v awk)"
        if [ -n "$_params" ]; then
            echo "Parameters:"
            echo -e "$_params
            "
        fi
        echo -e "${_code}"
    else
        echo "ERROR" "Unsupported Function name '$_function_name'." >&2; return 1
    fi
}

# (supposed to be) private functions

function _log() {
    # At this moment, outputting to STDERR
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" >&2
}

function _workdir() {
    local _work_dir="${1-$_WORK_DIR}"

    [ -z "${_work_dir}" ] && _work_dir="./${FUNCNAME}_$$"

    if [ ! -d "$_work_dir" ] && ! mkdir $_work_dir; then
        echo "ERROR" "Couldn't create $_work_dir directory" >&2; return 1
    fi

    if [ ! -w "$_work_dir" ]; then
        echo "ERROR" "Couldn't write $_work_dir directory" >&2; return 1
    fi

    _WORK_DIR="${_work_dir}"
}

function _list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | grep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "Y"`"
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


# Main
if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "p:l:d:f:h" opts; do
        case $opts in
            p)
                _PID="$OPTARG"
                ;;
            l)
                _LOG_DIR="$OPTARG"
                ;;
            d)
                _LOG_DAY="$OPTARG"
                ;;
            f)
                _FUNCTION_NAME="$OPTARG"
                ;;
            h)
                help | less
                exit 0
        esac
    done

    if [ -n "$_FUNCTION_NAME" ]; then
        help "$_FUNCTION_NAME" | less
        exit
    fi

    # validation
    if [ "$USER" != "root" ]; then
        echo "ERROR" "Please run as 'root' user" >&2
        exit 1
    fi

    _workdir
    f_check_system
    if [ -n "$_PID" ]; then
        f_check_process "$_PID"
    fi
    f_collect_config
    if [ -n "$_LOG_DIR" ]; then
        f_collect_log_files "$_LOG_DIR" "$_LOG_DAY"
    fi
    f_tar_work_dir
    echo "INFO" "Completed!" >&2
fi