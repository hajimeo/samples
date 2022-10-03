# source /dev/stdin <<< "(curl https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_aliases.sh --compressed)"

## Simple/generic alias commands (some need pip though) ################################################################
# 'cd' to last modified directory
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias fd='find . -name'
alias sha1R='find . -type f -exec sha1sum "{}" \;'
alias fcv='fc -e vim'
alias vim0='vim -u NONE'   # handy when you process large text
# 'time' with format
alias timef='/usr/bin/time -f"[%Us user %Ss sys %es real %MkB mem]"' # brew install gnu-time --with-default-names
# In case 'tree' is not installed
type tree &>/dev/null || alias tree="pwd;find . | sort | sed '1d;s/^\.//;s/\/\([^/]*\)$/|-- \1/;s/\/[^/|]*/|  /g'"
# Debug network performance with curl
alias curld='curl -w "\ntime_namelookup:\t%{time_namelookup}\ntime_connect:\t%{time_connect}\ntime_appconnect:\t%{time_appconnect}\ntime_pretransfer:\t%{time_pretransfer}\ntime_redirect:\t%{time_redirect}\ntime_starttransfer:\t%{time_starttransfer}\n----\ntime_total:\t%{time_total}\nhttp_code:\t%{http_code}\nspeed_download:\t%{speed_download}\nspeed_upload:\t%{speed_upload}\n"'
# output the longest line *number* as wc|gwc -L does not show the line number
alias wcln="awk 'length > max_length { max_length = length; longest_line_num = NR } END { print longest_line_num }'"
# Sum integer in a column by using paste (which concatenates files or characters(+))
#alias sum_cols="gpaste -sd+ | bc"
alias sum_cols="paste -sd+ - | bc"
# diff side-by-side ignoring whitespace diff
alias diffY="diff -wy --suppress-common-lines"
type mdfind &>/dev/null && alias mdfindN="mdfind kMDItemFSName="
type mdfind &>/dev/null && alias mdfindSize="mdfind 'kMDItemFSSize > 209715200 && kMDItemContentModificationDate < \$time.now(-2419200)' | while read -r _l;do ls -lh \"\${_l}\"; done | sort -k5 -h | tail -n20"
alias noalnum='tr -cd "[:alnum:]._-"'
alias gzipk='gzip -k'
# Configure .ssh/config. Not using -f and autossh
alias s5proxy='netstat -tln | grep -E ":38080\s+" || ssh -4gC2TxnN -D38080'
#sudo mdutil -d /Volumes/Samsung_T5
# not using sudo which may generate error if /var/db/locate.database is not accessible
[ -s /usr/libexec/locate.updatedb ] && alias updatedb='sudo FILESYSTEMS="hfs ufs apfs exfat" /usr/libexec/locate.updatedb'

## Git #################################################################################################################
# Show current tag
alias git_tag_crt='git describe --tags'
alias git_crt_tag='git describe --tags'
alias git_tag_hash='git tag --contains'
# compare tags
function git_comp_tags() {
    local _tag1="$1"
    local _tag2="$2"
    local _diff="$3"
    local _fetched="$(find . -maxdepth 3 -type f -name "FETCH_HEAD" -mmin -60 -print 2>/dev/null)"
    if [ -z "${_fetched}" ]; then
        git fetch
    fi
    if [ -z "${_tag2}" ]; then
        git tag --list ${_tag1} | tail
    else
        if [[ "${_diff}" =~ ^[yY] ]]; then
            git diff ${_tag1} ${_tag2}
        else
            git log ${_tag1} ${_tag2}
        fi
    fi
}
# find branches or tags which contains a commit
function git_search() {
    local _search="$1"
    for c in $(git log --all --grep "$_search" | grep ^commit | cut -d ' ' -f 2); do git branch -r --contains $c; done
    for c in $(git log --all --grep "$_search" | grep ^commit | cut -d ' ' -f 2); do git tag --contains $c; done
}

## Python ##############################################################################################################
#virtualenv -p python3 $HOME/.pyvenv
alias pyv='source $HOME/.pyvenv/bin/activate'
alias pyv39='source $HOME/.pyvenv39/bin/activate'
#alias pyv='pyenv activate mypyvenv'    # I felt pyenv is slow, so not using
alias urldecode='python2 -c "import sys, urllib as ul; print(ul.unquote_plus(sys.argv[1]))"'
alias urlencode3='python3 -c "import sys;from urllib import parse; print(parse.quote(sys.argv[1]))"'
alias urlencode='python2 -c "import sys, urllib as ul; print(ul.quote(sys.argv[1]))"'
# base64 encode/decode (coreutils base64 or openssl base64 -e|-d)
alias b64encode='python3 -c "import sys, base64; print(base64.b64encode(sys.argv[1].encode(\"utf-8\")).decode())"'
#alias b64encode='python -c "import sys, base64; print(base64.b64encode(sys.argv[1]))"'
alias b64decode='python3 -c "import sys, base64; print(base64.b64decode(sys.argv[1]).decode())"'                                                                                   # .decode() to remove "b'xxxx"
# require python3
alias htmlencode="python -c \"import sys,html;print(html.escape(sys.argv[1]))\""
alias htmldecode="python -c \"import sys,html;print(html.unescape(sys.argv[1]))\""
alias utc2int='python3 -c "import sys,time,dateutil.parser;from datetime import timezone;print(int(dateutil.parser.parse(sys.argv[1]).replace(tzinfo=timezone.utc).timestamp()))"' # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python -c "import sys,datetime;print(datetime.datetime.utcfromtimestamp(int(sys.argv[1][0:10])).strftime(\"%Y-%m-%dT%H:%M:%S\")+\".\"+sys.argv[1][10:13]+\"Z\")"'
#alias int2utc='python -c "import sys,time;print(time.asctime(time.gmtime(int(sys.argv[1])))+\" UTC\")"'
alias dec2hex='printf "%x\n"'
alias hex2dec='printf "%d\n"'
#alias python_i_with_pandas='python -i <(echo "import sys,json;import pandas as pd;f=open(sys.argv[1]);jd=json.load(f);df=pd.DataFrame(jd);")'   # Start python interactive after loading json object in 'df' (pandas dataframe)
alias python_i_with_pd_json='python3 -i <(echo "import sys,json;import pandas as pd;df=pd.read_json(sys.argv[1]);print(df)")' # to convert list/dict pdf.values.tolist()
alias python_i_with_pd_csv='python3 -i <(echo "import sys;import pandas as pd;df=pd.read_csv(sys.argv[1],escapechar=\"\\\\\", index_col=False);print(df)")'
alias python_i_with_json='python3 -i <(echo "import sys,json;js=json.load(open(sys.argv[1]));print(\"js\");")'
alias json2csv='python3 -c "import sys,json;import pandas as pd;pdf=pd.read_json(sys.argv[1]);pdf.to_csv(sys.argv[1]+\".csv\", header=True, index=False)"'
# Read xml file, then convert to dict, then print json
alias xml2json='python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))"'
# simplest json pretty print
alias pjt='sed "s/,$//" | while read -r _l;do echo "${_l}" | python -m json.tool; done'
# this one is from a *JSON* file
#alias prettyjson='python3 -c "import sys,json;print(json.dumps(json.load(open(sys.argv[1])), indent=4, sort_keys=True))"'
# echo "json like string" | prettyjson
alias prettyjson='while read -r _l; do echo "${_l}" | sed "s/,$//" | python3 -c "import sys,json;print(json.dumps(json.loads(sys.stdin.read()), indent=4, sort_keys=True))";echo "--";done'
# Pretty|Tidy print XML. NOTE: without encoding, etree.tostring returns bytes, which does not work with print()
#alias prettyxml='python3 -c "import sys;from lxml import etree;t=etree.parse(sys.argv[1].encode(\"utf-8\"));print(etree.tostring(t,encoding=\"unicode\",pretty_print=True))"'
#alias prettyxml='xmllint --format'
# echo "xml like string" | prettyxml
alias prettyxml='python3 -c "import sys;from lxml import etree;t=etree.fromstring(sys.stdin.read());print(etree.tostring(t,encoding=\"unicode\",pretty_print=True))"'
# TODO: find with sys.argv[2] (no ".//"), then output as string
alias xml_get='python3 -c "import sys;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();print(r.find(sys.argv[2],namespaces=r.nsmap))"'
# Search with 2nd arg and output the path(s)
alias xml_path='python -c "import sys,pprint;from lxml import etree;t=etree.parse(sys.argv[1]);r=t.getroot();pprint.pprint([t.getelementpath(x) for x in r.findall(\".//\"+sys.argv[2],namespaces=r.nsmap)])"'
# Strip XML / HTML to get text. NOTE: using sys.stdin.read. (TODO: maybe </br> without new line should add new line)
alias strip_tags='python3 -c "import sys,html,re;rx=re.compile(r\"<[^>]+>\");print(html.unescape(rx.sub(\"\",sys.stdin.read())))"'
alias escape4json='python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))"'
alias jp='pyv && jupyter-lab &> /tmp/jupyter-lab.out &'
alias jn='pyv && jupyter-notebook &> /tmp/jupyter-notebook.out &'

## Common software/command but need to install #######################################################################
type docker &>/dev/null && alias docker_stop="docker stop -t 120"  # 10 seconds is too short
#alias rdocker="DOCKER_HOST='tcp://dh1:2375' docker"
alias rdocker="ssh dh1 docker"
type podman &>/dev/null && alias podmand="podman --log-level debug" && alias podman_login="podman --log-level debug login --tls-verify=false" && alias podman_pull="podman --log-level debug pull --tls-verify=false" && alias podman_push="podman --log-level debug push --tls-verify=false"
alias podman_delete_all='podman system prune --all'    # --force && podman rmi --all
type q &>/dev/null && alias qcsv='q -O -d"," -T --disable-double-double-quoting'
type pgbadger &>/dev/null && alias pgbg='pgbadger --timezone 0'
type microk8s &>/dev/null && alias kubectl="microk8s kubectl"

## Non default (need to install some complex software and/or develop script) alias commands ############################
# Load/source my own searching utility functions / scripts
#mkdir -p $HOME/IdeaProjects/samples/bash; curl -o $HOME/IdeaProjects/samples/bash/log_search.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
if [ -d $HOME/IdeaProjects/samples/bash ]; then
    alias logT="pyv; source $HOME/IdeaProjects/samples/bash/log_tests.sh"
    alias logTest="pyv;$HOME/IdeaProjects/samples/bash/log_tests.sh"
    alias setNexus="source $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh"
    alias ss="bash $HOME/IdeaProjects/samples/bash/setup_standalone.sh"
fi
if [ -d $HOME/IdeaProjects/work/bash ]; then
    alias logS="pyv; source $HOME/IdeaProjects/work/bash/log_search.sh"
    alias logN="logT; source $HOME/IdeaProjects/work/bash/log_tests_nxrm.sh"
    alias logNxrm="pyv;$HOME/IdeaProjects/work/bash/log_tests_nxrm.sh"
    alias instSona="source $HOME/IdeaProjects/work/bash/install_sonatype.sh"
fi
#alias xmldiff="python $HOME/IdeaProjects/samples/python/xml_parser.py" # this is for Hadoop xml files

# VM related
# virt-manager remembers the connections, so normally would not need to start in this way.
alias kvm='virt-manager -c "qemu+ssh://virtuser@dh1/system?socket=/var/run/libvirt/libvirt-sock" &>/tmp/virt-manager.out &'

# Java / jar related
#alias mb='java -jar $HOME/Apps/metabase.jar &>/tmp/metabase.out &'    # port is 3000
alias vnc='java -Xmx2g -jar $HOME/Apps/tightvnc-jviewer.jar &>/tmp/vnc-java-viewer.out &'
#alias vnc='java -jar $HOME/Applications/VncViewer-1.9.0.jar &>/tmp/vnc-java-viewer.out &'
alias samurai='java -Xmx4g -jar $HOME/Apps/samurali/samurai.jar &>/tmp/samurai.out &'
alias tda='java -Xmx4g -jar $HOME/Apps/tda-bin-2.4/tda.jar &>/tmp/tda.out &'    #https://github.com/irockel/tda/releases/latest
alias gcviewer='java -Xmx4g -jar $HOME/Apps/gcviewer/gcviewer-1.36.jar' # &>/tmp/gcviewer.out & # Mac can't stop this so not put in background
alias gitbucket='java -jar gitbucket.war &> /tmp/gitbucket.out &'   #https://github.com/gitbucket/gitbucket/releases/download/4.34.0/gitbucket.war
alias groovyi='groovysh -e ":set interpreterMode true"'
alias jenkins='java -jar $HOME/Apps/jenkins.war'  #curl -o $HOME/Apps/jenkins.war -L https://get.jenkins.io/war-stable/<version>/jenkins.war
# http (but https fails) + reverse proxy server https://www.mock-server.com/mock_server/getting_started.html
alias mockserver='java -jar $HOME/Apps/mockserver-netty.jar'  #curl -o $HOME/Apps/mockserver-netty.jar -L https://search.maven.org/remotecontent?filepath=org/mock-server/mockserver-netty/5.11.1/mockserver-netty-5.11.1-jar-with-dependencies.jar
alias jkCli='java -jar $HOME/Apps/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin123' #curl -o $HOME/Apps/jenkins-cli.jar -L http://localhost:8080/jnlpJars/jenkins-cli.jar
[ -f /var/tmp/share/java/orient-console.jar ] && alias orient-console="java -jar /var/tmp/share/java/orient-console.jar"
[ -f /var/tmp/share/java/blobpath.jar ] && alias blobpathJ="java -jar /var/tmp/share/java/blobpath.jar"

# Chrome aliases for Mac (URL needs to be IP as hostname wouldn't be resolvable on remote)
#alias shib-local='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/local --proxy-server=socks5://localhost:28081'
#alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=socks5://dh1:28081 http://192.168.1.31:4200/webuser/'
alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=http://dh1:28080 http://192.168.1.31:4200/webuser/'
alias k8s-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/k8s-dh1 --proxy-server=socks5://dh1:38081'
alias hblog='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/hajigle https://www.blogger.com/blogger.g?blogID=9018688091574554712&pli=1#allposts'
# pretending windows chrome on Linux
alias winchrome='/opt/google/chrome/chrome --user-data-dir=$HOME/.chromep --proxy-server=socks5://localhost:38080  --user-agent="Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.96 Safari/537.36"'

# Work specific aliases
alias hwxS3='s3cmd ls s3://private-repo-1.hortonworks.com/HDP/centos7/2.x/updates/'
# TODO: public-repo-1.hortonworks.com private-repo-1.hortonworks.com
# Slack API Search
# python3 -m http.server
[ -s $HOME/IdeaProjects/samples/python/SimpleWebServer.py ] && alias slackS="pyv && cd $HOME/IdeaProjects/samples/python/ && python3 ./SimpleWebServer.py &> /tmp/SimpleWebServer.out &"
alias smtpdemo='python -m smtpd -n -c DebuggingServer localhost:2500'

### Functions (some command syntax does not work with alias eg: sudo) ##################################################
function fcat() {
    local _name="$1"
    local _find_all="$2"
    local _max_depth="${3:-"7"}"
    local _result=1
    # Accept not only file name but also /<dir>/<filename> so that using grep
    for _f in `find . -maxdepth ${_max_depth} -type f -print | grep -w "${_name}$"`; do
        echo "# ${_f}" >&2
        cat "${_f}" && _result=0
        [[ "${_find_all}" =~ ^(y|Y) ]] || break
        echo ''
    done
    return ${_result}
}

function lns() {
    if [ -L "$2" ]; then rm -i "$2" || return $?; fi
    if [ -d "$2" ]; then rmdir "$2" || return $?; fi
    ln -v -s "$(realpath "$1")" "$(realpath "$2")"
}

function unzips() {
    for _f in "$@"; do
        local _dir_name="$(basename "${_f}" .zip)"
        if unzip -l "${_f}" | grep -q "${_dir_name}"; then
            unzip "${_f}"
        else
            unzip -d "${_dir_name}" "${_f}"
        fi || return $?
    done
}

function random_list() {
    eval "IFS=\" \" read -a _list <<< \"${1}\""
    local _rand=$[$RANDOM % ${#_list[@]}]
    echo "${_list[${_rand}]}"
}

function datems() {
    local _cmd="date"
    type gdate &>/dev/null && _cmd="gdate"
    ${_cmd} +"%F %T.%3N"
}
# eg: date_calc "17:15:02.123 -262.708 seconds" or " 30 days ago"
function date_calc() {
    local _d_opt="$1"
    local _d_fmt="${2:-"%Y-%m-%d %H:%M:%S.%3N"}" #%d/%b/%Y:%H:%M:%S
    local _cmd="date"
    which gdate &>/dev/null && _cmd="gdate"
    ${_cmd} -u +"${_d_fmt}" -d"${_d_opt}"
}
#eg: time_calc_ms "02:30:00" 39381000 to add milliseconds to the hh:mm:ss
function time_calc_ms() {
    local _time="$1" #hh:mm:ss.sss
    local _ms="$2"
    local _sec=$(bc <<<"scale=3; ${_ms} / 1000")
    if [[ ! "${_sec}" =~ ^[+-] ]]; then
        _sec="+${_sec}"
    fi
    date_calc "${_time} ${_sec} seconds"
}
# Obfuscate string (encode/decode)
# How-to: echo -n "your secret word" | obfuscate "your salt"
function obfuscate() {
    local _salt="$1"
    # -pbkdf2 does not work with 1.0.2 on CentOS. Should use -aes-256-cbc?
    # 2>/dev/null to hide WARNING : deprecated key derivation used.
    openssl enc -aes-128-cbc -md sha256 -salt -pass pass:"${_salt}" 2>/dev/null
}
# cat /your/secret/file | deobfuscate "your salt"
function deobfuscate() {
    local _salt="$1"
    openssl enc -aes-128-cbc -md sha256 -salt -pass pass:"${_salt}" -d 2>/dev/null
}
# Merge split/multiple zip files to one file
function merge_zips() {
    local _first_file="$1"
    zip -FF ${_first_file} --output ${_first_file%.*}.merged.zip
}
# head and tail of one file or multiple files "aaaa-*.log" (need quotes)
function head_tail() {
    for _f in "$@"; do
        echo "# ${_f}" >&2
        _head_tail "${_f}" "1"
    done
}
function _head_tail() {
    local _f="$1"
    local _n="${2:-"1"}"
    if [[ "${_f}" =~ \.(log|csv) ]]; then
        local _tac="tac"
        which gtac &>/dev/null && _tac="gtac"
        rg '(^\d\d\d\d-\d\d-\d\d|\d\d.[a-zA-Z]{3}.\d\d\d\d).\d\d:\d\d:\d\d' -m ${_n} ${_f}
        ${_tac} ${_f} | rg '(^\d\d\d\d-\d\d-\d\d|\d\d.[a-zA-Z]{3}.\d\d\d\d).\d\d:\d\d:\d\d' -m ${_n}
    else
        head -n ${_n} "${_f}"
        tail -n ${_n} "${_f}"
    fi
}
# Handy to check f_threads analysed / separated files
function tail_head() {
    local _glob="$1"    # NOTE: need double quotes
    local _tn="${2:-"1"}"
    local _hn="${3:-"${_tn}"}"
    ls -1 ${_glob} | while read -r _f; do
        echo "==> ${_f} <=="
        tail -n ${_tn} "${_f}" | head -n ${_hn}
        echo " "
    done
}
# To display every Nth line from a file
function every_Nth() {
    local _Nth="$1"
    local _file="$2"
    awk "NR % ${_Nth} == 0" "${_file}"
}

# make a directory and cd
function mcd() {
    local _path="$1"
    mkdir "${_path}"
    cd "${_path}"
}
function jsondiff() {
    local _f1="$(echo $1 | sed -e 's/^.\///' -e 's/[/]/_/g')"
    local _f2="$(echo $2 | sed -e 's/^.\///' -e 's/[/]/_/g')"
    # alternative https://json-delta.readthedocs.io/en/latest/json_diff.1.html
    python3 -c "import sys,json;print(json.dumps(json.load(open('${_f1}')), indent=4, sort_keys=True))" >"/tmp/${_f1}" || return $?
    python3 -c "import sys,json;print(json.dumps(json.load(open('${_f2}')), indent=4, sort_keys=True))" >"/tmp/${_f2}" || return $?
    #prettyjson $2 > "/tmp/${_f2}"
    vimdiff "/tmp/${_f1}" "/tmp/${_f2}"
}
function xmldiff() {
    python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))" $1 >/tmp/xmldiff1_$$.json || return $?
    python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))" $2 >/tmp/xmldiff2_$$.json || return $?
    vimdiff /tmp/xmldiff1_$$.json /tmp/xmldiff2_$$.json
}
# Convert yml|yaml file to a sorted json. Can be used to validate yaml file
function yaml2json() {
    local _yaml_file="${1}"
    # pyyaml doesn't like ********
    cat "${_yaml_file}" | sed 's/\*\*+/__PASSWORD__/g' | python3 -c 'import sys, json, yaml
try:
    print(json.dumps(yaml.safe_load(sys.stdin), indent=4, sort_keys=True))
except yaml.YAMLError as e:
    sys.stderr.write(e+"\n")
'
}
# surprisingly it's not easy to trim|remove all newlines with bash
function rmnewline() {
    python -c 'import sys
for l in sys.stdin:
   sys.stdout.write(l.rstrip("\n"))'
}
# Find recently modified (log) files
function _find_recent() {
    local _dir="${1}"
    local _file_glob="${2:-"*.log"}"
    local _follow_symlink="${3}"
    local _base_dir="${4:-"."}"
    local _mmin="${5-"-60"}"
    if [ ! -d "${_dir}" ]; then
        _dir=$(if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
            realpath $(find -L ${_base_dir%/} -type d \( -name log -o -name logs \) | tr '\n' ' ') | sort | uniq | tr '\n' ' '
        else
            find ${_base_dir%/} -type d \( -name log -o -name logs \) | tr '\n' ' '
        fi 2>/dev/null | tail -n1)
    fi
    [ -n "${_mmin}" ] && _mmin="-mmin ${_mmin}"
    if [[ "${_follow_symlink}" =~ ^(y|Y) ]]; then
        realpath $(find -L ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' ') | sort | uniq | tr '\n' ' '
    else
        find ${_dir} -type f -name "${_file_glob}" ${_mmin} | tr '\n' ' '
    fi
}
# Tail recnetly modified log files
function tail_logs() {
    local _log_dir="${1}"
    local _log_file_glob="${2:-"*.log"}"
    tail -n20 -f $(_find_recent "${_log_dir}" "${_log_file_glob}")
}
# Grep only recently modified files (TODO: should check if ggrep or rg is available)
function grep_logs() {
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
s = '''${_str}''';n = 0;p = '${_pad}';f = False;
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
    i += 1
print('')"
}
# Grep against jar file to find a class ($1)
function jargrep() {
    local _cmd="jar -tf"
    which jar &>/dev/null || _cmd="less"
    find -L ${2:-./} -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "${_cmd} {} | grep -wi '$1' && echo {}"
}
# from https://stackoverflow.com/questions/54920113/calculate-average-execution-time-of-a-program-using-bash
function avg_time() {
    #
    # usage: avg_time n command ...
    #
    n=$1; shift
    (($# > 0)) || return                   # bail if no command given
    for ((i = 0; i < n; i++)); do
        { time -p "$@" &>/dev/null; } 2>&1 # ignore the output of the command
                                           # but collect time's output in stdout
    done | awk '
        /real/ { real = real + $2; nr++ }
        /user/ { user = user + $2; nu++ }
        /sys/  { sys  = sys  + $2; ns++}
        END    {
                 if (nr>0) printf("real %f\n", real/nr);
                 if (nu>0) printf("user %f\n", user/nu);
                 if (ns>0) printf("sys %f\n",  sys/ns)
               }'
}
# convert .mov file to .gif
function mov2gif() {
    local _in="$1"
    local _out="$2"
    # based on https://gist.github.com/dergachev/4627207
    [ -z "${_out}" ] && _out="$(basename "${_in}" ".mov").gif"
    if which gifsicle &>/dev/null; then
        ffmpeg -i "${_in}" -pix_fmt rgb24 -r 6 -f gif - | gifsicle --optimize=3 --delay=5 >"${_out}"
    else
        ffmpeg -i "${_in}" -pix_fmt rgb24 -r 6 -f gif "${_out}"
    fi
}
# Grep STDIN with \d\d\d\d-\d\d-\d\d.\d\d:\d (upto 10 mins) and pass to bar_chart
function bar() {
    local _time_regex="${1}" # Below line was intentional as \ will be removed in ":-"
    local _file="${2}"
    [ -z "${_time_regex}" ] && _time_regex="\d\d:\d"
    #ggrep -oP "${_datetime_regex}" | sed 's/ /./g' | bar_chart.py
    rg "(^\"?20\d\d-\d\d-\d\d|\"timestamp\":\"20\d\d-\d\d-\d\d|\d\d.[A-Z][a-z]{2}.20\d\d).${_time_regex}" -o ${_file} | sed 's/ /./g' | bar_chart.py
}
# Start Jupyter Lab as service
function jpl() {
    local _dir="${1:-"."}"
    local _kernel_timeout="${2-10800}"
    local _shutdown_timeout="${3-115200}"

    local _conf="$HOME/.jupyter/jpl_tmp_config.py"
    local _log="/tmp/jpl_${USER}_$$.out"
    if [ ! -d "$HOME/.jupyter" ]; then mkdir "$HOME/.jupyter" || return $?; fi
    >"${_conf}"
    [[ "${_kernel_timeout}" =~ ^[0-9]+$ ]] && echo "c.MappingKernelManager.cull_idle_timeout = ${_kernel_timeout}" >>"${_conf}"
    [[ "${_shutdown_timeout}" =~ ^[0-9]+$ ]] && echo "c.NotebookApp.shutdown_no_activity_timeout = ${_shutdown_timeout}" >>"${_conf}"

    echo "Redirecting STDOUT / STDERR into ${_log}" >&2
    nohup jupyter lab --ip=$(hostname -I | cut -d ' ' -f1) --no-browser --config="${_conf}" --notebook-dir="${_dir%/}" 2>&1 | tee "${_log}" | grep -m1 -oE "http://$(hostname -I | cut -d ' ' -f1):.+token=.+" &
}
# Mac only: Start Google Chrome in incognito with proxy
function chromep() {
    local _host_port="${1:-"192.168.6.163:28081"}"
    local _url=${2}
    local _port=${3:-28081}

    local _host="${_host_port}"
    if [[ "${_host_port}" =~ ^([a-zA-Z0-9.-]+):([0-9]+)$ ]]; then
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
    local _dh="${1}" # docker host IP or L2TP 10.0.1.1
    local _network_addrs="${2:-"172.17.0.0 172.18.0.0 172.17.100.0 10.1.25.0"}" # last one is for K8s pods
    [ -z "${_dh}" ] && _dh="$(ifconfig ppp0 | grep -oE 'inet .+' | awk '{print $4}')" 2>/dev/null
    [ -z "${_dh}" ] && _dh="dh1.standalone.localdomain"

    for _addr in ${_network_addrs}; do
        if [ "Darwin" = "$(uname)" ]; then
            # NOTE: Always using /24 because L2TP VPN assigns IP 172.31.0.x to this PC
            sudo route delete -net ${_addr}/24 &>/dev/null
            sudo route add -net ${_addr}/24 ${_dh}
        elif [ "Linux" = "$(uname)" ]; then
            sudo ip route del ${_addr}/24 &>/dev/null
            sudo route add -net ${_addr}/24 gw ${_dh} ens3
        else # Assuming windows (cygwin)
            route delete ${_addr} &>/dev/null
            route add ${_addr} mask 255.255.255.0 ${_dh}
        fi
    done
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
function ssh_remote_mount() {
    local _user="${1:-"$USER"}"
    local _src="${2:-"/Users/${_user}"}"    # expecting Mac...
    local _tgt="${3}"
    [ -z "${SSH_CONNECTION}" ] && return 1
    local _remote_host="$(echo ${SSH_CONNECTION} | cut -d" " -f1)"
    [ -z "${_tgt}" ] && _tgt="$HOME/mnt/${_remote_host}"
    if [ ! -d "${_tgt}" ]; then
        mkdir -v -p -m 777 ${_tgt} || return $?
    fi
    eval sshfs -o uid=$UID,umask=002,reconnect,follow_symlinks ${_user}@${_remote_host}:${_src} ${_tgt}
}
# My personal dirty ssh shortcut (cd /var/tmp/share/sonatype/logs/node-nxiq_nxiq)
alias _ssh='ssh $(basename "$PWD" | cut -d"_" -f1)'

# Start PostgreSQL (on Mac)
# NOTE: if brew upgraded postgresql, may need to run 'brew postgresql-upgrade-database'
function pgStart() {
    local _cmd="${1:-"status"}"
    local _pg_data="${2:-"/usr/local/var/postgres"}"
    local _log_path="${3:-"$HOME/postgresql.log"}"
    if [ "${_cmd}" == "start" ] && [ -n "${_log_path}" ] && [ -s "${_log_path}" ]; then
        if mv -v ${_log_path} /tmp/; then
            gzip -S _$(date +'%Y%m%d%H%M%S').gz /tmp/$(basename ${_log_path}) &>/dev/null &
        fi
    fi
    if [ -n "${_log_path}" ]; then
        pg_ctl -D ${_pg_data} -l ${_log_path} ${_cmd}
    else
        pg_ctl -D ${_pg_data} ${_cmd}
    fi
    # To connect: psql template1
    # If 'The data directory was initialized by PostgreSQL version', then brew postgresql-upgrade-database
    # and also check postgresql.conf : listen_addresses
}

# Start a dummy web server for webhook POST receiver
# TODO: PUT is not working because of 0 content length (which is for POST), and can't kill on Mac
function ncWeb() {
    local _port="${1:-"2222"}"
    local _http_status="${2:-"200 OK"}" # 400 Bad Request
    local _last_mod="$(type gdate &>/dev/null && gdate --rfc-2822 || date --rfc-2822)" || return $?
    while true; do
        echo -e "HTTP/1.1 ${_http_status}\nDate: $(type gdate &>/dev/null && gdate --rfc-2822 || date --rfc-2822)\nServer: ncWeb\nLast-Modified: ${_last_mod}\nContent-Length: 0\n\n" | nc -v -v -n -l -p ${_port}
        echo -e "\n"
    done
}

# backup & cleanup (backing up files smaller than 10MB only)
function backupC() {
    local _src="${1:-"$HOME/Documents/cases"}"
    local _dst="${2-"/Volumes/D512/hajime/cases"}"  # if not specified, delete only
    #local _dst="${2-"hosako@z230:/cygdrive/h/hajime/cases"}"

    if which code && [ -d "$HOME/backup" ]; then
        code --list-extensions | xargs -L 1 echo code --install-extension >$HOME/backup/vscode_install_extensions.sh
    fi
    if [ -s /etc/hosts ] && [ -d "$HOME/backup" ]; then
        cp -v -f /etc/hosts $HOME/backup/etc_hosts
    fi

    [ ! -d "${_src}" ] && return 11
    [ ! -d "$HOME/.Trash" ] && return 12

    ## Special: support_tmp directory or .tmp or .out file wouldn't need to backup (not using atime as directory doesn't work)
    # NOTE: xargs may not work with very long file name 'mv: rename {} to /Users/hosako/.Trash/{}: No such file or directory'
    _src="$(realpath "${_src}")"    # because find -L ... -delete does not work
    find ${_src%/} -type f -mtime +7 -size 0 \( ! -name "._*" \) -print -delete 2>/dev/null &
    find ${_src%/} -type d -mtime +14 -name '*_tmp' -print -delete 2>/dev/null &
    find ${_src%/} -type f -mtime +14 -name '*.tmp' -print -delete 2>/dev/null &
    find ${_src%/} -type f -mtime +60 -name "*.log" -print -delete 2>/dev/null &
    find ${_src%/} -type f -mtime +90 -size +128000k -print -delete 2>/dev/null &
    find ${_src%/} -type f -mtime +180 -print -delete 2>/dev/null &
    # NOTE: this find command requires "/*"
    if [ "Darwin" = "$(uname)" ]; then
        gfind ${_src%/}/* -type d -mtime +2 -empty -print -delete 2>/dev/null &
    else
        find ${_src%/}/* -type d -mtime +2 -empty -print -delete 2>/dev/null &
    fi
    wait

    #local _mv="mv --backup=t"
    #[ "Darwin" = "$(uname)" ] && _mv="gmv --backup=t"
    #find ${_src%/} -type f -mtime +360 -size +100k -print0 | xargs -0 -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    #find ${_src%/} -type f -mtime +270 -size +10240k -print0 | xargs -0 -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    #find ${_src%/} -type f -mtime +180 -size +1024000k -print0 | xargs -0 -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    #find ${_src%/} -type f -mtime +90  -size +2048000k -print0 | xargs -0 -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    #find ${_src%/} -type f -mtime +45 -size +4048000k -print0 | xargs -0 -n1 -I {} ${_mv} "{}" $HOME/.Trash/ &
    wait

    # Sync all files smaller than _size (10MB), means *NO* backup for files over 10MB.
    if [ -n "${_dst}" ]; then
        if [[ "${_dst}" =~ @ ]]; then
            rsync -Pvaz --bwlimit=10240 --max-size=10000k --modify-window=1 --exclude '*_tmp' --exclude '_*' ${_src%/}/ ${_dst%/}/
        elif [ "${_dst:0:1}" == "/" ]; then
            #mkdir -p "${_dst%/}"
            if [ -d "${_dst%/}" ]; then
                # if (looks like) local disk, slightly larger size, and no -z, no --bwlimit
                rsync -Pva --max-size=30000k --modify-window=1 --exclude '*_tmp' --exclude '_*' ${_src%/}/ ${_dst%/}/
            fi
        fi
    fi

    if [ "Darwin" = "$(uname)" ]; then
        echo "#mdfind 'kMDItemFSSize > 209715200 && kMDItemContentModificationDate < \$time.now(-2419200)' | LC_ALL=C sort"   # -onlyin "${_src}"
        mdfind 'kMDItemFSSize > 209715200 && kMDItemContentModificationDate < $time.now(-2419200)' | LC_ALL=C sort | while read -r _l;do ls -lh "${_l}"; done | sort -k5 -h | tail -n20
    fi
    # Currently updatedb may not index external drive (maybe because exFat?)
    if type updatedb &>/dev/null; then
        #alias of 'updatedb' = sudo FILESYSTEMS="hfs ufs apfs exfat" /usr/libexec/locate.updatedb
        echo "# executing updatedb (may ask sudo password)"
        updatedb
    fi
}
# accessed time doesn't seem to work with directory, so using _name to check files
#mv_not_accessed "." "30" "*.pom" "Y"
function mv_not_accessed() {
    local _dir="${1:-"."}"
    local _atime="${2:-100}" # 100 days
    local _name="${3}"       # "*.pom"
    local _do_it="${4}"
    # Can't remember why I'm using FUNCNAME[0] (even not FUNCNAME[1] for caller)
    #find -L /tmp -type f -name "${FUNCNAME[0]}_$$.out" -mmin -3 | grep -q "${FUNCNAME[0]}_$$.out"
    if [ -n "${_name}" ]; then
        find ${_dir%/} -amin +${_atime} -name "${_name}" -print0
    else
        find ${_dir%/} -amin +${_atime} -print0
    fi | xargs -0 -n1 -I {} dirname {} | LC_ALL=C sort -r | uniq >/tmp/${FUNCNAME[0]}_$$.out
    cat /tmp/${FUNCNAME[0]}_$$.out | while read _f; do
        local _dist_name="$(echo ${_f//\//_} | sed 's/^\._//')"
        if [[ "${_do_it}" =~ ^[yY] ]]; then
            # May want to use $RANDOM to avoid "Directory not empty" as often directory name is just a version string.
            mv -v ${_f%/} $HOME/.Trash/${_dist_name}
        else
            echo "mv -v ${_f%/} $HOME/.Trash/${_dist_name}"
        fi
    done
}
# synchronising my search.osakos.com
function push2search() {
    # May need to configure .ssh/config to specify the private key
    local _force="$1"
    # 'indexes' and 'cache' are optional
    rsync -vrc -n --exclude 'indexes' --exclude 'cache' --exclude 'tmp' --exclude '.git' --exclude '.idea' search.osakos.com:~/www/search/ $HOME/IdeaProjects/search/
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
if [ -s $HOME/IdeaProjects/samples/runcom/nexus_alias.sh ]; then
    source $HOME/IdeaProjects/samples/runcom/nexus_alias.sh
fi
if [ -s $HOME/IdeaProjects/work/bash/nexus_aliases.sh ]; then
    source $HOME/IdeaProjects/work/bash/nexus_aliases.sh
fi
function pubS() {
    [ $HOME/IdeaProjects/work/bash/install_sonatype.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/work/bash/install_sonatype.sh dh1:/var/tmp/share/sonatype/ && cp -v -f $HOME/IdeaProjects/work/bash/install_sonatype.sh $HOME/share/sonatype/
    [ $HOME/IdeaProjects/samples/bash/setup_standalone.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/setup_standalone.sh dh1:/usr/local/bin/
    [ $HOME/IdeaProjects/samples/runcom/nexus_alias.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/runcom/nexus_alias.sh dh1:/var/tmp/share/sonatype/
    [ $HOME/IdeaProjects/samples/bash/utils.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/utils.sh dh1:/var/tmp/share/ && cp -v -f $HOME/IdeaProjects/samples/bash/utils.sh $HOME/share/sonatype/
    [ $HOME/IdeaProjects/samples/bash/utils_db.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/utils_db.sh dh1:/var/tmp/share/ && cp -v -f $HOME/IdeaProjects/samples/bash/utils_db.sh $HOME/share/sonatype/
    [ $HOME/IdeaProjects/samples/bash/utils_container.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/utils_container.sh dh1:/var/tmp/share/ && cp -v -f $HOME/IdeaProjects/samples/bash/utils_container.sh $HOME/share/sonatype/
    [ $HOME/IdeaProjects/samples/bash/_setup_host.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/_setup_host.sh dh1:/var/tmp/share/
    [ $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh dh1:/var/tmp/share/sonatype/ && cp -v -f $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh $HOME/share/sonatype/ && cp -v -f $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh $HOME/IdeaProjects/nexus-toolbox/scripts/
    [ $HOME/IdeaProjects/work/bash/log_tests_nxrm.sh -nt /tmp/pubS.last ] && cp -v -f $HOME/IdeaProjects/work/bash/log_tests_nxrm.sh $HOME/IdeaProjects/nexus-toolbox/scripts/log_check_scripts/
    [ $HOME/IdeaProjects/samples/java/asset-dupe-checker/src/main/java/AssetDupeCheckV2.java -nt /tmp/pubS.last ] && cp -v -f $HOME/IdeaProjects/samples/java/asset-dupe-checker/src/main/java/AssetDupeCheckV2.java $HOME/IdeaProjects/nexus-toolbox/asset-dupe-checker/src/main/java/ && cp -v -f $HOME/IdeaProjects/samples/misc/asset-dupe-checker-v2.jar $HOME/IdeaProjects/nexus-toolbox/asset-dupe-checker/
    [ $HOME/IdeaProjects/samples/bash/patch_java.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/patch_java.sh dh1:/var/tmp/share/java/
    #cp -v -f $HOME/IdeaProjects/work/nexus-groovy/src2/TrustStoreConverter.groovy $HOME/IdeaProjects/nexus-toolbox/scripts/
    scp ~/IdeaProjects/samples/misc/orient-console.jar dh1:/var/tmp/share/java/ &
    sync_nexus_binaries &>/dev/null &
    date | tee /tmp/pubS.last
}
function sync_nexus_binaries() {
    local _host="${1:-"dh1"}"
    echo "Synchronising IQ binaries from/to ${_host} ..." >&2
    rsync -Prc ${_host}:/var/tmp/share/sonatype/nexus-iq-server-*-bundle.tar.gz $HOME/.nexus_executable_cache/
    rsync -Prc $HOME/.nexus_executable_cache/nexus-iq-server-*-bundle.tar.gz ${_host}:/var/tmp/share/sonatype/
}

function set_classpath() {
    local _port_or_dir="${1}"
    if [[ "${_port_or_dir}" =~ ^[0-9]+$ ]]; then
        local _p=`lsof -ti:${_port} -s TCP:LISTEN` || return $?
        # requires jcmd in the path
        export CLASSPATH=".:`jcmd ${_p} VM.system_properties | sed -E -n 's/^java.class.path=(.+$)/\1/p' | sed 's/[\]:/:/g'`"
    elif [ -d "${_port_or_dir}" ]; then
        local _tmp_cp="$(find ${_port_or_dir%/} -type f -name '*.jar' | tr '\n' ':')"
        export CLASSPATH=".:${_tmp_cp%:}"
    fi
}

function update_cacerts() {
    local _pem="$1"
    local _alias="$2"
    [ -z "${JAVA_HOME}" ] && return 1
    [ ! -f "${JAVA_HOME%/}/jre/lib/security/cacerts" ] && return 2
    [ ! -f "${_pem}" ] && return 3
    [ -z "${_alias}" ] && _alias="$(basename "${_pem%%.*}")"
    sudo keytool -import -alias "${_alias}" -keystore "${JAVA_HOME%/}/jre/lib/security/cacerts" -file "${_pem}" -noprompt -storepass changeit
}