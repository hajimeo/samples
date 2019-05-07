## Simple/generic alias commands (some need pip though) ################################################################
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"' # cd to the last modified dir
alias urldecode='python -c "import sys, urllib as ul; print ul.unquote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
alias utc2int='python -c "import sys,time,dateutil.parser;print int(time.mktime(dateutil.parser.parse(sys.argv[1]).timetuple()))"'  # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python -c "import sys,time;print time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\""'
#alias pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);pdf=pd.DataFrame(jd);")'   # Start python interactive after loading json object in 'pdf' (pandas dataframe)
alias pandas='python -i <(echo "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);")'
alias rmcomma='sed "s/,$//g; s/^\[//g; s/\]$//g"'
alias rgm='rg -N --no-filename -z'
alias timef='/usr/bin/time -f"[%Us user %Ss sys %es real %MkB mem]"'    # brew install gnu-time --with-default-names
alias jp='jupyter-lab &> /tmp/jupyter-lab.out &'
# Read xml file, then convert to dict, then json
alias xml2json='python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))"'
# TODO: find with sys.argv[2] (no ".//"), then output as string
alias xml_get='python3 -c "import sys;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();print(r.find(sys.argv[2],namespaces=r.nsmap))"'
# Search with 2nd arg and output the path(s)
alias xml_path='python -c "import sys,pprint;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();pprint.pprint([t.getelementpath(x) for x in r.findall(\".//\"+sys.argv[2],namespaces=r.nsmap)])"'

## Non generic (OS/host/app specific) alias commands ###################################################################
# Load/source my log searching utility functions
#mkdir -p ~/IdeaProjects/samples/bash; curl -o ~/IdeaProjects/samples/bash/log_search.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
alias logS="source $HOME/IdeaProjects/samples/bash/log_search.sh"
alias xmldiff="python $HOME/IdeaProjects/samples/python/xml_parser.py"
alias ss="bash $HOME/IdeaProjects/samples/bash/setup_standalone.sh"

# VM related
# virt-manager remembers the connections, so normally would not need to start in this way.
alias kvm_seth='virt-manager -c "qemu+ssh://root@sethdesktop/system?socket=/var/run/libvirt/libvirt-sock" &>/tmp/virt-manager.out &'

# Java / jar related
alias mb='java -jar ~/Applications/metabase.jar'    # port is 3000
alias vnc='nohup java -jar ~/Applications/tightvnc-jviewer.jar &>/tmp/tightvnc-jviewer.out &'

# Chrome aliases for Mac (URL needs to be IP as hostname wouldn't be resolvable on remote)
alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=socks5://dh1:28081 https://192.168.1.31:4200/webuser/'
alias shib-spt='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/spt --proxy-server=socks5://support:28081 https://192.168.6.162:4200/webuser/'
alias shib-haj='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/haj --proxy-server=socks5://hajime:28081 https://192.168.6.163:4200/webuser/'
alias hblog='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/hajigle https://www.blogger.com/blogger.g?blogID=9018688091574554712&pli=1#allposts'

# Python simple http server from the specific dir
# To setup: asDocSync <server ip>
alias webs='cd ~/Public/atscale_latest/ && nohup python -m SimpleHTTPServer 38081 &>/tmp/python_simplehttpserver.out & nohup python ~/IdeaProjects/samples/python/SympleWebServer.py &>/tmp/python_simplewebserver.out &'
# List and grep some specific files from s3. NOTE: https:// requires s3-us-west-1.amazonaws.com

# Work specific aliases
alias asS3='s3cmd ls s3://files.atscale.com/installer/package/ | grep -E "^201[89]-.+atscale-(20|[6789]).+\.x86_64\.(tar\.gz|rpm)$"'
alias hwxS3='s3cmd ls s3://private-repo-1.hortonworks.com/HDP/centos7/2.x/updates/'
# TODO: public-repo-1.hortonworks.com private-repo-1.hortonworks.com


### Functions (some command syntax does not work with alias eg: sudo) ##################################################
# head and tail of one file
function ht() {
    local _f="$1"
    local _tac="tac"
    which gtac &>/dev/null && _tac="gtac"
    grep -E '^[0-9]' -m 1 ${_f}
    ${_tac} ${_f} | grep -E '^[0-9]' -m 1
}
# make a directory and cd
function mcd() {
    local _path="$1"
    mkdir "${_path}" && cd "${_path}"
}
# cat some.json | pjson | less (or vim -)
function pjson() {
    local _max_length="${1:-16384}"
    local _sort_keys="False"; [[ "$2" =~ (y|Y) ]] && _sort_keys="True"

    python -c 'import sys,json,encodings.idna
for l in sys.stdin:
    l2=l.strip().lstrip("[").rstrip(",]")[:'${_max_length}']
    try:
        jo=json.loads(l2)
        print json.dumps(jo, indent=4, sort_keys='${_sort_keys}')
    except ValueError:
        print l2'
}
# Grep against jar file to find a class ($1)
function jargrep() {
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${2:-./} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} | grep -wi '$1' && echo {}"
}
# Get PID from the port number, then set JAVA_HOME and CLASSPATH
function javaenvs() {
    local _port="${1}"
    local _p=`lsof -ti:${_port}`
    if [ -z "${_p}" ]; then
        echo "Nothing running on port ${_port}"
        return 11
    fi
    local _user="`stat -c '%U' /proc/${_p}`"
    local _dir="$(dirname `readlink /proc/${_p}/exe` 2>/dev/null)"
    export JAVA_HOME="$(dirname $_dir)"
    export CLASSPATH=".:`sudo -u ${_user} $JAVA_HOME/bin/jcmd ${_p} VM.system_properties | sed -nr 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
}
# Grep STDIN with \d\d\d\d-\d\d-\d\d.\d\d:\d (upto 10 mins) and pass to bar_chart
function bar() {
    #ggrep -oP "${2:-^\d\d\d\d-\d\d-\d\d.\d\d:\d}" ${1-./*} | bar_chart.py
    rg '^(\d\d\d\d-\d\d-\d\d).(\d\d:\d)' -o -r '${1}T${2}' | bar_chart.py
}
function barH() {
    #ggrep -oP "${2:-^\d\d\d\d-\d\d-\d\d.\d\d:\d}" ${1-./*} | bar_chart.py
    rg '^(\d\d\d\d-\d\d-\d\d).(\d\d)' -o -r '${1}T${2}' | bar_chart.py
}
# Start Jupyter Lab as service
function jpl() {
    local _dir="${1:-"."}"
    local _kernel_timeout="${2-10800}"
    local _shutdown_timeout="${3-115200}"

    local _conf="$HOME/.jupyter/jpl_tmp_config.py"
    local _log="/tmp/jpl_${USER}_$$.out"
    if [ ! -d "$HOME/.jupyter" ]; then mkdir "$HOME/.jupyter" || return $?; fi
    > "${_conf}"
    [[ "${_kernel_timeout}" =~ ^[0-9]+$ ]] && echo "c.MappingKernelManager.cull_idle_timeout = ${_kernel_timeout}" >> "${_conf}"
    [[ "${_shutdown_timeout}" =~ ^[0-9]+$ ]] && echo "c.NotebookApp.shutdown_no_activity_timeout = ${_shutdown_timeout}" >> "${_conf}"

    echo "Redirecting STDOUT / STDERR into ${_log}" >&2
    nohup jupyter lab --ip=`hostname -I | cut -d ' ' -f1` --no-browser --config="${_conf}" --notebook-dir="${_dir%/}" 2>&1 | tee "${_log}" | grep -m1 -oE "http://`hostname -I | cut -d ' ' -f1`:.+token=.+" &
}
# Mac only: Start Google Chrome in incognito with proxy
function chromep() {
    local _host_port="${1:-"192.168.6.163:28081"}"
    local _url=${2}
    local _port=${3:-28081}

    local _host="${_host_port}"
    if [[ "${_host_port}" =~ ^([0-9.]+):([0-9]+)$ ]]; then
        _host="${BASH_REMATCH[1]}"
        _port="${BASH_REMATCH[2]}"
    fi
    [ ! -d $HOME/.chromep/${_host}_${_port} ] && mkdir -p $HOME/.chromep/${_host}_${_port}
    [ -n "${_url}" ] && [[ ! "${_url}" =~ ^http ]] && _url="http://${_url}"
    #nohup "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --user-data-dir=$HOME/.chromep/${_host}_${_port} --proxy-server="socks5://${_host}:${_port}" ${_url} &>/tmp/chrome.out &
    open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/${_host}_${_port} --proxy-server=socks5://${_host}:${_port} ${_url}
    echo 'open -na "Google Chrome" --args --user-data-dir=$(mktemp -d) --proxy-server=socks5://'${_host}':'${_port}' '${_url}
}
# Add route to dockerhost to access containers directly
function r2dh() {
    local _3rd="${1:-100}"  # 3rd decimal in network address
    local _dh="${2:-dh1}"  # docker host IP
    if [ "Darwin" = "`uname`" ]; then
        sudo route delete -net 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 ${_dh}
        sudo route delete -net 172.18.0.0/24 &>/dev/null;sudo route add -net 172.18.0.0/24 ${_dh}
        sudo route delete -net 172.17.180.0/24 &>/dev/null;sudo route add -net 172.17.180.0/24 192.168.1.32
    elif [ "Linux" = "`uname`" ]; then
        sudo ip route del 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 gw ${_dh} ens3
    else    # Assuming windows (cygwin)
        route delete 172.17.${_3rd}.0 &>/dev/null;route add 172.17.${_3rd}.0 mask 255.255.255.0 ${_dh};
    fi
}
function sshs() {
    local _user_at_host="$1"
    local _session_name="${2}"
    local _cmd="screen -r || screen -ls"
    if [ -n "${_session_name}" ]; then
        _cmd="screen -x ${_session_name} || screen -S ${_session_name}"
    else
        # if no session name specified, tries to attach it anyway (if only one session, should work)
        _cmd="screen -x || screen -x $USER || screen -S $USER"
    fi
    ssh ${_user_at_host} -t ${_cmd}
}
# backup commands
function backupC() {
    local _src="${1:-"$HOME/Documents/cases"}"
    local _dst="${2:-"hosako@z230:/cygdrive/h/hajime/cases"}"
    [ ! -d "${_src}" ] && return 11
    [ ! -d "$HOME/.Trash" ] && return 12
    local _size="10000k"
    # Delete files larger than _size (10MB) and older than one year
    find ${_src%/} -type f -mtime +365 -size +${_size} -print0 | xargs -0 -t -n1 -I {} mv {} $HOME/.Trash/ &
    # Delete files larger than 200MB and older than 90 days
    find ${_src%/} -type f -mtime +90 -size +200000k -print0 | xargs -0 -t -n1 -I {} mv {} $HOME/.Trash/ &
    # Synch all files smaller than _size (10MB)
    rsync -Pvaz --max-size=${_size} --modify-window=1 ${_src%/}/* ${_dst%/}/
    wait
}


## Work specific functions
# copy script(s) into linux servers
function asPubInst() {
    scp -C $HOME/IdeaProjects/samples/atscale/install_atscale.sh root@192.168.6.160:/var/tmp/share/atscale/ &
    scp -C $HOME/IdeaProjects/samples/atscale/install_atscale.sh hajime@192.168.6.162:/var/tmp/share/atscale/ &
    scp -C $HOME/IdeaProjects/samples/atscale/install_atscale.sh hajime@192.168.6.163:/var/tmp/share/atscale/ &
    scp $HOME/IdeaProjects/samples/atscale/install_atscale.sh hosako@dh1:/var/tmp/share/atscale/ &
    cp -f $HOME/IdeaProjects/samples/atscale/install_atscale.sh $HOME/share/atscale/
    wait
}
# List files against hostname 'asftp'. NOTE: the hostname 'asftp' is specified in .ssh_config
function asftpl() {
    local _name="${1}"
    local _n="${2:-20}"
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        _n=$1
        _name="${2}"
    fi
    #ssh -q asftp -t 'cd /home/ubuntu/upload && find . -type f -mtime -2 -size +10240k -name "'${_name}'" -ls | sort -k9,10 | tail -n'${_n}
    ssh -q asftp -t 'cd /home/ubuntu/upload && ls -lhtr '${_name}' | grep -vE "(telemetryonly|image-diagnostic|\.dmp)" | tail -n'${_n}';date'
}
# Download a syngle file from hostname 'asftp'. NOTE: the hostname 'asftp' is specified in .ssh_config
function asftpd() {
    local _file="$1"
    local _bwlimit_kb="$2"
    [ -z "${_file}" ] && ( asftpl; return 1 )
    ssh -q asftp -t "cd /home/ubuntu/upload && ls -lhtr ${_file}" || return $?
    local _ext="${_file##*.}"
    local _rsync_opts="-Phz"
    [[ "${_ext}" =~ ^gz|zip|tgz$ ]] && _rsync_opts="-Ph"
    [[ "${_bwlimit_kb}" =~ ^[0-9]+$ ]] && _rsync_opts="${_rsync_opts} --bwlimit=${_bwlimit_kb}"
    rsync ${_rsync_opts} asftp:"/home/ubuntu/upload/${_file}" ./
}
function asDocSync() {
    local _server="$1"
    local _loginas="${2:-root}"
    rsync -Phrz ${_loginas}@${_server}:/usr/local/atscale/apps/modeler/assets/modeler/public/docs/* ~/Public/atscale_latest/
    cd ~/Public/atscale_latest/ && patch -p0 -b < ~/IdeaProjects/samples/misc/doc_index.patch
}
