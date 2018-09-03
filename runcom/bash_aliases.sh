# Simple/generic alias commands
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias urldecode='python -c "import sys, urllib as ul; print ul.unquote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
alias utc2int='python -c "import sys,time,dateutil.parser;print int(time.mktime(dateutil.parser.parse(sys.argv[1]).timetuple()))"'  # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python -c "import sys,time;print time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\""'

# Alias commands related to my script and work
alias logS="source ~/IdeaProjects/samples/bash/log_search.sh"
#alias pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);pdf=pd.DataFrame(jd);")'
alias pandas='python -i <(echo "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);")'
# port: 30000
alias mb='java -jar ~/Applications/metabase.jar'
alias jn='if [ -d ~/backup/jupyter-notebook ]; then
    cp -f ~/backup/jupyter-notebook/Aggregation.ipynb ./ && jupyter notebook &
    while true; do
        sleep 300
        if [ "`ls -1 ./*.ipynb 2>/dev/null | wc -l`" -gt 0 ]; then
            rsync -a --exclude="Untitled.ipynb" ./*.ipynb ~/backup/jupyter-notebook/ || break
        fi
        if ! nc -z localhost 8888 &>/dev/null; then
            mv -f ./Aggregation.ipynb /tmp/
            break
        fi
    done &
fi'

# Hostname specific alias command
# rsync -Pharz root@server:/usr/local/atscale/apps/modeler/assets/modeler/public/* ./atscale_doc_NNN/
# cd ./atscale_doc_NNN/ && patch -p0 -b < ~/doc_index.patch
# ln -s ~/IdeaProjects/atscale_doc_NNN/docs ~/Public/atscale_latest
alias aDoc='cd ~/Public/atscale_latest/ && nohup python -m SimpleHTTPServer 38081 &>/tmp/python_simplehttpserver.out &'
alias sWeb='nohup python ~/IdeaProjects/samples/python/SympleWebServer.py &>/tmp/python_simplewebserver.out &'
# NOTE: https requires s3-us-west-1.amazonaws.com
alias asS3='s3cmd ls s3://files.atscale.com/installer/package/ | grep -E "atscale-[6789].+latest.+\.tar\.gz$"'



### Functions (some command syntax does not work with alias eg: sudo) ###############################
# NOTE: the hostname 'asftp' is specified in .ssh_config
function asftpl() {
    local _name="${1}"
    local _n="${2:-20}"
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        _n=$1
        _name="${2}"
    fi
    #ssh -q asftp -t 'cd /home/ubuntu/upload && find . -type f -mtime -2 -size +10240k -name "'${_name}'" -ls | sort -k9,10 | tail -n'${_n}
    ssh -q asftp -t 'cd /home/ubuntu/upload && ls -lhtr '${_name}'| tail -n'${_n}
}
function asftpd() {
    [ -z "$1" ] && ( asftpl; return 1 )
    for _a in "$@"; do
        local _ext="${_a##*.}"
        local _rsync_opts="-Phz"
        [[ "${_ext}" =~ ^gz|zip|tgz$ ]] && _rsync_opts="-Ph"
        rsync ${_rsync_opts} asftp:"/home/ubuntu/upload/$_a" ./
    done
}

function jargrep() {
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${2:-./} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c ''${_cmd}' {} | grep -wi '$1' && echo {}'
}

function bar() {
    ggrep -oP "${2:-^\d\d\d\d-\d\d-\d\d.\d\d:\d\d}" ${1-./*} | bar_chart.py # TODO: need to sort?
}

function r2dh() {
    local _3rd="${1:-100}"  # 3rd decimal in network address
    local _dh="${2:-192.168.0.31}"  # docker host IP
    if [ "Darwin" = "`uname`" ]; then
        sudo route delete -net 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 ${_dh}
    elif [ "Linux" = "`uname`" ]; then
        sudo ip route del 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 gw ${_dh} ens3
    else    # Assuming windows (cygwin)
        route delete 172.17.${_3rd}.0 &>/dev/null;route add 172.17.${_3rd}.0 mask 255.255.255.0 ${_dh};
    fi
}