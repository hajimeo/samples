#!/bin/env bash
#
# DOWNLOAD the latest script
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/hwx_triage.sh
#
# Collection of functions to triage HDP related issues
# Tested on CentOS 6.6
# @author Hajime
#
# Each function should work individually
#

### Global variable ###################
[ -z "${g_AMBARI_USER}" ] && g_AMBARI_USER='admin'
[ -z "${g_AMBARI_PASS}" ] && g_AMBARI_PASS='admin'

_WORK_DIR="./hwx_triage"
_PID=""
_LOG_DIR=""
_LOG_DAY="1"
_FUNCTION_NAME=""
set -o posix


# Public functions
usage() {
    echo "This script is for collecting OS command outputs, and if PID is provided, collecting PID related information.

Example 1: Run one script (eg.: f_check_system)
    source ./hwx_triage.sh
    help f_check_system     # to see the help of this function
    f_check_system

Example 2: Collect Kafka PID related information
    $BASH_SOURCE -p \"\`cat /var/run/kafka/kafka.pid\`\"

Example 3: Collect Kafka PID related information with Kafka log (for past 1 day)
    $BASH_SOURCE -p \"\`cat /var/run/kafka/kafka.pid\`\" -l \"/var/log/kafka\" [-d 1]

Available options:
    -p PID     This PID will be checked
    -l PATH    A log directory path
    -d NUM     If -l is given, collect past x days of logs (default 1 day)
    -v         (TODO) Verbose mode
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
    local _work_dir="${1-$_WORK_DIR}"
    [ -z "$_work_dir" ] && _work_dir="."
    echo "INFO" "Collecting OS related information..." >&2

    # System information
    uname -a &> ${_work_dir%/}/uname-a.out
    systemd-analyze &> ${_work_dir%/}/systemd-analyze.out
    systemd-analyze blame &>> ${_work_dir%/}/systemd-analyze.out   # then disable and stop
    lsb_release -a &>> ${_work_dir%/}/uname-a.out
    localectl status &> ${_work_dir%/}/locale.out
    locale &>> ${_work_dir%/}/locale.out
    cat /proc/cpuinfo &> ${_work_dir%/}/cpuinfo.out
    cat /proc/meminfo &> ${_work_dir%/}/meminfo.out
    numactl -H &> ${_work_dir%/}/numa.out
    dmesg | grep 'link up' &> ${_work_dir%/}/dmesg_link_up.out
    getenforce &> ${_work_dir%/}/getenforce.out
    iptables -nvL --line-number &> ${_work_dir%/}/iptables.out
    iptables -t nat -nvL --line-number &>> ${_work_dir%/}/iptables.out
    timeout 3 time head -n 1 /dev/./urandom &> ${_work_dir%/}/random.out
    echo '-' &>> ${_work_dir%/}/random.out
    timeout 3 time head -n 1 /dev/random &>> ${_work_dir%/}/random.out
    lslocks -u > ${_work_dir%/}/lslocks.out    # *local* file system lock (/proc/locks)
    cat /sys/fs/cgroup/cpuset/cpuset.cpus &> ${_work_dir%/}/cpuset.cpus.out # for kubernetes pod / docker container

    #top -b -n1 -c -o +%MEM  # '+' (default) for reverse order (opposite of 'ps')
    top -b -n1 -c &>> ${_work_dir%/}/top.out
    #ps aux --sort uid,-vsz # '-' for reverse (opposite of 'top')
    ps auxwwwf &> ${_work_dir%/}/ps.out
    netstat -aopen || cat /proc/net/tcp &> ${_work_dir%/}/netstat.out
    mpstat -P ALL &> ${_work_dir%/}/top.out     # CPU stats (-P)

    # Name resolution
    nscd -g &> ${_work_dir%/}/nscd.out
    getent ahostsv4 `hostname -f` &> ${_work_dir%/}/getent_from_name.out
    getent hosts `hostname -I` &> ${_work_dir%/}/getent_from_ip.out
    python -c 'import socket as s;print s.gethostname();print s.gethostbyname(s.gethostname());print s.getfqdn()' &> ${_work_dir%/}/python_getfqdn.out

    # Disk
    # NOTE: with java https://confluence.atlassian.com/kb/test-disk-access-speed-for-a-java-application-818577561.html
    mount &> ${_work_dir%/}/mount_df.out    # findmnt -T /path for specific location's mount options
    df -Th &> ${_work_dir%/}/mount_df.out
    grep -wE "(nfs|nfs4)" /proc/mounts > mounts_nfs.out # to check NFS version
    vmstat 1 3 &> ${_work_dir%/}/vmstat.out &
    iostat -x -p -t 1 3 2>/dev/null || vmstat -d 1 3 &> ${_work_dir%/}/iostat.out &
    pidstat -dl 3 3 &> ${_work_dir%/}/pstat.out &   # current disk stats per PID
    #sar -uqrbd -p -s 09:00:00 -e 12:00:00 -f /var/log/sysstat/sa26
    sar -uqrbd -p &> ${_work_dir%/}/sar_qrbd.out # if no -p, ls -l /dev/sd*
    #ioping -c 12 . # check latency on current dir 12 times.
    #ioping -RL /dev/sda1

    # NFS related
    showmount -e `hostname` &> ${_work_dir%/}/nfs.out
    #rpcinfo -s &>> ${_work_dir%/}/nfs.out              # list NFS summary information (for rpcbind)
    rpcinfo -p `hostname` &>> ${_work_dir%/}/nfs.out    # list NFS versions, ports, services but a bit too long
    nfsstat -v &>> ${_work_dir%/}/nfs.out               # -v = -o all Display Server and Client stats

    # Network
    ifconfig 2>/dev/null || ip address &> ${_work_dir%/}/ifconfig.out
    netstat -s &> ${_work_dir%/}/netstat_s.out
    cat /proc/net/dev &> ${_work_dir%/}/net_dev.out

    # Misc.
    #sysctl kernel.pid_max fs.file-max fs.file-nr # max is OS limit (Too many open files)
    sysctl -a &> ${_work_dir%/}/sysctl.out
    #sar -A &> ${_work_dir%/}/sar_A.out
    env &> ${_work_dir%/}/env.out  # to check PATH, LD_LIBRARY_PATH, JAVA_HOME, CLASSPATH
    wait
}

function f_check_process() {
    local __doc__="Execute PID related commands (jstack, jstat, jmap)"
    local _p="$1"	# Java PID ex: `cat /var/run/kafka/kafka.pid`
    local _work_dir="${2-$_WORK_DIR}"
    [ -z "$_work_dir" ] && _work_dir="."

    if [ -z "$_p" ]; then
        echo "ERROR" "No PID" >&2; return 1
    fi

    local _user="`stat -c '%U' /proc/${_p}`"
    local _cmd_dir="$(dirname `readlink /proc/${_p}/exe` 2>/dev/null)"
    # In case, java is JRE, use JAVA_HOME
    if [ ! -x "${_cmd_dir}/jstack" ] && [ -d "$JAVA_HOME" ]; then
        _cmd_dir="$JAVA_HOME/bin" 2>/dev/null
    fi

    echo "INFO" "Collecting PID (${_p}) related information..." >&2
    su - $_user -c 'klist -eaf' &> ${_work_dir%/}/klist_${_user}.out
    #lslocks -u -p ${_p} > ${_work_dir%/}/lslocks_${_p}.out # not using as it's used in the f_check_system

    if which prlimit &>/dev/null; then
        prlimit -p ${_p} &> ${_work_dir%/}/proc_limits_${_p}.out
    else
        cat /proc/${_p}/limits &> ${_work_dir%/}/proc_limits_${_p}.out
    fi
    cat /proc/${_p}/status &> ${_work_dir%/}/proc_status_${_p}.out
    date > ${_work_dir%/}/proc_io_${_p}.out; cat /proc/${_p}/io >> ${_work_dir%/}/proc_io_${_p}.out
    cat /proc/${_p}/environ | tr '\0' '\n' > ${_work_dir%/}/proc_environ_${_p}.out
    # https://gist.github.com/jkstill/5095725
    cat /proc/${_p}/net/tcp > ${_work_dir%/}/net_tcp_${_p}.out
    lsof -nPp ${_p} &> ${_work_dir%/}/lsof_${_p}.out

    if [ -d "$_cmd_dir" ]; then
        local _java_home="$(dirname $_cmd_dir)"
        zipgrep CryptoAllPermission "$_java_home/jre/lib/security/local_policy.jar" &> ${_work_dir%/}/jce_${_p}.out
        grep "^securerandom.source=" "$_java_home/jre/lib/security/java.security" &> ${_work_dir%/}/java_random_${_p}.out

        # NO heap dump at this moment
        local _pre_cmd=""
        which timeout &>/dev/null && _pre_cmd="timeout 12"
        [ -x "${_cmd_dir}/jmap" ] && $_pre_cmd sudo -u ${_user} ${_cmd_dir}/jmap -histo ${_p} &> ${_work_dir%/}/jmap_histo_${_p}.out
        # 'ps' with -L (or -T) does not work with -p <pid>. For MacOS, htop then F5?
        #ps -eLo user,pid,lwp,nlwp,ruser,pcpu,stime,etime,comm | grep -w "${_p}" &> ${_work_dir%/}/pseLo_${_p}.out (Mac
        top -H -b -n 3 -d 3 -p ${_p} &> ${_work_dir%/}/top_${_p}.out &    # printf "%x\n" [PID]
        #ls -l /proc/<PID>/task/<tid>/fd    # to check which Linux thread opens which files
        [ -x "${_cmd_dir}/jstack" ] && for i in {1..3};do $_pre_cmd sudo -u ${_user} ${_cmd_dir}/jstack -l ${_p}; sleep 3; done &> ${_work_dir%/}/jstack_${_p}.out &
        #$_pre_cmd pstack ${_p} &> ${_work_dir%/}/pstack_${_p}.out &    # if jstack or jstack -F doesn't work
        [ -x "${_cmd_dir}/jstat" ] && $_pre_cmd sudo -u ${_user} ${_cmd_dir}/jstat -gccause ${_p} 1000 9 &> ${_work_dir%/}/jstat_${_p}.out &
    fi

    pmap -x ${_p} &> ${_work_dir%/}/pmap_${_p}.out
    wait
    date >> ${_work_dir%/}/proc_io_${_p}.out; cat /proc/${_p}/io >> ${_work_dir%/}/proc_io_${_p}.out
}

function f_collect_config() {
    local __doc__="Collect HDP all config files and generate tgz file"
    local _work_dir="${1-$_WORK_DIR}"
    [ -z "$_work_dir" ] && _work_dir="."

    echo "INFO" "Collecting HDP config files ..." >&2
    # no 'v' at this moment
    tar czhf ${_work_dir%/}/hdp_all_conf_$(hostname)_$(date +"%Y%m%d%H%M%S").tgz /usr/hdp/current/*/conf /etc/{ams,ambari}-* /etc/ranger/*/policycache /etc/hosts /etc/krb5.conf 2>/dev/null
}

function f_collect_log_files() {
    local __doc__="Collect log files for past x days (default is 1 day) and generate tgz file"
    local _path="$1"
    local _day="${2-1}"
    local _work_dir="${3-$_WORK_DIR}"
    [ -z "$_work_dir" ] && _work_dir="."

    if [ -z "$_path" ] || [ ! -d "$_path" ]; then
        echo "ERROR" "$_path is not a directory" >&2; return 1
    fi

    echo "INFO" "Collecting log files under ${_path} for past ${_day} day(s) ..." >&2

    tar czhf ${_work_dir%/}/hdp_log_$(hostname)_$(date +"%Y%m%d%H%M%S").tar.gz `find -L "${_path}" -type f -mtime -${_day}` 2>&1 | grep -v 'Removing leading'
    # grep -i "killed process" /var/log/messages* # TODO: should we also check OOM Killer?
}

function f_collect_webui() {
    local __doc__="TODO: Collect Web UI with wget"
    local _url="$1"
    local _work_dir="${2-$_WORK_DIR}"
    [ -z "$_work_dir" ] && _work_dir="."

    if ! which wget &>/dev/null ; then
        echo "ERROR" "No wget in the PATH." >&2; return 1
    fi

    local _d="collect_webui"
    mkdir ${_work_dir%/}/$_d
    wget -r -P${_work_dir%/}/$_d -X logs -l 3 -t 1 -k --restrict-file-names=windows -E --no-check-certificate -o ${_work_dir%/}/$_d/collect_webui_wget.log "$_url"
}

function f_collect_host_info_from_ambari() {
    local __doc__="Access to Ambari API to get the host (and component) information"
    local _node="${1}"              # node name = hostname
    local _comp="${2}"              # host_component eg: DATANODE, HBASE_REGIONSERVER
    local _fields="${3}"            # metric field filter eg: "metrics/cpu/cpu_idle._sum,metrics/cpu/cpu_idle._avg"
    local _date_start_string="$4"   # default: "1 hour ago"
    local _date_end_string="$5"     # default: "now"
    local _ambari_url="$6"          # http://hostname:8080/
    local _work_dir="$_WORK_DIR"
    local _admin="${g_AMBARI_USER-admin}"
    local _pass="${g_AMBARI_PASS}"

    local _cmd_opts="-s -k -u ${_admin}"
    [ -z "${_pass}" ] && read -p "Enter password for user '${_admin}': " -s "_pass"
    echo ""
    [ -n "${_pass}" ] && _cmd_opts="${_cmd_opts}:${_pass}"
    [ -z "$_node" ] && _node="`hostname -f`"
    [ -z "$_date_start_string" ] && _date_start_string="1 hour ago"
    [ -z "$_date_end_string" ] && _date_end_string="now"
    [ -z "$_work_dir" ] && _work_dir="."
    [ -z "${_ambari_url}" ] && _ambari_url="http://`hostname -f`:8080/"
    echo "INFO" "Collecting ${_node} information from Ambari..." >&2

    # generating base url from href entry from clusters API response
    local _href="`curl ${_cmd_opts} ${_ambari_url%/}/api/v1/clusters/ | grep -oE 'http://.+/clusters/[^"/]+'`"
    if [ -z "$_href" ]; then
        echo "ERROR" "No href from ${_ambari_url%/}/api/v1/clusters/" >&2
        return 2
    fi

    # Looks like Ambari 2.5.x doesn't care the case (lower or upper or mix) for hostname
    if [ -z "${_fields}" ]; then
        curl ${_cmd_opts} "${_href}/hosts/${_node}" -o ${_work_dir%/}/ambari_${_node}.json || return $?
    else
        curl ${_cmd_opts} "${_href}/hosts/${_node}?fields=${_fields}" -o ${_work_dir%/}/ambari_${_node}.json || return $?
    fi

    # If no python, not collecting detailed metrics at this moment
    which python >/dev/null || return $?

    local _S="`date '+%s' -d"${_date_start_string}"`" || return $?
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

    echo "INFO" "Collecting ${_node} metric from Ambari..." >&2
    local _fields_with_time="`cat ${_work_dir%/}/ambari_${_node}.json | python -c "${_script}"`"
    [ -n "${_fields_with_time}" ] && curl ${_cmd_opts} "${_href}/hosts/${_node}" -G --data-urlencode "fields=${_fields_with_time}" -o ${_work_dir%/}/ambari_${_node}_metrics.json

    if [ ! -z "$_comp" ]; then
        echo "INFO" "Collecting ${_node} ${_comp} metric from Ambari..." >&2
        curl ${_cmd_opts} "${_href}/hosts/${_node}/host_components/${_comp^^}" -G --data-urlencode "fields=${_fields_with_time}" -o ${_work_dir%/}/ambari_${_node}_${_comp}_metrics.json
    fi
}

function f_collect_comp_metrics_from_ambari() {
    local __doc__="Access to Ambari API to get particular metrics (so far no node level metrics)"
    local _serv="${1}"             # service eg: YARN, HDFS
    local _comp="${2}"             # eg: DATANODE, HBASE_REGIONSERVER
    local _fields="${3}"           # eg: "metrics/cpu/cpu_idle._sum,metrics/cpu/cpu_idle._avg"
    local _date_start_string="$4"  # default: "1 hour ago"
    local _date_end_string="$5"    # default: "now"
    local _ambari_url="$6"         # http://hostname:8080/
    local _work_dir="$_WORK_DIR"
    local _admin="${g_AMBARI_USER-admin}"
    local _pass="${g_AMBARI_PASS}"

    local _cmd_opts="-s -k -u ${_admin}"
    [ -z "${_pass}" ] && read -p "Enter password for user '${_admin}': " -s "_pass"
    echo ""
    [ -n "${_pass}" ] && _cmd_opts="${_cmd_opts}:${_pass}"
    [ -z "$_date_start_string" ] && _date_start_string="1 hour ago"
    [ -z "$_date_end_string" ] && _date_end_string="now"
    [ -z "$_work_dir" ] && _work_dir="."
    [ -z "${_ambari_url}" ] && _ambari_url="http://`hostname -f`:8080/"

    [ -z "${_serv}" ] && return 1
    [ -z "${_comp}" ] && return 1

    local _href="`curl ${_cmd_opts} ${_ambari_url%/}/api/v1/clusters/ | grep -oE 'http://.+/clusters/[^"/]+'`"
    if [ -z "$_href" ]; then
        echo "ERROR" "No href from ${_ambari_url%/}/api/v1/clusters/" >&2
        return 2
    fi

    # For this function, python is mandatory
    which python >/dev/null || return $?

    local _tmp_fields=$(echo "${_fields}" | sed -e 's/[^A-Za-z0-9._-]//g')
    # For speed up, if file exists, reuse it
    if [ ! -s "/tmp/ambari_${_comp}_${_tmp_fields}.json" ]; then
        if [ -z "${_fields}" ]; then
            _tmp_fields="all-fields"
            curl ${_cmd_opts} "${_href}/services/${_serv^^}/components/${_comp^^}" -o /tmp/ambari_${_comp}_${_tmp_fields}.json || return $?
        else
            curl ${_cmd_opts} "${_href}/services/${_serv^^}/components/${_comp^^}" -G --data-urlencode "fields=${_fields}" -o /tmp/ambari_${_comp}_${_tmp_fields}.json || return $?
        fi
    fi

    local _S="`date '+%s' -d"${_date_start_string}"`" || return $?
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

    _fields="`cat /tmp/ambari_${_comp}_${_tmp_fields}.json | python -c "${_script}"`"
    if [ -z "$_fields" ]; then
        echo "WARN" "Couldn't determine fields. Please check /tmp/ambari_${_comp}_${_tmp_fields}.json if exists." >&2
        return 11
    fi

    echo "INFO" "Collecting ${_serv} / ${_comp} metric from Ambari..." >&2
    curl ${_cmd_opts} "${_href}/services/${_serv^^}/components/${_comp^^}" -G --data-urlencode "fields=${_fields}" -o ${_work_dir%/}/ambari_${_comp}_metrics.json
}

function f_collect_comp_metrics_from_AMS() {
    local __doc__="Access to AMS API to get particular metrics (so far no node level metrics)"
    local _comp="${1}"              # component eg: DATANODE, HBASE_REGIONSERVER
    local _metric_names="${2}"      # eg: "cpu%"
    local _extra="${3}"             # eg: "precision=MINUTES&hostname=%"
    local _date_start_string="$4"   # eg & default: "1 hour ago"
    local _date_end_string="$5"     # eg & default: "now"
    local _ams_url="$6"             # eg & default: http://`hostname -f`:6188 (running from AMS node)
    local _work_dir="$_WORK_DIR"

    local _cmd_opts="-s -k"
    [ -z "$_date_start_string" ] && _date_start_string="1 hour ago"
    [ -z "$_date_end_string" ] && _date_end_string="now"
    [ -z "$_work_dir" ] && _work_dir="."
    [ -z "${_comp}" ] && return 1
    [ -z "${_precision}" ] && _precision="MINUTES"
    [ -z "${_ams_url}" ] && _ams_url="http://`hostname -f`:6188"
    local _base_url="${_ams_url%/}/ws/v1/timeline/metrics"
    # Seems AMS works with second and millisecond both
    local _S="`date '+%s' -d"${_date_start_string}"`" || return $?
    local _E="`date '+%s' -d"${_date_end_string}"`"

    echo "INFO" "Collecting ${_comp^^} metric from AMS (${_ams_url}) ..." >&2
    if [ -z "$_metric_names" ]; then
        echo "ERROR" "No metric names (eg: cpu%)" >&2
        return 11
    fi

    [ -n "${_extra}" ] && _base_url="${_base_url}?${_extra}"
    curl ${_cmd_opts} "${_base_url}" -G --data-urlencode "metricNames=${_metric_names}" --data-urlencode "appId=${_comp^^}" --data-urlencode "startTime=${_S}" --data-urlencode "endTime=${_E}" -o ${_work_dir%/}/ams_${_comp}_metrics.json || return $?
    cat ${_work_dir%/}/ams_${_comp}_metrics.json | python -m json.tool > /tmp/ams_${_comp}_metrics.json || return $?
    mv -f /tmp/ams_${_comp}_metrics.json ${_work_dir%/}/ams_${_comp}_metrics.json
}

function f_write_permission_test() {    # for 'Permission denied'
    local _file="$1"
    jrunscript -e 'var f=new java.io.FileWriter("'${_file}'");f.write("OK\n");f.close();'
    rm -v "${_file}"
}

#function f_test_network() {
#    local __doc__="TODO: Test network speed/error"
#}

function f_tar_work_dir() {
    local __doc__="Create tgz file from work dir and cleanup work dir if hwx_triage"
    local _tar_file_path="$1"
    local _work_dir="${2-$_WORK_DIR}"

    if [ -z "$_tar_file_path" ]; then
        _tar_file_path="./hwx_triage_$(hostname)_$(date +"%Y%m%d%H%M%S").tgz"
    fi

    if [ -z "${_work_dir%/}" ] || [ ! -d "$_work_dir" ]; then
        echo "ERROR" "${_work_dir} is not a good directory to tar" >&2
        return 1
    fi

    echo "INFO" "Creating ${_tar_file_path} file ..." >&2

    if [ "${_work_dir}" = "./hwx_triage" ]; then
        tar --remove-files -czf ${_tar_file_path} ${_work_dir%/}/* 2>&1 | grep -v 'Removing leading'
    else
        tar -czf ${_tar_file_path} ${_work_dir%/}/* 2>&1 | grep -v 'Removing leading'
    fi
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
    if [ -n "${_LOG_FILE_PATH}" ]; then
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" | tee -a ${_LOG_FILE_PATH} 1>&2
    else
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $@" 1>&2
    fi
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
