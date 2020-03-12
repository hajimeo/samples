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

NEXUS_IQ_SERVER_HOME=/opt/sonatype/nexus-iq-server
# The user ID which should be used to run the IQ Server
# # IMPORTANT - Make sure that the user has the required privileges to write into the IQ Server work directory.
RUN_AS_USER="${_NXIQ_USER:-"sonatype"}"
_XMX="${_NXIQ_HEAPSIZE:-"2G"}"
# _JAVA_OPTIONS should be appended in the last to overwrite
JAVA_OPTIONS="-Xms${_XMX} -Xmx${_XMX} -XX:+UseG1GC -verbose:gc -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:./log/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1024k -XX:+PrintClassHistogramBeforeFullGC -XX:+TraceClassLoading -XX:+TraceClassUnloading ${_JAVA_OPTIONS}"

do_start()
{
    cd $NEXUS_IQ_SERVER_HOME
    # Original uses su -m which can inherits almost all env of current user (eg: root), not sure if it was intentional
    sudo -u $RUN_AS_USER java $JAVA_OPTIONS -jar ./nexus-iq-server-*.jar server ./config.yml &> ./log/nexus_iq_server.out &
    echo "Started nexus-iq-server"
}

do_console()
{
    cd $NEXUS_IQ_SERVER_HOME
    sudo -u $RUN_AS_USER java $JAVA_OPTIONS -jar ./nexus-iq-server-*.jar server ./config.yml
}

do_stop()
{
    local pid=$(ps -o pid,command -u sonatype -U sonatype | grep -m1 -P '^java .+/nexus-iq-server.*jar server\b' | awk '{print $1}')
    if [ -n "${pid}" ]; then
        kill $pid
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