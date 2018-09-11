### Simple/generic alias commands (some need pip though) ###############################################################
# cd to the last modified dir
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias urldecode='python -c "import sys, urllib as ul; print ul.unquote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
alias utc2int='python -c "import sys,time,dateutil.parser;print int(time.mktime(dateutil.parser.parse(sys.argv[1]).timetuple()))"'  # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python -c "import sys,time;print time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\""'
# Start python interactive after loading json object in 'pdf' (pandas dataframe)
#alias pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);pdf=pd.DataFrame(jd);")'
alias pandas='python -i <(echo "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);")'
alias rmcomma='sed "s/,$//g; s/^\[//g; s/\]$//g"'


## Non generic (OS/host/app specific) alias commands ###################################################################
# Load/source my log searching utility functions
alias logS="source ~/IdeaProjects/samples/bash/log_search.sh"
# Start metabase on port: 30000
alias mb='java -jar ~/Applications/metabase.jar'
alias vnc='java -jar ~/Applications/tightvnc-jviewer.jar'
# Start Jupyter Notebook with Aggregation template (and backup-ing)
alias jn='if [ -d ~/backup/jupyter-notebook ]; then
    cp ~/backup/jupyter-notebook/Aggregation.ipynb ./ && jupyter notebook &
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
# Start python simple http server from the specific dir
# To setup:
#   rsync -Pharz root@server:/usr/local/atscale/apps/modeler/assets/modeler/public/* ./atscale_doc_NNN/
#   cd ./atscale_doc_NNN/ && patch -p0 -b < ~/doc_index.patch
#   ln -s ~/IdeaProjects/atscale_doc_NNN/docs ~/Public/atscale_latest
alias webs='cd ~/Public/atscale_latest/ && nohup python -m SimpleHTTPServer 38081 &>/tmp/python_simplehttpserver.out & nohup python ~/IdeaProjects/samples/python/SympleWebServer.py &>/tmp/python_simplewebserver.out &'
# List and grep some specific files from s3. NOTE: https:// requires s3-us-west-1.amazonaws.com
alias asS3='s3cmd ls s3://files.atscale.com/installer/package/ | grep -E "atscale-[6789].+latest-el6\.x86_64\.tar\.gz$"'


### Functions (some command syntax does not work with alias eg: sudo) ##################################################
# Mac only: Start Google Chrome in incognito with proxy
function chromep() {
    local _proxy_host="${1:-http://support:28080}"
    local _reuse_session="${2}" # This means Chrome needs to be shutdown to use proxy
    local _proxy=""; [ -n "$_proxy_host" ] && _proxy="--proxy-server=$_proxy_host"
    local _user_dir="--user-data-dir=$(mktemp -d)"; [[ "${_reuse_session}" =~ ^(y|Y) ]] && _user_dir=""
    nohup "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ${_user_dir} ${_proxy} &
    # Below didn't work
    #open -na "Google Chrome" --args "--user-data-dir=${_tmp_dir} ${_proxy}"
    #open -na "Google Chrome" --args "--incognito ${_proxy}"
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
    ssh -q asftp -t 'cd /home/ubuntu/upload && ls -lhtr '${_name}'| tail -n'${_n}
}
# Download files from hostname 'asftp'. NOTE: the hostname 'asftp' is specified in .ssh_config
function asftpd() {
    [ -z "$1" ] && ( asftpl; return 1 )
    for _a in "$@"; do
        local _ext="${_a##*.}"
        local _rsync_opts="-Phz"
        [[ "${_ext}" =~ ^gz|zip|tgz$ ]] && _rsync_opts="-Ph"
        rsync ${_rsync_opts} asftp:"/home/ubuntu/upload/$_a" ./
    done
}

# Grep against jar file to find a class ($1)
function jargrep() {
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${2:-./} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c ''${_cmd}' {} | grep -wi '$1' && echo {}'
}
# Grep file(s) with \d\d\d\d-\d\d-\d\d.\d\d:\d (upto 10 mins) and pass to bar_chart
function bar() {
    ggrep -oP "${2:-^\d\d\d\d-\d\d-\d\d.\d\d:\d}" ${1-./*} | bar_chart.py
}
# Add route to dockerhost to access containers directly
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