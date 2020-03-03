## Simple/generic alias commands (some need pip though) ################################################################
# 'cd' to last modified directory
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias fd='find . -name'
alias fcv='fc -e vim'
alias pjt='python -m json.tool'
alias urldecode='python -c "import sys, urllib as ul; print(ul.unquote_plus(sys.argv[1]))"'
#alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print(ul.quote(sys.argv[1]))"'
# base64 encode/decode (coreutils base64 or openssl base64 -e|-d)
alias b64encode='python -c "import sys, base64; print(base64.b64encode(sys.argv[1]))"'
alias b64decode='python -c "import sys, base64; print(base64.b64decode(sys.argv[1]))"'
alias utc2int='python -c "import sys,time,dateutil.parser;print(int(time.mktime(dateutil.parser.parse(sys.argv[1]).timetuple())))"'  # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python -c "import sys,datetime;print(datetime.datetime.utcfromtimestamp(int(sys.argv[1][0:10])).strftime(\"%Y-%m-%d %H:%M:%S\")+\".\"+sys.argv[1][10:13]+\" UTC\")"'
#alias int2utc='python -c "import sys,time;print(time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\")"'
alias dec2hex='printf "%x\n"'
alias hex2dec='printf "%d\n"'
#alias pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);pdf=pd.DataFrame(jd);")'   # Start python interactive after loading json object in 'pdf' (pandas dataframe)
alias pandas='python3 -i <(echo "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);print(pdf)")'
alias json2csv='python3 -c "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);pdf.to_csv(sys.argv[1]+\".csv\", header=True, index=False)"'
# Read xml file, then convert to dict, then print json
alias xml2json='python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))"'
alias printjson='python3 -c "import sys,json;print(json.dumps(json.load(open(sys.argv[1])), indent=4, sort_keys=True))"'
# TODO: find with sys.argv[2] (no ".//"), then output as string
alias xml_get='python3 -c "import sys;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();print(r.find(sys.argv[2],namespaces=r.nsmap))"'
# Search with 2nd arg and output the path(s)
alias xml_path='python -c "import sys,pprint;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();pprint.pprint([t.getelementpath(x) for x in r.findall(\".//\"+sys.argv[2],namespaces=r.nsmap)])"'
# Strip XML / HTML to get text (TODO: maybe </br> without new line should add new line)
# language=Python
alias xml2text='python3 -c "import sys,html,re;rx=re.compile(r\"<[^>]+>\");print(html.unescape(rx.sub(\"\",sys.stdin.read())))"'
alias jp='jupyter-lab &> /tmp/jupyter-lab.out &'
alias jn='jupyter-notebook &> /tmp/jupyter-notebook.out &'
alias rmcomma='sed "s/,$//g; s/^\[//g; s/\]$//g"'
#alias rmnewline='gsed ":a;N;$!ba;s/\n//g"'  # should not use gsed but anyway, not perfect
# 'time' with format
alias timef='/usr/bin/time -f"[%Us user %Ss sys %es real %MkB mem]"'    # brew install gnu-time --with-default-names
# In case 'tree' is not installed
which tree &>/dev/null || alias tree="pwd;find . | sort | sed '1d;s/^\.//;s/\/\([^/]*\)$/|--\1/;s/\/[^/|]*/|  /g'"
# Debug network performance with curl
alias curld='curl -w "\ntime_namelookup:\t%{time_namelookup}\ntime_connect:\t%{time_connect}\ntime_appconnect:\t%{time_appconnect}\ntime_pretransfer:\t%{time_pretransfer}\ntime_redirect:\t%{time_redirect}\ntime_starttransfer:\t%{time_starttransfer}\n----\ntime_total:\t%{time_total}\nhttp_code:\t%{http_code}\nspeed_download:\t%{speed_download}\nspeed_upload:\t%{speed_upload}\n"'
# output the longest line *number* as wc|gwc -L does not show the line number
alias wcln="awk 'length > max_length { max_length = length; longest_line_num = NR } END { print longest_line_num }'"
# Sum integer in a column by using paste (which concatenates files or characters(+))
alias sumcol="gpaste -sd+ | bc"
# 10 seconds is too short
alias docker_stop="docker stop -t 120"

## Non generic (OS/host/app specific) alias commands ###################################################################
which mdfind &>/dev/null && alias locat="mdfind"
# Load/source my log searching utility functions
#mkdir -p $HOME/IdeaProjects/samples/bash; curl -o $HOME/IdeaProjects/samples/bash/log_search.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
alias logS="source $HOME/IdeaProjects/samples/bash/log_search.sh; source $HOME/IdeaProjects/work/bash/log_search.sh"
alias xmldiff="python $HOME/IdeaProjects/samples/python/xml_parser.py"
alias ss="bash $HOME/IdeaProjects/samples/bash/setup_standalone.sh"

# VM related
# virt-manager remembers the connections, so normally would not need to start in this way.
alias kvm_haji='virt-manager -c "qemu+ssh://root@hajime/system?socket=/var/run/libvirt/libvirt-sock" &>/tmp/virt-manager.out &'

# Java / jar related
alias mb='java -jar $HOME/Applications/metabase.jar'    # port is 3000
alias vnc='nohup java -jar $HOME/Applications/tightvnc-jviewer.jar &>/tmp/vnc-java-viewer.out &'
alias samurai='java -Xmx2048m -jar $HOME/Apps/samurali/samurai.jar'
alias gcviewer='java -Xmx4g -jar $HOME/Apps/gcviewer/gcviewer-1.36.jar'
#alias vnc='nohup java -jar $HOME/Applications/VncViewer-1.9.0.jar &>/tmp/vnc-java-viewer.out &'
alias groovyi='groovysh -e ":set interpreterMode true"'

# Chrome aliases for Mac (URL needs to be IP as hostname wouldn't be resolvable on remote)
#alias shib-local='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/local --proxy-server=socks5://localhost:28081'
#alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=socks5://dh1:28081 http://192.168.1.31:4200/webuser/'
alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=http://dh1:28080 http://192.168.1.31:4200/webuser/'
alias hblog='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/hajigle https://www.blogger.com/blogger.g?blogID=9018688091574554712&pli=1#allposts'

# Work specific aliases
alias hwxS3='s3cmd ls s3://private-repo-1.hortonworks.com/HDP/centos7/2.x/updates/'
# TODO: public-repo-1.hortonworks.com private-repo-1.hortonworks.com
# Slack API Search
[ -s $HOME/IdeaProjects/samples/python/SimpleWebServer.py ] && alias slackS="cd $HOME/IdeaProjects/samples/python/ && nohup python ./SimpleWebServer.py &> /tmp/SimpleWebServer.out &"
#[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py ] && alias supportZip="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/analyze-nexus3-support-zip.py"
#[ -s $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py ] && alias supportBoot="python3 $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py"
[ -s $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py ] && alias sptDumpScript="python3 $HOME/IdeaProjects/nexus-toolbox/scripts/dump_nxrm3_groovy_scripts.py"


### Functions (some command syntax does not work with alias eg: sudo) ##################################################
# Obfuscate string (encode/decode)
function obfuscate() {
    local _str="$1"
    local _salt="$2"
    echo -n "${_str}" | openssl enc -aes-128-cbc -pbkdf2 -salt -pass pass:"${_salt}"
}
function deobfuscate() {
    local _str="$1"
    local _salt="$2"
    echo -n "${_str}" | openssl enc -aes-128-cbc -pbkdf2 -salt -pass pass:"${_salt}" -d
}

# Merge split zip files to one file
function merge_zips() {
    local _first_file="$1"
    zip -FF ${_first_file} --output ${_first_file%.*}.merged.zip
}

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
    mkdir "${_path}"; cd "${_path}"
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
# surprisingly it's not easy to remove all newlines
function rmnewline() {
    python -c 'import sys
for l in sys.stdin:
   sys.stdout.write(l.rstrip("\n"))'
}
function rmspaces() {
    python -c 'import sys
for l in sys.stdin:
   sys.stdout.write("".join(l.split()))'
}

function _find_recent() {
    local __doc__="Find recent (log) files"
    local _dir="${1}"
    local _file_glob="${2:-"*.log"}"
    local _follow_symlink="${3}"
    local _base_dir="${4:-"."}"
    local _mmin="${5-"-60"}"
    if [ ! -d "${_dir}" ]; then
        _dir=$(if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
            realpath $(find -L ${_base_dir%/} -type d \( -name log -o -name logs \) | tr '\n' ' ') | sort | uniq | tr '\n' ' '
        else
            find ${_base_dir%/} -type d \( -name log -o -name logs \)| tr '\n' ' '
        fi 2>/dev/null | tail -n1)
    fi
    [ -n "${_mmin}" ] && _mmin="-mmin ${_mmin}"
    if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
        realpath $(find -L ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' ') | sort | uniq | tr '\n' ' '
    else
        find ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' '
    fi
}

function tail_logs() {
    local __doc__="Tail log files"
    local _log_dir="${1}"
    local _log_file_glob="${2:-"*.log"}"
    tail -n20 -f $(_find_recent "${_log_dir}" "${_log_file_glob}")
}

function grep_logs() {
    local __doc__="Grep (recent) log files"
    local _search_regex="${1}"
    local _log_dir="${2}"
    local _log_file_glob="${3:-"*.log"}"
    local _grep_opts="${4:-"-IrsP"}"
    grep ${_grep_opts} "${_search_regex}" $(_find_recent "${_log_dir}" "${_log_file_glob}")
}

# prettify any strings by checkinbg braces
function prettify() {
    local _str="$1"
    local _pad="${2-"    "}"
    #local _oneline="${3:-Y}"
    #[[ "${_oneline}" =~ ^[yY] ]] && _str="$(echo "${_str}" | tr -d '\n')"
    # TODO: convert to pyparsing (or think about some good regex)
    python -c "import sys
s = '${_str}';n = 0;p = '${_pad}';f = False;
if len(s) == 0:
    for l in sys.stdin:
        s += l
i = 0;
while i < len(s):
    if s[i] in ['(', '[', '{']:
        if (s[i] == '(' and s[i + 1] == ')') or (s[i] == '[' and s[i + 1] == ']') or (s[i] == '{' and s[i + 1] == '}'):
            sys.stdout.write(s[i] + s[i + 1])
            i += 1
        else:
            n += 1
            sys.stdout.write(s[i] + '\n' + (p * n))
            f = True
    elif s[i] in [',']:
        sys.stdout.write(s[i] + '\n' + (p * n))
        f = True
    elif s[i] in [')', ']', '}']:
        n -= 1
        sys.stdout.write('\n' + (p * n) + s[i])
    else:
        sys.stdout.write(s[i])
    if f:
        if (i + 1) < len(s) and s[i + 1] == ' ' and ((i + 2) < len(s) and s[i + 2] != ' '):
            i += 1
    f = False
    i += 1"
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

# Execute multiple commands concurrently. NOTE: seems Mac's xargs has command length limit and no -r to ignore empty line
function _parallel() {
    local _cmds_list="$1"   # File or strings of commands
    local _prefix_cmd="$2"  # eg: '(date;'
    local _suffix_cmd="$3"  # eg: ';date) &> test_$$.out'
    local _num_process="${4:-3}"
    if [ -f "${_cmds_list}" ]; then
        cat "${_cmds_list}"
    else
        echo ${_cmds_list}
    fi | sed '/^$/d' | tr '\n' '\0' | xargs -t -0 -n1 -P${_num_process} -I @@ bash -c "${_prefix_cmd}@@${_suffix_cmd}"
    # Somehow " | sed 's/"/\\"/g'" does not need... why?
}
# Escape characters for Shell
function _escape() {
    local _string="$1"
    printf %q "${_string}"
}
# Grep STDIN with \d\d\d\d-\d\d-\d\d.\d\d:\d (upto 10 mins) and pass to bar_chart
function bar() {
    local _datetime_regex="${1}"
    [ -z "${_datetime_regex}" ] && _datetime_regex="^(\d\d\d\d-\d\d-\d\d.\d\d:\d)"
    #ggrep -oP "${2:-^\d\d\d\d-\d\d-\d\d.\d\d:\d}" ${1-./*} | bar_chart.py
    rg "${_datetime_regex}" -o -r '$1' | sed 's/ /./g' | bar_chart.py
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
    local _dh="${1}"  # docker host IP or L2TP 10.0.1.1
    local _3rd="${2-100}"  # 3rd decimal in network address
    [ -z "${_dh}" ] && _dh="$(ifconfig ppp0 | grep -oE 'inet .+' | awk '{print $4}')" 2>/dev/null
    [ -z "${_dh}" ] && _dh="dh1"

    if [ "Darwin" = "`uname`" ]; then
        [ -n "${_3rd}" ] && ( sudo route delete -net 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 ${_dh} )
        sudo route delete -net 172.17.0.0/24 &>/dev/null;sudo route add -net 172.17.0.0/24 ${_dh}
        sudo route delete -net 172.18.0.0/24 &>/dev/null;sudo route add -net 172.18.0.0/24 ${_dh}
    elif [ "Linux" = "`uname`" ]; then
        [ -n "${_3rd}" ] && ( sudo ip route del 172.17.${_3rd}.0/24 &>/dev/null;sudo route add -net 172.17.${_3rd}.0/24 gw ${_dh} ens3 )
    else    # Assuming windows (cygwin)
        [ -n "${_3rd}" ] && ( route delete 172.17.${_3rd}.0 &>/dev/null;route add 172.17.${_3rd}.0 mask 255.255.255.0 ${_dh} )
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

    local _mv="mv --backup=t"
    [ "Darwin" = "`uname`" ] && _mv="gmv --backup=t"

    ## Special: support_tmp directory wouldn't need to backup
    find ${_src%/} -type d -mtime +30 -name '*_tmp' -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/

    # Delete files larger than _size (10MB) and older than one year
    find ${_src%/} -type f -mtime +365 -size +10000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    # Delete files larger than 60MB and older than 180 days
    find ${_src%/} -type f -mtime +180 -size +60000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    # Delete files larger than 100MB and older than 90 days
    find ${_src%/} -type f -mtime +90 -size +100000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    # Delete files larger than 500MB and older than 60 days
    find ${_src%/} -type f -mtime +60 -size +500000k -print0 | xargs -0 -t -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    wait
    # Sync all files smaller than _size (10MB), means *NO* backup for files over 10MB.
    rsync -Pvaz --bwlimit=10240 --max-size=10000k --modify-window=1 ${_src%/}/ ${_dst%/}/
}
function push2search() {
    local _force="$1"
    # May need to configure .ssh/config to specify the private key
    local _cmd="rsync -vrc --exclude '.git' --exclude '.idea' --exclude '*.md' $HOME/IdeaProjects/search/ search.osakos.com:~/www/search/"
    if [[ "${_force}" =~ ^[yY] ]]; then
        eval "${_cmd}"
        return $?
    fi
    eval "${_cmd} -n"
    echo ""
    read -p "Are you sure?: " "_yes"
    echo ""
    [[ "${_yes}" =~ ^[yY] ]] && eval "${_cmd}"
}


## Work specific functions
function pubS() {
    scp -C $HOME/IdeaProjects/work/bash/install_sonatype.sh dh1:/var/tmp/share/sonatype/
    cp -f $HOME/IdeaProjects/work/bash/install_sonatype.sh $HOME/share/sonatype/
    date
}
function sync_nexus_binaries() {
    # Currently only IQ ...
    rsync -Prc root@dh1:/var/tmp/share/sonatype/nexus-iq-server-*-bundle.tar.gz $HOME/.nexus_executable_cache/
    rsync -Prc $HOME/.nexus_executable_cache/nexus-iq-server-*-bundle.tar.gz root@dh1:/var/tmp/share/sonatype/
}
function sptBoot() {
    local _zip="$1"
    [ -s $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py ] || return 1
    if [ -z "${_zip}" ]; then
        _zip="$(ls -1 ./support-20*.zip | tail -n1)" || return $?
        echo "Using ${_zip} ..."
    fi
    echo "To just re-launch or start, check relaunch-support.sh"
    echo "To use docker with https:\
    cp $HOME/IdeaProjects/samples/misc/standalone.localdomain.jks ./$(basename "${_zip}" .zip)_tmp/sonatype-work/nexus3/etc/ssl/keystore.jks"
    python3 $HOME/IdeaProjects/nexus-toolbox/support-zip-booter/boot_support_zip.py -cr "${_zip}" ./$(basename "${_zip}" .zip)_tmp
}
function iqCli() {
    # https://help.sonatype.com/display/NXI/Nexus+IQ+CLI
    local _iq_url="${_IQ_URL:-"http://dh1.standalone.localdomain:8070/"}"
    if [ -z "$1" ]; then
        iqCli "./"
        return $?
    fi
    java -jar /Users/hosako/Apps/iq-clis/nexus-iq-cli.jar -i "sandbox-application" -s "${_iq_url}" -a "admin:admin123" -X $@
}
function iqMvn() {
    # https://help.sonatype.com/display/NXI/Sonatype+CLM+for+Maven
    mvn com.sonatype.clm:clm-maven-plugin:evaluate -Dclm.additionalScopes=test,provided,system -Dclm.applicationId=sandbox-application -Dclm.serverUrl=http://dh1.standalone.localdomain:8070/ -Dclm.username=admin -Dclm.password=admin123
}
function mvn-get() {
    # maven/mvn get/download
    local _gav="$1"
    local _repo="$2"
    local _localrepo="$3"
    local _options="-Dtransitive=false"
    # -Dmaven.repo.local=./repo_local
    [ -n "${_repo}" ] && _options="${_options% } -Dmaven.repo.remote=${_repo}"
    [ -n "${_localrepo}" ] && _options="${_options% } -Dmaven.repo.local=${_localrepo}"
    mvn dependency:get ${_options} -Dartifact=$@ -X
}

# To patch nexus (so that checking /system) but probably no longer using.
function _patch() {
    local _java_file="${1}"
    local _jar_file="${2}"
    local _base_dir="${3:-"."}"
    if [ -z "${_java_file}" ] || [ ! -f "${_java_file}" ]; then
        return 1
    fi
    if [ ! -s $HOME/IdeaProjects/samples/bash/patch_java.sh ]; then
        return 1
    fi
    if [ -z "${_jar_file}" ]; then
        _jar_file="$(find ${_base_dir%/} -type d -name system -print | head -n1)"
    fi
    if [ -z "${CLASSPATH}" ]; then
        echo "old CLASSPATH=${CLASSPATH}"
    fi
    export CLASSPATH=`find ${_base_dir%/} -path '*/system/*' -type f -name '*.jar' | tr '\n' ':'`.
    bash $HOME/IdeaProjects/samples/bash/patch_java.sh "" ${_java_file} ${_jar_file}0
}