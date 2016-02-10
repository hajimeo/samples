#!/bin/bash
# $1 = cluster name, $2 = Ambari Hostname
# function name is noun_verb

_DOCKER_NETWORK_ADDR="172.17.100."
_DOMAIN_SUFFIX=".localdomain"
_AMBARI_HOST="node1$_DOMAIN_SUFFIX"

function f_ntp() {
    echo "ntpdate ..."
    ntpdate -u ntp.ubuntu.com
}

function f_rc() {
    echo "re-running rc.local ..."
    /etc/rc.local
}

function f_docker_start() {
    local num=`docker ps -aq | wc -l`
    local _num=`docker ps -q | wc -l`
    if [ $_num -ne 0 ]; then
      echo "$_num containers are already running...";
    else
      echo "starting $num docker contains ..."
      for i in `seq 1 $num`; do docker start --attach=false node$i; sleep 1; done
    fi
}

function f_docker_run() {
    local num=`docker ps -aq | wc -l`
    local _num=`docker ps -q | wc -l`
    if [ $_num -ne 0 ]; then
      echo "$_num containers are already running...";
    else
      echo "running $num docker contains ..."
      local _ip=`ifconfig docker0 | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d' | cut -d":" -f2`
      if [ -z "$_ip" ]; then
        echo "No Docker interface IP"
        return
      fi

      for n in `seq 1 $num`; do
        docker run -t -i -d --dns $_ip --name node$n --privileged horton/base /startup.sh ${_DOCKER_NETWORK_ADDR}$n node$n${_DOMAIN_SUFFIX} $_ip
      done
    fi
}

function f_ambari_start() {
    ssh $_AMBARI_HOST "ambari-server start" || return

    local _num=`docker ps -q | wc -l`
    for i in `seq 1 $_num`; do
        ssh -t node$i${_DOMAIN_SUFFIX} 'ambari-agent start'
    done
}

function f_etcs_mount() {
    echo "Mounting etc ..."
    local _num=`docker ps -q | wc -l`
    for i in `seq 1 $_num`; do
        if [ ! -d /mnt/etc/node$i ]; then
            mkdir -p /mnt/etc/node$i
        fi

        umount /mnt/etc/node$i 2>/dev/null;
        sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,transform_symlinks node${i}${_DOMAIN_SUFFIX}:/etc /mnt/etc/node${i}
    done
}

function f_repo_setup() {
    local _host_pc="$1"
    local _mu="${2-hosako}"
    local _src="${3-/Users/${_mu}/Public/hdp/}"
    local _mounting_dir="/var/www/html/hdp"

    if [ -z "$_host_pc" ]; then
      _host_pc="`env | awk '/SSH_CONNECTION/ {gsub("SSH_CONNECTION=", "", $1); print $1}'`"
      if [ -z "$_host_pc" ]; then
        _host_pc="192.168.136.1"
      fi
    fi

    mount | grep "$_mounting_dir"
    if [ $? -eq 0 ]; then
      umount -f "$_mounting_dir"
    fi
    if [ ! -d "$_mounting_dir" ]; then
        mkdir "$_mounting_dir" || return
    fi

    echo "Mounting ${_mu}@${_host_pc}:${_src} to $_mounting_dir ..."
    echo "(TODO: Edit this function for your env)"
    sleep 4
    sshfs -o allow_other,uid=0,gid=0,umask=002,reconnect,transform_symlinks ${_mu}@${_host_pc}:${_src} "$_mounting_dir"
    service apache2 start
}

function f_services_start() {
    c=$(PGPASSWORD=bigdata psql -Uambari -h $_AMBARI_HOST -tAc "select cluster_name from ambari.clusters order by cluster_id desc limit 1;")
    if [ -z "$c" ]; then
      echo "ERROR: No cluster name (check postgres)..."
      return 1
    fi
    
    for i in `seq 1 10`; do
      u=$(PGPASSWORD=bigdata psql -Uambari -h $_AMBARI_HOST -tAc "select count(*) from hoststate where health_status ilike '%UNKNOWN%';")
      #curl -s --head "http://$_AMBARI_HOST:8080/" | grep '200 OK'
      if [ "$u" -eq 0 ]; then
        break
      fi
  
      echo "Some Ambari agent is in UNKNOWN state ($u). retrying..."
      sleep 5
    done
    # trying anyway
    sleep 10
    curl -u admin:admin -H "X-Requested-By: ambari" "http://$_AMBARI_HOST:8080/api/v1/clusters/${c}/services?" -X PUT --data '{"RequestInfo":{"context":"_PARSE_.START.ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"'${c}'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}'
    echo ""
}

function f_screen_cmd() {
    screen -ls | grep -w docker
    if [ $? -ne 0 ]; then
      local _num=`docker ps -q | wc -l`
      echo "You may want to run the following commands to start GNU Screen:"
      echo "screen -S \"docker\" bash -c 'for s in \`seq 1 4\`; do screen -t \"node\${s}\" \"ssh\" \"node\${s}.localdomain\"; done'"
    fi
}

function f_host_setup() {
    local _docer0="${1-172.17.42.1}"
    set -x
    apt-get update && apt-get upgrade -y
    apt-get -y install wget createrepo sshfs dnsmasq apache2 htop dstat iotop sysv-rc-conf postgresql-client mysql-client
    #krb5-kdc krb5-admin-server mailutils postfix
    
    apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >> /etc/apt/sources.list.d/docker.list; cat /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get purge lxc-docker*; apt-get install docker-engine -y
    
    echo 'addn-hosts=/etc/banner_add_hosts' >> /etc/dnsmasq.conf; grep '^addn-hosts' /etc/dnsmasq.conf
    # TODO: the first IP can be wrong
    #_ip=`ifconfig docker0 | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d' | cut -d":" -f2`
    echo "$_docer0     dockerhost1.localdomain dockerhost1
172.17.100.1    node1.localdomain node1
172.17.100.2    node2.localdomain node2
172.17.100.3    node3.localdomain node3
172.17.100.4    node4.localdomain node4
172.17.100.5    node5.localdomain node5
172.17.100.6    node6.localdomain node6
172.17.100.7    node7.localdomain node7
172.17.100.8    node8.localdomain node8
" > /etc/banner_add_hosts; cat /etc/banner_add_hosts
    service dnsmasq restart

   mkdir -m 777 /var/www/html/hdp
   set +x
}

function f_hostname() {
    local _new_name="$1"
    if [ -z "$_new_name" ]; then
      echo "no hostname"
      return 1
    fi
    
    set -x
    local _current="`cat /etc/hostname`"
    hostname $_new_name
    echo "$_new_name" > /etc/hostname
    sed -i.bak "s/\b${_current}\b/${_new_name}/g" /etc/hosts
    diff /etc/hosts.bak /etc/hosts
    set +x
}

function f_yum_remote_proxy() {
    # TODO: requires password less ssh
    local _proxy="$1"
    local _host="$2"

    ssh $_host "grep proxy /etc/yum.conf" && return 1
    ssh $_host "echo "proxy=${_proxy}" >> /etc/yum.conf"
    ssh $_host "grep proxy /etc/yum.conf"
}

function f_gw_set() {
    set -x
    local _gw="`ifconfig docker0 | grep -oP 'inet addr:\d+\.\d+\.\d+\.\d' | cut -d":" -f2`"
    local _num=`docker ps -q | wc -l`
    for i in `seq 1 $_num`; do
        ssh -t node$i${_DOMAIN_SUFFIX} "route add default gw $_gw eth0"
    done
    set +x
}

if [ "$0" = "$BASH_SOURCE" ]; then
    f_ntp
    #f_rc
    #f_docker_run
    f_docker_start
    sleep 4
    f_ambari_start
    f_etcs_mount
    #f_repo_setup
    echo "WARN: Will start all services after 10 secs..."
    sleep 10
    f_services_start
    f_screen_cmd
fi
