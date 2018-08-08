alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias urldecode='python -c "import sys, urllib as ul; print ul.unquote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
alias utc2int='python -c "import sys,time,dateutil.parser;print int(time.mktime(dateutil.parser.parse(sys.argv[1]).timetuple()))"'
alias int2utc='python -c "import sys,time;print time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\""'

alias sWeb='python ~/IdeaProjects/samples/python/SympleWebServer.py &'

#alias pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);pdf=pd.DataFrame(jd);")'
alias pandas='python -i <(echo "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);")'
# jn ./some_notebook.ipynb &
alias jn='if [ -d ~/backup/jupyter-notebook ]; then
    cp -f ~/backup/jupyter-notebook/Aggregation.ipynb ./
    while true; do
        if [ "`ls -1 ./*.ipynb 2>/dev/null | wc -l`" -gt 0 ]; then
            rsync -a --exclude="./Untitled.ipynb" ./*.ipynb ~/backup/jupyter-notebook/ || break
        fi
        sleep 300
        if ! nc -z localhost 8888 &>/dev/null; then
            mv -f ./Aggregation.ipynb /tmp/
            break
        fi
    done &
fi
jupyter notebook'



### Functions (some command syntax does not work with alias eg: sudo) ###############################
function asftpl() {
    ssh -q asftp -t 'cd /home/ubuntu/upload && ls -lt '$2' | head -n ${1:-20}'
}
function asftpd() {
    [ -z "$1" ] && return 1
    local _ext="${1##*.}"
    local _rsync_opts="-Phz"
    [[ "${_ext}" =~ gz|zip ]] && _rsync_opts="-Ph"
    #sftp asftp:/home/ubuntu/upload/$1
    rsync ${_rsync_opts} asftp:/home/ubuntu/upload/$1 ./
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