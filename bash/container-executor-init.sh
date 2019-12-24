#!/usr/bin/env bash
# /tmp/container-executor-init.sh gmrbatch application_1499127505791_0508 container_e98_1499127505791_0508_01_000019 /jbod/hdd01/hadoop/yarn/local /jbod/hdd01/hadoop/yarn/log

_user=$1
_appid=$2
_contid=$3
_local=$4
_log=$5

/usr/hdp/current/hadoop-yarn-nodemanager/bin/container-executor --checksetup || exit $?

source /etc/hadoop/conf/hadoop-env.sh

if [ -f ${_local%/}/nmPrivate/${_contid}.tokens ]; then
  echo "trying to remove ${_contid}.tokens ..."
  su $_user -c "rm ${_local%/}/nmPrivate/${_contid}.tokens"
fi

# NOTE: classpath is not accurate
/usr/hdp/current/hadoop-yarn-nodemanager/bin/container-executor $_user $_user 0 $_appid ${_local%/}/nmPrivate/${_contid}.tokens ${_local%/} ${_log%/} $JAVA_HOME/bin/java -classpath `hadoop classpath` org.apache.hadoop.yarn.server.nodemanager.containermanager.localizer.ContainerLocalizer $_user $_appid $_contid `hostname -f` 8040 ${_local%/}
