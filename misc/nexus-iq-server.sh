#!/usr/bin/env bash
# From https://help.sonatype.com/iqserver/installing/running-iq-server-as-a-service

# The following comment lines are used by the init setup script like the
# chkconfig command for RedHat based distributions. Change as
# appropriate for your installation.

### BEGIN INIT INFO
# Provides:          nexus-iq-server
# Required-Start:    $local_fs $remote_fs $network $time $named
# Required-Stop:     $local_fs $remote_fs $network $time $named
# Default-Start:     3 5
# Default-Stop:      0 1 2 6
# Short-Description: nexus-iq-server service
# Description:       Start the nexus-iq-server service
### END INIT INFO

### BEGIN Variables (change to fit your configuration)
# Make sure those directories exist and owned by "RUN_AS_USER"
NEXUS_IQ_SERVER_HOME="$(dirname -- "${BASH_SOURCE[0]}")/nexusiq"
RUN_AS_USER="${USER}"
### END Variables

SUDO=""
[ "x${RUN_AS_USER}" != "x${USER}" ] && SUDO="sudo -u ${RUN_AS_USER}"

JAVA="java"
# If JAVA_HOME is specified, use it.
[ -n "${JAVA_HOME}" ] && JAVA="${JAVA_HOME%/}/bin/java"

# Minimum recommended options (but not using -XX:-OmitStackTraceInFastThrow as this is for my test server)
JAVA_OPTIONS="-Xms${_NXIQ_HEAPSIZE:-"2G"} -Xmx${_NXIQ_HEAPSIZE:-"2G"} -XX:ActiveProcessorCount=2"
# For kill -3 (too see the stdout, use journalctl _PID=<PID>). Also jvm_%p.log works too
JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+UnlockDiagnosticVMOptions -XX:+LogVMOutput -XX:LogFile=${NEXUS_IQ_SERVER_HOME}/log/jvm.log"
# GC log related options are different by Java version.
if ${JAVA} -XX:+PrintFlagsFinal -version 2>&1 | grep -q GCLogFileSize; then
    # probably java 8 (-verbose:gc = -XX:+PrintGC)
    JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+UseG1GC -XX:+ExplicitGCInvokesConcurrent -XX:+PrintGCApplicationStoppedTime -XX:+TraceClassLoading -XX:+TraceClassUnloading"
    # https://confluence.atlassian.com/confkb/how-to-enable-garbage-collection-gc-logging-300813751.html
    # -XX:+PrintTenuringDistribution -XX:+PrintClassHistogramBeforeFullGC
    JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCCause -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M -Xloggc:${NEXUS_IQ_SERVER_HOME}/log/gc.%t.log -XX:+PrintClassHistogramAfterFullGC"
else
    # Java 11 / 17 (@see: https://docs.oracle.com/en/java/java-components/enterprise-performance-pack/epp-user-guide/printing-jvm-information.html)
    # https://docs.azul.com/prime/Unified-GC-Logging
    #JAVA_OPTIONS="${JAVA_OPTIONS} -Xlog:gc*,classhisto*=trace:file=${NEXUS_IQ_SERVER_HOME}/log/gc.%t.log:time,uptime:filecount=10,filesize=100m"
    JAVA_OPTIONS="${JAVA_OPTIONS} -Xlog:gc*,safepoint:file=${NEXUS_IQ_SERVER_HOME}/log/gc.%t.log:time,uptime:filecount=10,filesize=100m"
fi
JAVA_OPTIONS="${JAVA_OPTIONS} -XX:MaxDirectMemorySize=1g -Djdk.nio.maxCachedBufferSize=262144"  # probably bytes
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:OnOutOfMemoryError='kill %p'"    # Or -XX:+ExitOnOutOfMemoryError, but no need because of https://help.sonatype.com/en/iq-server-installation.html#automatic-shutdown-on-errors
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:OnOutOfMemoryError='kill -3 %p'"  # TODO: May not work with IQ
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+CrashOnOutOfMemoryError -XX:ErrorFile=${NEXUS_IQ_SERVER_HOME}/log"  # TODO: May not work with IQ
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${NEXUS_IQ_SERVER_HOME}/log"    # or 'user.dir' (cwd) if not specified
#JAVA_OPTIONS="${JAVA_OPTIONS} -Xdump:system:label=${NEXUS_IQ_SERVER_HOME}/log/core.%Y%m%d.%H%M%S.%pid.dmp"     # or 'user.dir' (cwd) if not specified
#JAVA_OPTIONS="${JAVA_OPTIONS} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=6786 -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"
# for testing
#JAVA_OPTIONS="${JAVA_OPTIONS} -Dinsight.threads.monitor=3"

JAR_FILE="$(find -L "${NEXUS_IQ_SERVER_HOME%/}" -maxdepth 3 -type f -name 'insight-brain-service*.jar' -o -name 'nexus-iq-server*.jar' 2>/dev/null | sort -V | tail -n1)"
CONFIG_FILE="$(find -L "${NEXUS_IQ_SERVER_HOME%/}" -maxdepth 3 -type f -name 'config.yml' 2>/dev/null | sort -V | tail -n1)"

chmod a+w /tmp/nexus_iq_server.out /tmp/nexus_iq_server.err &>/dev/null
mkdir -p ${NEXUS_IQ_SERVER_HOM%/E}/log &>/dev/null

function get_pid() {
    # NOTE: Should not output anything except the PID.
    local work_dir="$(sed -n -E 's/sonatypeWork[[:space:]]*:[[:space:]]*(.+)/\1/p' "${CONFIG_FILE}")"
    if [ ! -d "${work_dir}" ]; then
        echo "ERROR: No work_dir detected from ${CONFIG_FILE}" >&2
        return 1
    fi
    local lock_file="${work_dir%/}/lock"
    if [ ! -s "${lock_file}" ]; then
        echo "ERROR: No lock file detected from ${work_dir}" >&2
        return 1
    fi
    local pid="$(cat "${lock_file}" | cut -d"@" -f1)"
    if ! ls -1 /proc/"${pid}" &>/dev/null; then
        echo "nexus-iq-server is NOT running - PID ${pid} (stale lock file)" >&2
        return 1
    fi
    echo "${pid}"
}

do_start()
{
    cd "${NEXUS_IQ_SERVER_HOME}" || return $?   # Log path might be using relative path
    export NEXUS_IQ_SERVER_HOME
    # Original uses su -m which can inherits almost all env of current user (eg: root), not sure if it was intentional
    ${SUDO} ${JAVA} ${JAVA_OPTIONS} -jar "${JAR_FILE}" server "${CONFIG_FILE}" > /tmp/nexus_iq_server.out 2> /tmp/nexus_iq_server.err &
    echo "Started nexus-iq-server"
}

do_console()
{
    cd "${NEXUS_IQ_SERVER_HOME}" || return $?
    export NEXUS_IQ_SERVER_HOME
    ${SUDO} ${JAVA} ${JAVA_OPTIONS} -jar "${JAR_FILE}" server "${CONFIG_FILE}"
}

do_stop()
{
    local pid="$(get_pid)"
    if [ -z "${pid}" ]; then
        sleep 10
        pid="$(get_pid)"
    fi

    if [ -z "${pid}" ]; then
        echo "ERROR: No nexus-iq-server process found" >&2
        return 1
    fi

    if ! grep -aq "NEXUS_IQ_SERVER_HOME" /proc/${pid}/environ 2>/dev/null; then
        echo "ERROR: PID ${pid} is not started by this script" >&2
        return 1
    fi

    echo "Terminating nexus-iq-server - PID $pid"
    kill $pid || return $?
}

do_usage()
{
    echo "Usage: nexus-iq-server [console|start|stop]"
}

case $1 in
    console)
        do_console
        ;;
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    *)
        do_usage
        ;;
esac
