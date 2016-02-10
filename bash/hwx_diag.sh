#!/bin/env bash
_now=$(date +"%Y%m%d%H%M%S")
_c="${1-$_now}"
_u="$2"
#_p="`lsof -ti:$3 -sTCP:LISTEN`"
_p="$3"
if [ -z "$_p" ] || [ -z "$_u" ]; then
  echo "USAGE: $0 case_number process_owner pid"
  echo $0' 00068101 ranger "`lsof -ti:6080 -sTCP:LISTEN`"'
  exit 1
fi
if [ ! -d "/proc/${_p}" ]; then
  echo "PID ${_p} is not running"
  exit 2
fi
_j="$(dirname `readlink /proc/${_p}/exe`)"

mkdir ${_c} || exit 3
cd ${_c} || exit 4

echo "collecting top/ps outputs ..."
top -b -n 1 -c &> top.out;netstat -aopen &> netstat.out;ifconfig &> ifconfig.out;ps auxwwwf &> ps.out;grep -i HugePages_Total /proc/meminfo &>hpt_size.out
cat /proc/${_p}/limits &> ${_p}_limits.out;cat /proc/${_p}/status &> ${_p}_status.out;cat /proc/${_p}/io &> ${_p}_io.out;sleep 5;cat /proc/${_p}/io &>> ${_p}_io.out;cat /proc/${_p}/environ | tr '\0' '\n' > ${_p}_environ.out

if [ -x ${_j}/jstack ]; then
  echo "collecting jstack (takes 30 secs)..."
  for i in `seq 1 3`;do sudo -u ${_u} ${_j}/jstack -l ${_p}; sleep 10; done > ./${_p}_jstack.out &
  ps -eLo pid,lwp,nlwp,ruser,pcpu,stime,etime,args | grep -P "^\s*${_p}" > ./${_p}_pseLo.out
fi

if [ -x ${_j}/jstat ]; then
  echo "collecting jstat (takes 15 secs)..."
  sudo -u ${_u} ${_j}/jstat -gccause ${_p} 3000 5 > ./${_p}_jstat.out
fi

wait

cd - &>/dev/null
tar czfv ./${_c}_$(hostname)_${_now}.tar.gz ./${_c}/*.out
echo "created ./${_c}_$(hostname)_${_now}.tar.gz"
echo "please remove ${_c}"
