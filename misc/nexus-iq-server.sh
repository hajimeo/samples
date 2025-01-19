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
NEXUS_IQ_SERVER_HOME=/opt/sonatype/nexus-iq-server
NEXUS_IQ_SONATYPEWORK=/opt/sonatype/sonatype-work/clm-server
RUN_AS_USER="${_NXIQ_USER:-"sonatype"}"
### END Variables

SUDO="sudo -u ${RUN_AS_USER}"
[ "${RUN_AS_USER}" == "${USER}" ] && SUDO=""
JAVA="java"
# If JAVA_HOME is specified, use it.
[ -n "${JAVA_HOME}" ] && JAVA="${JAVA_HOME%/}/bin/java"

# Minimum recommended options (but not using -XX:-OmitStackTraceInFastThrow as this is for my test server)
JAVA_OPTIONS="-Xms${_NXIQ_HEAPSIZE:-"2G"} -Xmx${_NXIQ_HEAPSIZE:-"2G"} -XX:ActiveProcessorCount=2"

# For kill -3 (too see the stdout, use journalctl _PID=<PID>). Also jvm_%p.log works too
JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+UnlockDiagnosticVMOptions -XX:+LogVMOutput -XX:LogFile=${NEXUS_IQ_SONATYPEWORK}/log/jvm.log"

# GC log related options are different by Java version.
if ${JAVA} -XX:+PrintFlagsFinal -version 2>&1 | grep -q GCLogFileSize; then
    # probably java 8 (-verbose:gc = -XX:+PrintGC)
    JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+UseG1GC -XX:+ExplicitGCInvokesConcurrent -XX:+PrintGCApplicationStoppedTime -XX:+TraceClassLoading -XX:+TraceClassUnloading"
    # https://confluence.atlassian.com/confkb/how-to-enable-garbage-collection-gc-logging-300813751.html
    # -XX:+PrintTenuringDistribution -XX:+PrintClassHistogramBeforeFullGC
    JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCCause -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M -Xloggc:${NEXUS_IQ_SONATYPEWORK}/log/gc.%t.log -XX:+PrintClassHistogramAfterFullGC"
else
    # default, expecting java 11 (@see: https://docs.oracle.com/en/java/java-components/enterprise-performance-pack/epp-user-guide/printing-jvm-information.html)
    #JAVA_OPTIONS="${JAVA_OPTIONS} -Xlog:gc*,gc+classhisto*=trace:file=${NEXUS_IQ_SONATYPEWORK}/log/gc.%t.log:time,uptime:filecount=10,filesize=100m"
    # TODO: GC log for Java 17
    JAVA_OPTIONS="${JAVA_OPTIONS}"
fi
JAVA_OPTIONS="${JAVA_OPTIONS} -XX:MaxDirectMemorySize=1g -Djdk.nio.maxCachedBufferSize=262144"  # probably bytes
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:OnOutOfMemoryError='kill %p'"    # Or -XX:+ExitOnOutOfMemoryError, but no need because of https://help.sonatype.com/en/iq-server-installation.html#automatic-shutdown-on-errors
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:OnOutOfMemoryError='kill -3 %p'"  # TODO: May not work with IQ
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+CrashOnOutOfMemoryError -XX:ErrorFile=${NEXUS_IQ_SONATYPEWORK}/log"  # TODO: May not work with IQ
#JAVA_OPTIONS="${JAVA_OPTIONS} -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${NEXUS_IQ_SONATYPEWORK}/log"    # or 'user.dir' (cwd) if not specified
#JAVA_OPTIONS="${JAVA_OPTIONS} -Xdump:system:label=${NEXUS_IQ_SONATYPEWORK}/log/core.%Y%m%d.%H%M%S.%pid.dmp"     # or 'user.dir' (cwd) if not specified
#JAVA_OPTIONS="${JAVA_OPTIONS} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=6786 -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"
# for testing
#JAVA_OPTIONS="${JAVA_OPTIONS} -Dinsight.threads.monitor=3"

chmod a+w /tmp/nexus_iq_server.out /tmp/nexus_iq_server.err &>/dev/null
do_start()
{
    cd ${NEXUS_IQ_SONATYPEWORK}
    # Original uses su -m which can inherits almost all env of current user (eg: root), not sure if it was intentional
    ${SUDO} ${JAVA} ${JAVA_OPTIONS} -jar ${NEXUS_IQ_SERVER_HOME%/}/nexus-iq-server-[0-9.]*-??.jar server ${NEXUS_IQ_SERVER_HOME%/}/config.yml > /tmp/nexus_iq_server.out 2> /tmp/nexus_iq_server.err &
    echo "Started nexus-iq-server"
}

do_console()
{
    cd ${NEXUS_IQ_SONATYPEWORK}
    ${SUDO} ${JAVA} ${JAVA_OPTIONS} -jar ${NEXUS_IQ_SERVER_HOME%/}/nexus-iq-server-[0-9.]*-??.jar server ${NEXUS_IQ_SERVER_HOME%/}/config.yml
}

do_stop()
{
    local pid=$(ps -o pid,command -u ${RUN_AS_USER} -U ${RUN_AS_USER} | grep -m1 -P '\bjava .+/nexus-iq-server.*jar server ' | awk '{print $1}')
    if [ -n "${pid}" ]; then
        kill $pid || return $?
        echo "Killed nexus-iq-server - PID $pid"
    fi
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