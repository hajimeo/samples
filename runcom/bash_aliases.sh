# source /dev/stdin <<< "(curl https://raw.githubusercontent.com/hajimeo/samples/master/runcom/bash_aliases.sh --compressed)"

## Simple/generic alias commands (some need pip though) ################################################################
# 'cd' to last modified directory
alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias fd='find . -name'
alias sha1R='find . -type f -exec sha1sum "{}" \;'
alias fcv='fc -e vim'
alias vim0='vim -u NONE -N -c "syn off" -c "set nowrap"'   # handy when you process large text
if ! type mvim &>/dev/null && [ -x "/Applications/MacVim.app/Contents/bin/mvim" ]; then
    alias mvim='/Applications/MacVim.app/Contents/bin/mvim'
    #alias mvim='open -na "MacVim"'
fi
if ! type mvimdiff &>/dev/null && [ -x "/Applications/MacVim.app/Contents/bin/mvimdiff" ]; then
    alias mvimdiff='/Applications/MacVim.app/Contents/bin/mvimdiff'
fi
# like dos2unix
alias crlf2lf='vim -c "set ff=unix" -c ":x"'
# 'time' with format
alias timef='/usr/bin/time -f"[%Us user %Ss sys %es real %MkB mem]"' # brew install gnu-time --with-default-names
# In case 'tree' is not installed
if type tree &>/dev/null; then
    function tree() {
        readlink -f "${1%/}"
        find "${1%/}" | sort | sed '1d;s/^\.//;s/\/\([^/]*\)$/|-- \1/;s/\/[^/|]*/|  /g'
    }
fi
# Debug network performance with curl
alias curld='curl -w "\ntime_namelookup:\t%{time_namelookup}\ntime_connect:\t%{time_connect}\ntime_appconnect:\t%{time_appconnect}\ntime_pretransfer:\t%{time_pretransfer}\ntime_redirect:\t%{time_redirect}\ntime_starttransfer:\t%{time_starttransfer}\n----\ntime_total:\t%{time_total}\nhttp_code:\t%{http_code}\nspeed_download:\t%{speed_download}\nspeed_upload:\t%{speed_upload}\n"'
# output the longest line *number* as wc|gwc -L does not show the line number
alias longest_line="awk 'length > max_length { max_length = length; longest_line_num = NR } END { print longest_line_num }'"
# count a specific character from each line with the line number. eg. gunzip -c large.sql.gz |
function count_char() {
    awk '/'$1'/ {print NR, gsub(/'$1'/, "", $0)}' $2  # if '/' needs to be '\/'
    # then `sed -n '<line_num>p' ./file.txt
}
# Sum integer in a column by using paste (which concatenates files or characters(+))
#alias sum_cols="gpaste -sd+ | bc"
alias sum_cols="paste -sd+ - | bc"
alias sum_and_count="awk '{ c+=1;s+=\$1 }; END { print \"sum:\"s\", count:\"c\"\" }'"
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
alias git_crt_tag=git_tag_crt
alias git_tag_hash='git tag --contains'
# To list release-<version>
function git_tags() {
    local _project="${1:-"."}" # eg: $HOME/IdeaProjects/samples
    local _checkout_to="$2"
    local _checkout_opts="$3"
    if [ -n "${_checkout_to}" ]; then
        git -C "${_project%/}" checkout ${_checkout_opts} "${_checkout_to}"
        return $?
    fi
    git -C "${_project%/}" tag -l | sort --version-sort # | grep -oE "\d+\.\d+\.\d+\-\d+"
}
# compare commits: git diff <commit1>[..<commit2>]
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
    local _git_repo="${2:-"."}"
    for c in $(git -C "${_git_repo}" log --all --grep "$_search" | grep ^commit | cut -d ' ' -f 2); do git branch -r --contains $c; done
    for c in $(git -C "${_git_repo}" log --all --grep "$_search" | grep ^commit | cut -d ' ' -f 2); do git tag --contains $c; done
}

## Python ##############################################################################################################
#pip tends to cause a lot of issue and using -m is safer
alias pip='python -m pip'
#virtualenv -p python3 $HOME/.pyvenv
function pyvTest() {
    local _dir="${1:-".venv"}"
    if [ ! -d "${_dir%/}" ]; then
        python3 -m venv "${_dir%/}" || return $?
    fi
    cd "${_dir%/}" && source ./bin/activate
}
#alias pyv='pyenv activate mypyvenv'    # I felt pyenv is slow, so not using
alias pyv='source $HOME/.pyvenv/bin/activate'
alias pyvN='source $HOME/.pyvenv_new/bin/activate'

## Below uses sys.argv[1] as sys.stdin.read() requires `echo -n`
alias urlencode='python3 -c "import sys;from urllib import parse; print(parse.quote(sys.argv[1]))"'
alias urldecode='python3 -c "import sys;from urllib import parse; print(parse.unquote(sys.argv[1]))"'
# base64 encode/decode (alternatives are coreutils's base64 or openssl base64 -e|-d)
alias b64encode='python3 -c "import sys, base64; print(base64.b64encode(sys.argv[1].encode(\"utf-8\")).decode())"'
#alias b64encode='python -c "import sys, base64; print(base64.b64encode(sys.argv[1]))"'
alias b64decode='python3 -c "import sys, base64; b=sys.argv[1]; b += \"=\" * ((4-len(b)%4)%4); print(base64.b64decode(b).decode())"' # .decode() to remove "b'xxxx"

alias htmlencode="python3 -c \"import sys,html;print(html.escape(sys.stdin.read()))\""
alias htmldecode="python3 -c \"import sys,html;print(html.unescape(sys.stdin.read()))\""
alias utc2int='python3 -c "import sys,time,dateutil.parser;from datetime import timezone;print(int(dateutil.parser.parse(sys.argv[1]).replace(tzinfo=timezone.utc).timestamp()))"' # doesn't work with yy/mm/dd (2 digits year)
alias int2utc='python3 -c "import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1][0:10]), tz=datetime.timezone.utc).isoformat())"'
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
alias prettyjson='python3 -c "import sys,json;print(json.dumps(json.loads(sys.stdin.read()), indent=4, sort_keys=True))"'
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
alias jp='pyvN && jupyter-lab --AiExtension.allowed_providers=ollama &> /tmp/jupyter-lab.out'   # not using & as I tend to forget to stop
alias jn='pyvN && jupyter-notebook &> /tmp/jupyter-notebook.out'
# php -S 0.0.0.0:7999
alias startWeb='python3 -m http.server' # specify port (default:8000) if python2: python -m SimpleHTTPServer 8000

#type zsh &>/dev/null && alias zzhi='env /usr/bin/arch -x86_64 /bin/zsh —-login'
type zsh &>/dev/null && alias ibrew="arch -x86_64 /usr/local/bin/brew"
type zsh &>/dev/null && alias pbrew="ALL_PROXY=http://proxyuser:proxypwd@dh1:28081 arch -x86_64 /usr/local/bin/brew"

## Common software/command but need to install #######################################################################
alias qcsv='q -O -d"," -T --disable-double-double-quoting'
alias pgbg='pgbadger --timezone 0'
export TABBY_DISABLE_USAGE_COLLECTION=1 # just in case
alias tabby_start='TABBY_DISABLE_USAGE_COLLECTION=1 tabby serve --device metal --model TabbyML/StarCoder-1B &>/tmp/tabby.out &'

### Docker/K8s/VM related
#alias rdocker="DOCKER_HOST='tcp://dh1:2375' docker"
alias rdocker="ssh dh1 docker"
alias docker_rmi_old="docker images | grep '(years|[0-9][0-9]+ months) ago' | awk '{print \$3}' | uniq | xargs -I{} docker rmi {}"
alias docker_rm_old="docker ps -a | grep -E '(years|[0-9][0-9]+ months) ago\s+Exited' | awk '{print \$1}' | xargs -P2 -I{} docker rm {}"
#dhTags "alpine" "library"
function dhTags() { # docker list tags
    local _image="${1}"
    local _namespace="${2}"
    local _size="${3:-"10"}"
    if [ -n "${_namespace}" ]; then
        _image="namespaces/${_namespace%/}/repositories/${_image%/}"
    else
        _image="repositories/${_image%/}"
    fi
    curl -L -sSf "https://registry.hub.docker.com/v2/${_image%/}/tags?page_size=${_size}" | pjt
}
alias podmand="podman --log-level debug" && alias podman_login="podman --log-level debug login --tls-verify=false" && alias podman_pull="podman --log-level debug pull --tls-verify=false" && alias podman_push="podman --log-level debug push --tls-verify=false"
alias podman_delete_all='podman system prune --all'    # --force && podman rmi --all
#type microk8s &>/dev/null && alias kubectl="microk8s kubectl"
alias kPods='kubectl get pods --show-labels -A'
function kBash() {
    local _pod="${1}"
    local _ns="${2}"
    #kubectl get pods -n sonatype-ha -l name=nxiqha-iq-server -o jsonpath={.items[0].metadata.name} | head -n1
    if [[ "${_pod}" =~ ^(iq|iqha|IQHA) ]]; then
        _pod="$(kPods | grep -m1 'name=nxiqha-iq-server,pod-template-hash=' | awk '{print $2}')"
    elif [[ "${_pod}" =~ ^(rmha|RMHA) ]]; then
        _pod="$(kPods | grep -m1 'app.kubernetes.io/name=nxrm-ha' | awk '{print $2}')"
    elif [[ "${_pod}" =~ ^(rm|RM) ]]; then
        _pod="$(kPods | grep -m1 'app=nxrm3pg,pod-template-hash=' | awk '{print $2}')"
    fi
    if [ -z "${_ns}" ]; then
        _ns="$(kubectl get pods -A | grep -E "\s${_pod}\s.+\sRunning\s" | awk '{print $1}')"
        [ -z "${_ns}" ] && return 1
    fi
    kubectl exec "${_pod}" -n "${_ns}" -t -i -- bash
}
function kConfMerge() {
    local _append="${1}"
    local _orig="${2:-"$HOME/.kube/config"}"
    local _merged="${3:-"./merged_kube_config"}"
    [ -s "${_append}" ] || return 1
    KUBECONFIG=${_orig}:${_append} kubectl config view --flatten > ${_merged} || return $?
    echo "Created ${_merged}"
}
if [ -s "$HOME/.kube/support_test_config" ]; then
    alias awsSpt='aws-vault exec support -- aws'
    alias kcSpt='aws-vault exec support -- kubectl'
fi

## Non default (need to install some complex software and/or develop script) alias commands ############################
# Load/source my own searching utility functions / scripts
#mkdir -p $HOME/IdeaProjects/samples/bash; curl -o $HOME/IdeaProjects/samples/bash/log_search.sh https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
if [ -d $HOME/IdeaProjects/samples/bash ]; then
    alias logT="pyvN; source $HOME/IdeaProjects/samples/bash/log_tests.sh"
    alias logTest="pyvN;$HOME/IdeaProjects/samples/bash/log_tests.sh"
    alias setupRm3="source $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh"
    alias setupNexus3="source $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh"
    alias setupIq="source $HOME/IdeaProjects/samples/bash/setup_nexus_iq.sh"
    alias ss="bash $HOME/IdeaProjects/samples/bash/setup_standalone.sh"
fi
if [ -d $HOME/IdeaProjects/work/bash ]; then
    alias srcLog="pyvN; source $HOME/IdeaProjects/work/bash/log_search.sh"
    alias srcRm="logT; source $HOME/IdeaProjects/work/bash/log_tests_nxrm.sh"
    alias srcIq="logT; source $HOME/IdeaProjects/work/bash/log_tests_nxiq.sh"
    alias logRm="pyvN;$HOME/IdeaProjects/work/bash/log_tests_nxrm.sh && srcRm"
    alias logIq="pyvN;$HOME/IdeaProjects/work/bash/log_tests_nxiq.sh && srcIq"
    alias instSona="source $HOME/IdeaProjects/work/bash/install_sonatype.sh"
fi
#alias xmldiff="python $HOME/IdeaProjects/samples/python/xml_parser.py" # this is for Hadoop xml files

## VM related
# virt-manager remembers the connections, so normally would not need to start in this way.
alias kvm='virt-manager -c "qemu+ssh://virtuser@dh1/system?socket=/var/run/libvirt/libvirt-sock" &>/tmp/virt-manager.out &'

## Java / jar related
alias mb='${JAVA_HOME_11%/}/bin/java -jar $HOME/Apps/metabase.jar'    # port is 3000
alias vnc='java -Xmx2g -jar $HOME/Apps/tightvnc-jviewer.jar &>/tmp/vnc-java-viewer.out &'
#alias vnc='java -jar $HOME/Applications/VncViewer-1.9.0.jar &>/tmp/vnc-java-viewer.out &'
alias samurai='java -Xmx4g -jar $HOME/Apps/samurali/samurai.jar &>/tmp/samurai.out &'
alias tda='java -Xmx4g -jar $HOME/Apps/tda-bin-2.4/tda.jar &>/tmp/tda.out &'    #https://github.com/irockel/tda/releases/latest
alias gcviewer='java -Xmx4g -jar $HOME/Apps/gcviewer-1.37-SNAPSHOT.jar' # &>/tmp/gcviewer.out & # Mac can't stop this so not put in background
alias gitbucket='java -jar gitbucket.war &> /tmp/gitbucket.out &'   #https://github.com/gitbucket/gitbucket/releases/download/4.34.0/gitbucket.war
alias groovyi='groovysh -e ":set interpreterMode true"'
# JAVA_HOME_11 is set in bash_profile.sh
alias jenkins='${JAVA_HOME_11%/}/bin/java -Djava.util.logging.config.file=$HOME/Apps/jenkins-logging.properties -jar $HOME/Apps/jenkins.war'  #curl -o $HOME/Apps/jenkins.war -L https://get.jenkins.io/war-stable/2.426.3/jenkins.war
# http (but https fails) + reverse proxy server https://www.mock-server.com/mock_server/getting_started.html
alias mockserver='java -jar $HOME/Apps/mockserver-netty.jar'  #curl -o $HOME/Apps/mockserver-netty.jar -L https://search.maven.org/remotecontent?filepath=org/mock-server/mockserver-netty/5.11.1/mockserver-netty-5.11.1-jar-with-dependencies.jar
alias jkCli='java -jar $HOME/Apps/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin123' #curl -o $HOME/Apps/jenkins-cli.jar -L http://localhost:8080/jnlpJars/jenkins-cli.jar
[ -f $HOME/IdeaProjects/samples/misc/orient-console.jar ] && alias orient-console="java -jar $HOME/IdeaProjects/samples/misc/orient-console.jar"
[ -f $HOME/IdeaProjects/samples/misc/h2-console.jar ] && alias h2-console="java -jar $HOME/IdeaProjects/samples/misc/h2-console.jar"
[ -f $HOME/IdeaProjects/samples/misc/h2-console_v200.jar ] && alias h2-console_v200="java -jar $HOME/IdeaProjects/samples/misc/h2-console_v200.jar"
[ -f $HOME/IdeaProjects/samples/misc/h2-console_v224.jar ] && alias h2-console_v224="java -jar $HOME/IdeaProjects/samples/misc/h2-console_v224.jar"
# requires Java 11 or higher
[ -f $HOME/IdeaProjects/samples/misc/h2-console_v232.jar ] && alias h2-console_v232="/opt/homebrew/opt/openjdk\@17/libexec/openjdk.jdk/Contents/Home/bin/java -jar $HOME/IdeaProjects/samples/misc/h2-console_v232.jar"
[ -f $HOME/IdeaProjects/samples/misc/pg-console.jar ] && alias pg-console="java -jar $HOME/IdeaProjects/samples/misc/pg-console.jar"
#[ -f $HOME/IdeaProjects/samples/misc/blobpath.jar ] && alias blobpathJ="java -jar $HOME/IdeaProjects/samples/misc/blobpath.jar"
# JAVA_HOME_11 is set in bash_profile.sh
alias matJ11='/Applications/mat.app/Contents/MacOS/MemoryAnalyzer -vm ${JAVA_HOME_11%/}/bin'
if [ -s $HOME/IdeaProjects/samples/bash/patch_java.sh ]; then
    alias patchJava='$HOME/IdeaProjects/samples/bash/patch_java.sh'
fi

## Chrome aliases for Mac (URL needs to be IP as hostname wouldn't be resolvable on remote)
#alias shib-local='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/local --proxy-server=socks5://localhost:28081'
#alias shib-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=socks5://dh1:28081 http://192.168.1.31:4200/webuser/'
alias chrome-work='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/work'
alias chrome-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/dh1 --proxy-server=http://dh1:28080'
alias k8s-dh1='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/k8s-dh1 --proxy-server=socks5://dh1:38081'
alias hblog='open -na "Google Chrome" --args --user-data-dir=$HOME/.chromep/hajigle https://www.blogger.com/blogger.g?blogID=9018688091574554712&pli=1#allposts'
alias gemini='open -na "Google Chrome" --args --app="https://gemini.google.com/u/1/app"'   # --user-data-dir=$HOME/.chromep/hosako
# pretending windows chrome on Linux
alias winchrome='/opt/google/chrome/chrome --user-data-dir=$HOME/.chromep --proxy-server=socks5://localhost:38080  --user-agent="Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.96 Safari/537.36"'

## Work specific aliases
alias hwxS3='s3cmd ls s3://private-repo-1.hortonworks.com/HDP/centos7/2.x/updates/'
# TODO: public-repo-1.hortonworks.com private-repo-1.hortonworks.com
# Slack API Search
[ -s $HOME/IdeaProjects/samples/python/SimpleWebServer.py ] && alias slackS="pyvN && cd $HOME/IdeaProjects/samples/python/ && python3 ./SimpleWebServer.py &> /tmp/SimpleWebServer.out &"
alias smtpdemo='python -m smtpd -n -c DebuggingServer localhost:2500'

### Functions (some command syntax does not work with alias eg: sudo) ##################################################
# mac doesn't have namei (util-linux)
function namei_l() {
    local _path="$1"
    local _full_path="$(readlink -f "${_path}")"
    #while true; do ls -ld $1; _p="$(dirname "$1")" || break ; [ "$1" = "/" ] && break; done
    while true; do
        if [ -f "${_full_path}" ]; then
            echo "$(ls -l ${_full_path})"
        elif [ -d "${_full_path}" ]; then
            echo "$(ls -ld ${_full_path})"
        else
            echo "${_path} - No such file or directory"
        fi
        [ "${_path}" == "/" ] && break
        _path="$(dirname "${_path}")"
    done
}
function iconv_utf8() {
    # To cleanup/remove accent characters for UTF-8
    local _file="${1}"
    local _in_encoding="${2:-"ISO-8859-1"}"
    [ ! -s "${_file}" ] && return 1
    local _result="$(iconv -f ${_in_encoding} -t UTF-8 ${_file})" || return $?
    echo "${_result}" > "${_file}"
}
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

function fvim() {
    local _name="$1"
    local _find_all="$2"
    local _max_depth="${3:-"7"}"
    local _result=1
    # Accept not only file name but also /<dir>/<filename> so that using grep
    for _f in `find . -maxdepth ${_max_depth} -type f -print | grep "/${_name}$"`; do
        echo "# ${_f}" >&2
        vim "${_f}" && _result=$?
        [[ "${_find_all}" =~ ^(y|Y) ]] || break
        echo ''
    done
    return ${_result}
}

function lns() {
    if [ -L "$2" ]; then rm -i "$2" || return $?; fi
    if [ -d "$2" ]; then rmdir "$2" || return $?; fi
    ln -v -s "$(realpath "$1")" "$2"
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

function count_size() {
    local _path="${1:-"."}"
    local _filter="${2:-"*"}"
    # $1/1024/1024 for MB
    find ${_path%/} -type f -name "${_filter}" -printf '%s\n' | awk '{ c+=1;s+=$1 }; END { print "count:"c", size:"s" bytes" }'
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
# Run specific command X times parallely with Y concurrency
function multiexec() {
    local _cmd="$1"
    local _ttl="${2:-"1"}"    # How many times
    local _con="${3:-"1"}"    # Concurrency
    echo "$(seq 1 ${_ttl})" | xargs -I{} -P${_con} -t bash -c "${_cmd}"
}
# monitorexec ./db-migrator-2025-02-17T14-23.log "low heap memory" "jmap -dump:format=b,file=./db-mig_$(date +"%Y%m%d%H%M%S").hprof $PID" 5
function monitorexec() {
    local _file="$1"
    local _regex="$2"
    local _cmd="$3"
    local _how_many="${4:-"1"}"
    for _i in $(seq 1 ${_how_many}); do
        tail -n -1 -F "${_file}" | grep --line-buffered -m1 -E "${_regex}" && eval "${_cmd}"
        echo "# [$(date +'%Y-%m-%d %H:%M:%S')] ${_i} : '${_cmd}'"
        sleep 1
    done
}
# make a directory and cd
function mcd() {
    local _path="$1"
    mkdir "${_path}"
    cd "${_path}"
}
function jsondiff() {
    # alternative https://json-delta.readthedocs.io/en/latest/json_diff.1.html
    local _f1="$(basename $1 .json)_1.json"
    local _f2="$(basename $2 .json)_2.json"
    local _use_vimdiff="$3"
    if type sortjson &>/dev/null; then
        # curl -o /usr/local/bin/sortjson -L "https://github.com/hajimeo/samples/raw/master/misc/sortjson_$(uname)_$(uname -m)"
        sortjson "$1" "/tmp/${_f1}" || return $?
        sortjson "$2" "/tmp/${_f2}" || return $?
    else
        # NOTE: python one doesn't look like sorting recursively
        python3 -c "import sys,json;print(json.dumps(json.load(open('${1}')), indent=4, sort_keys=True))" >"/tmp/${_f1}" || return $?
        python3 -c "import sys,json;print(json.dumps(json.load(open('${2}')), indent=4, sort_keys=True))" >"/tmp/${_f2}" || return $?
    fi
    if [[ "${_use_vimdiff}" =~ ^[yY] ]]; then
        # sometimes vimdiff crush and close the terminal
        bash -c "vimdiff \"/tmp/${_f1}\" \"/tmp/${_f2}\"" 2>/tmp/vimdiff.err
    else
        diff -w -y --suppress-common-lines "/tmp/${_f1}" "/tmp/${_f2}"
    fi
}
function xmldiff() {
    python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))" $1 >/tmp/xmldiff1_$$.json || return $?
    python3 -c "import sys,xmltodict,json;print(json.dumps(xmltodict.parse(open(sys.argv[1]).read()), indent=4, sort_keys=True))" $2 >/tmp/xmldiff2_$$.json || return $?
    bash -c "vimdiff /tmp/xmldiff1_$$.json /tmp/xmldiff2_$$.json" 2>/tmp/vimdiff.err
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
function find_recent() {
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
# Tail recently modified log files
function tail_logs() {
    local _log_dir="${1}"
    local _log_file_glob="${2:-"*.log"}"
    tail -n20 -f $(find_recent "${_log_dir}" "${_log_file_glob}")
}
# Grep only recently modified files (TODO: should check if ggrep or rg is available)
function grep_logs() {
    local _search_regex="${1}"
    local _log_dir="${2}"
    local _log_file_glob="${3:-"*.log"}"
    local _grep_opts="${4:-"-IrsP"}"
    grep ${_grep_opts} "${_search_regex}" $(find_recent "${_log_dir}" "${_log_file_glob}")
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
    rg "(^\"?20\d\d-\d\d-\d\d|\"timestamp\":\"20\d\d-\d\d-\d\d|\d\d.[A-Z][a-z]{2}.20\d\d|\"date\":\"20\d\d-\d\d-\d\d).${_time_regex}" -o ${_file} | sed 's/ /./g' | bar_chart.py
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
# MITM proxy
function mitmProxy() {
    local _fport="${1:-"8080"}"
    local _bhost="${2:-"localhost"}"
    local _port="${3:-"${_fport}"}"
    local _node="${4:-"/tmp/mitmpipe_$$"}"
    [ -e "${_node}" ] || mknod "${_node}" p # creates a FIFO
    #nc -k -l ${_fport} 0<${_node} | tee -a ./in_$$.dump | nc "${_bhost}" ${_port} | tee -a ./out_$$.dump 1>${_node}
    nc -k -l ${_fport} 0<${_node} | tee >(LC_CTYPE=C tr -cd '[:print:]\n' >>./in_$$.dump) | nc "${_bhost}" ${_port} | tee >(LC_CTYPE=C tr -cd '[:print:]\n' >>./out_$$.dump) 1>${_node}
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
    local _network_addrs="${2:-"172.17.0.0 172.18.0.0 172.17.100.0 10.1.25.0 10.152.183.0"}" # last one is for K8s pods
    [ -z "${_dh}" ] && _dh="$(ifconfig ppp0 | grep -oE 'inet .+' | awk '{print $4}')" 2>/dev/null
    [ -z "${_dh}" ] && _dh="dh1.standalone.localdomain"

    # My home network custom setting
    #if ping -Q -t1 -c1 192.168.42.129 &>/dev/null; then
    #    sudo route delete -net 192.168.1.0/24 &>/dev/null
    #    sudo route add -net 192.168.1.0/24 192.168.42.129
    #fi

    # If geteway is unreachable, shouldn't update the route
    ping -Q -t1 -c1 ${_dh} || return $?

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
        _cmd="screen -x ${_session_name} || screen -s -/bin/bash -S ${_session_name}"
    else
        # if no session name specified, tries to attach it anyway (if only one session, should work)
        _cmd="screen -x || screen -x $USER || screen -s -/bin/bash -S $USER"
    fi
    ssh ${_user_at_host} -t ${_cmd}
}
# sshfs -o uid=$UID,gid=$UID,umask=000,reconnect,follow_symlinks $USER@$(echo ${SSH_CONNECTION} | cut -d" " -f1):/Users/$USER/IdeaProjects $HOME/IdeaProjects
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
# NOTE: if 'brew upgraded postgresql', may need to run 'brew postgresql-upgrade-database'
function pgStatus() {
    local _cmd="${1:-"status"}"
    local _pg_data="${2:-"/opt/homebrew/var/postgresql@14"}"    #/usr/local/var/postgresql@14
    local _log_path="${3-"${HOME%/}/postgresql.log"}"   # may not have permission on /var/log and /tmp might be small
    local _wal_backup_path="${4:-"$HOME/share/$USER/backups/$(hostname -s)_wal"}"
    #ln -s /Volumes/Samsung_T5/hajime/backups $HOME/share/$USER/backups
    if [[ "${_cmd}" =~ start$ ]]; then
        if [ -n "${_log_path}" ] && [ -s "${_log_path}" ]; then
            echo -n > ${_log_path}
        fi
        if [ -d "${_wal_backup_path%/}" ]; then
            find ${_wal_backup_path%/} -type f -mtime +2 -delete 2>/dev/null &  # -print
        fi
    fi
    if [ -n "${_log_path}" ]; then
        pg_ctl -D ${_pg_data} -l ${_log_path} ${_cmd}
    else
        pg_ctl -D ${_pg_data} ${_cmd}
    fi || return $?
    export PGDATA="${_pg_data}"
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
        echo -e "HTTP/1.1 ${_http_status}\nDate: $(type gdate &>/dev/null && gdate --rfc-2822 || date --rfc-2822)\nServer: ncWeb\nLast-Modified: ${_last_mod}\nContent-Length: 0\n\n" | nc -v -v -n -l ${_port} || break    # can't remember why -p was used
        echo -e "\n"
    done
}

# When this method is changed, update golang/README.md
#GO_SKIP_TESTS=Y GO_BUILD_OPTS="-mod=readonly" goBuild
function goBuild() {
    local __doc__="Go build for multiple OS/Arch. Use GO_SKIP_TESTS and GO_BUILD_OPTS to skip tests and pass options."
    local _goFile="$1"
    local _name="$2"
    local _destDir="${3:-"$HOME/IdeaProjects/samples/misc"}"
    local _opts="${4-"${GO_BUILD_OPTS}"}"   # -mod=readonly
    if [ -z "${_name}" ]; then
        if [ -z "${_goFile}" ]; then
            _name="$(basename "${PWD}" | tr '[:upper:]' '[:lower:]')"
        else
            _name="$(basename "${_goFile}" ".go" | tr '[:upper:]' '[:lower:]')"
        fi
    fi
    if [ -d /opt/homebrew/opt/go/libexec ]; then
        export GOROOT=/opt/homebrew/opt/go/libexec
    fi
    go mod tidy || return $?    # go get -v -t -u all && go mod tidy
    if [[ "${GO_SKIP_TESTS}" =~ ^[yY] ]]; then
        echo "# Skipping tests ..." >&2
    else
        echo "# Starting tests at $(date)" >&2
        # Saving into current directory
        go test -coverprofile=./coverage.out || return $?
        go tool cover -func=./coverage.out
        echo "" >&2
    fi
    echo "# Compiling at $(date)" >&2
    env GOOS=darwin GOARCH=arm64 go build -o "${_destDir%/}/${_name}_Darwin_arm64" ${_opts} ${_goFile} || return $?
    env GOOS=linux GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Linux_x86_64" ${_opts} ${_goFile} && \
    env GOOS=linux GOARCH=arm64 go build -o "${_destDir%/}/${_name}_Linux_aarch64" ${_opts} ${_goFile} && \
    env GOOS=darwin GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Darwin_x86_64" ${_opts} ${_goFile} && \
    env GOOS=windows GOARCH=amd64 go build -o "${_destDir%/}/${_name}_Windows_x86_64" ${_opts} ${_goFile}
    echo "" >&2
    find "${_destDir%/}" -type f -name "${_name}_*" -mmin -1 >&2
    echo "# curl -o /usr/local/bin/${_name} -L \"https://github.com/hajimeo/samples/raw/master/misc/${_name}_\$(uname)_\$(uname -m)\"" >&2
    echo "Completed at $(date) (scan ./go.sum)" >&2
}

function cleanOldDirs() {
    # Currently assuming the directory name starts with nxrm_[0-9] or nxiq_[0-9]
    # Also deleting directory if log file newer than 60 days does not exist
    local _test_dir="${1:-"$HOME/Documents/tests"}"
    local _days="${2:-"90"}"
    local _find="find"
    type gfind &>/dev/null && _find="gfind"
    find ${_test_dir%/} -maxdepth 1 -type d -name 'nxrm_[0-9]*' | while read -r _d; do
        local _dir_name="$(basename "${_d}")"
        if [ -d "${_d%/}/sonatype-work/nexus3/log" ]; then
            local _log_file="$(${_find} "${_d%/}/sonatype-work/nexus3/log" -maxdepth 1 -type f -name '*.log' -mtime -${_days} 2>/dev/null | head -n1)"
            if [ -z "${_log_file}" ]; then
                mv -v ${_d%/} ${_test_dir%/}/to_be_deleted_${_dir_name%/} || return $?    # this may fail if to_be_deleted_${_d%/} exists
            fi
        fi
    done
    find ${_test_dir%/} -maxdepth 1 -type d -name 'nxiq_[0-9]*' | while read -r _d; do
        local _dir_name="$(basename "${_d}")"
        local _log_dir="$(${_find} "${_d%/}" -maxdepth 3 -type d -name 'log' 2>/dev/null | head -n1)"
        if [ -d "${_log_dir}" ]; then
            local _log_file="$(${_find} "${_log_dir%/}" -maxdepth 1 -type f -name '*.log' -mtime -${_days} 2>/dev/null | head -n1)"
            if [ -z "${_log_file}" ]; then
                mv -v ${_d%/} ${_test_dir%/}/to_be_deleted_${_dir_name%/} || return $?    # this may fail if to_be_deleted_${_d%/} exists
            fi
        fi
    done
    #find ${_test_dir%/} -maxdepth 1 -type d -name 'to_be_deleted_*' | while read -r _d; do
    #    [[ "${_d}" =~ /to_be_deleted_(.+)$ ]] || continue
    #    mv -v ${_d%/} ${_test_dir%/}/${BASH_REMATCH[1]} || return $?
    #done
}

function cleanOldDBs() {
    # requires rg (ripgrep)
    # Currently assuming the DB name starts with 'nxrm|nxiq|rm|iq' and the directory name starts with 'nxrm_[0-9]' or 'nxiq_[0-9]'
    local _test_dir="${1:-"$HOME/Documents/tests"}"
    local _check_db_pfx="${2:-"nx(rm|iq)"}"
    psql --csv -t -l | rg "^${_check_db_pfx}[^,]+" -o > /tmp/${FUNCNAME[0]}_in_db_$$.out || return $?
    rg '^jdbcUrl=.+/(rm|nxrm)([^/\?]+)' -o -r '$1$2' --no-filename ${_test_dir%/}/nxrm_[0-9]*/sonatype-work/nexus3/etc/fabric/nexus-store.properties > /tmp/${FUNCNAME[0]}_nxrm_$$.out || return $?
    if [ ! -s "/tmp/${FUNCNAME[0]}_nxrm_$$.out" ]; then
        echo "ERROR /tmp/${FUNCNAME[0]}_nxrm_$$.out can't be empty" >&2
        return 1
    fi
    rg '^database:' -A6 --no-filename ${_test_dir%/}/nxiq_[0-9]*/config.yml | rg '^\s+name:\s*(iq|nxiq)([^/\?]+)' -o -r '$1$2' >> /tmp/${FUNCNAME[0]}_nxiq_$$.out || return $?
    if [ ! -s "/tmp/${FUNCNAME[0]}_nxiq_$$.out" ]; then
        echo "ERROR /tmp/${FUNCNAME[0]}_nxiq_$$.out can't be empty" >&2
        return 1
    fi
    grep -vxFf <(cat /tmp/${FUNCNAME[0]}_nxrm_$$.out /tmp/${FUNCNAME[0]}_nxiq_$$.out) /tmp/${FUNCNAME[0]}_in_db_$$.out | while read -r _db; do
        # Currently hard-coded to skip some databases
        if [[ "${_db}" =~ (sptboot|filelisttest|large) ]]; then
            continue
        fi
        local _sql="ALTER DATABASE ${_db} RENAME TO to_be_deleted_${_db}"
        echo "# Executing ${_sql}" >&2
        psql -c "${_sql}" || return $?
    done
    # To restore/revert
    #psql --csv -t -l | rg -i "^to_be_deleted_([^,]+)" -o -r '$1' | xargs -I{} -t psql -c "ALTER DATABASE to_be_deleted_{} RENAME TO {}"

    # Blow is bad because extracted files may have old dates
    #${_find} "${_test_dir%/}" -type f -mtime +120 -delete 2>/dev/null
    #${_find} ${_test_dir%/}/* -type d -mtime +2 -empty -print -delete
    echo "# DELETE statements for Not updated databases and above databases:" >&2
    #psql -d template1 -tAc "SELECT 'DROP DATABASE '||datname||';    -- '||pg_database_size(datname)||' bytes' FROM pg_stat_database WHERE datname NOT IN ('', 'template0', 'template1', 'postgres', CURRENT_USER) AND stats_reset < (now() - interval '60 days') ORDER BY stats_reset"
    psql -d template1 -tAc "SELECT 'DROP DATABASE '||datname||';    -- '||pg_database_size(datname)||' bytes' FROM pg_stat_database WHERE datname ilike 'to_be_deleted_%' ORDER BY datname"
    #psql -tAc "SELECT datname FROM pg_database WHERE datname LIKE 'to_be_deleted_%'" | while read -r _db; do psql -d template1 -c "DROP DATABASE ${_db}" || break; done
}

function listLargeDirs() {
    local _src="${1:-"/Volumes/Samsung_T5/hajime/cases"}"
    local _n="${2:-"20"}"
    local _du="du"
    type gdu &>/dev/null && _du="gdu"
    ${_du} -ahx -d1 ${_src} | sort -hr | head -n "${_n}" | while read -r _size_dir; do
        if [[ "${_size_dir}" =~ ^[[:space:]]*([0-9\.]+G)[[:space:]]+(.+) ]]; then
            echo "${BASH_REMATCH[1]} $(ls -dl "${BASH_REMATCH[2]}" | cut -d' ' -f9-)"
        fi
    done
}

#_RSYNC_DRY_RUN=Y syncGitReposWithRemotePC
function syncGitReposWithRemotePC() {
    local _remote_host="${1:-"oldmac"}"
    local _remote_user="${2:-"${USER}"}"
    local _repo_rel_path="${3:-"IdeaProjects/samples"}"
    local _local_base_dir="${4:-"$HOME"}"
    local _rsync_exclude="${5:-"--exclude .idea --exclude .git"}"
    local _dry_run="${6:-"${_RSYNC_DRY_RUN}"}"

    local _remote_user_host="${_remote_user}@${_remote_host}"
    local _remote_home="$(ssh ${_remote_user_host} 'echo $HOME')"
    if [ -z "${_remote_home%/}" ]; then
        echo "# '${_remote_host}' is not reachable. Skipping rsync." >&2
        return 1
    fi
    local _local_repo_path="${_local_base_dir%/}/${_repo_rel_path%/}"
    local _remote_repo_path="${_remote_home%/}/${_repo_rel_path%/}"

    if [ -n "${_dry_run}" ]; then
        echo "# *** Dry run mode ***" >&2
        _dry_run="-n"
    fi

    local _check_file="$HOME/.${_remote_host}_${_remote_user}_lastlist${_dry_run}.out"
    local _diff_mins="1440" # default 24 hours
    if [ -f "${_check_file}" ]; then
        local _current_ts="$(date +%s)"
        local _last_mod_ts="$(date -r "${_check_file}" +%s 2>/dev/null)"
        _diff_mins="$(((_current_ts - _last_mod_ts) / 60))"
    fi
    echo "" >&2
    echo "# Finding any '-mmin -${_diff_mins}' files in the remote and copy (just in case, excluding large files)" >&2
    # Need relative path, so using cd. If dry run, shouldn't touch the previous list file.
    ssh ${_remote_user_host} "cd ${_remote_repo_path} && find . -type f -mmin -${_diff_mins} -size -10M -not -path \"*/.idea/*\" -not -path \"*/.git/*\" -print" > "${_check_file}${_dry_run}" || return $?
    if [ -s "${_check_file}${_dry_run}" ]; then
        for _f in $(cat "${_check_file}${_dry_run}"); do
            if [ ! -s "${_local_repo_path%/}/${_f}" ]; then
                if [ -n "${_dry_run}" ]; then
                    echo "# Found new file: ${_remote_user_host}:${_remote_repo_path%/}/${_f}"
                else
                    # Currently exiting if one file failed to copy
                    scp -C ${_remote_user_host}:${_remote_repo_path%/}/${_f} ${_local_repo_path%/}/${_f} || return $?
                fi
            fi
        done
        if [ -n "${_dry_run}" ]; then
            rm -f "${_check_file}${_dry_run}"
        fi
    fi

    echo "" >&2
    echo "# Rsync ${_local_repo_path%/}/ ${_remote_user_host}:${_remote_repo_path%/}/ ${_rsync_exclude} ${_dry_run}" >&2
    # may need to add more --exclude
    eval "rsync -Pzau --delete --modify-window=1 ${_rsync_exclude} ${_local_repo_path%/}/ ${_remote_user_host}:${_remote_repo_path%/}/ ${_dry_run}"
    echo "" >&2
    if [ -z "${_dry_run}" ]; then
        # As the below may output misleading information, not running if dry run
        local _backup_dir="/tmp/$(basename ${_local_repo_path%/})_$(date +%Y%m%d%H%M%S)"
        echo "# Rsync ${_remote_user_host}:${_remote_repo_path%/}/ ${_local_repo_path%/}/ ${_rsync_exclude} --backup-dir=${_backup_dir} ${_dry_run}" >&2
        eval "rsync -Pzau --delete --backup --backup-dir=${_backup_dir} --modify-window=1 ${_rsync_exclude}" ${_remote_user_host}:${_remote_repo_path%/}/ ${_local_repo_path%/}/ ${_dry_run}
    fi
}

# backup & cleanup Cases (backing up files smaller than 10MB only)
function backupC() {
    local _src="${1:-"/Volumes/Samsung_T5/hajime/cases"}"
    local _ext_backup="${2:-"/Volumes/Samsung_T5/hajime/backups"}"
    local _find="find"
    type gfind &>/dev/null && _find="gfind"

    # vs code / codium extensions
    if which code && [ -d "$HOME/backup" ]; then
        code --list-extensions | xargs -L 1 echo code --install-extension >$HOME/backup/vscode_install_extensions.sh || return $?
    fi
    if type codium &>/dev/null && [ -d "$HOME/backup" ]; then
        codium --list-extensions | xargs -L 1 echo codium --install-extension >$HOME/backup/vscodium_install_extensions.sh || return $?
    fi

    if type kubectl &>/dev/null && [ -d "$HOME/backup/kube" ]; then
        rsync -cav $HOME/.kube/*config* $HOME/backup/kube/
    fi
    if [ -s $HOME/.aws/config ] && [ -d "$HOME/backup" ]; then
        # Not backing up .aws/credentials
        cp -v -f $HOME/.aws/config $HOME/backup/aws_config || return $?
    fi

    if [ -s /etc/hosts ] && [ -d "$HOME/backup" ]; then
        cp -v -f /etc/hosts $HOME/backup/etc_hosts || return $?
    fi
    if [ -d "$HOME/.ssh" ] && [ -d "$HOME/backup/ssh" ]; then
        # not copying symlink as I'm expecting symlinks would be from the "samples" repo
        rsync -cav --no-links "$HOME/.ssh/" "$HOME/backup/ssh" || return $?
    fi
    if [ -s "$HOME/IdeaProjects/m2_settings.xml" ] && [ -d "$HOME/backup/IdeaProjects" ]; then
        cp -v -f $HOME/IdeaProjects/m2_settings*.xml $HOME/backup/IdeaProjects/ || return $?
    fi

    echo ""
    echo "#### Synchronising a few Github repositories into 'oldmac' ####" >&2
    echo ""
    syncGitReposWithRemotePC "oldmac" "$USER" "IdeaProjects/samples" "$HOME" #|| return $?
    syncGitReposWithRemotePC "oldmac" "$USER" "IdeaProjects/work" "$HOME" #|| return $?

    echo ""
    echo "#### Cleaning up old temp/test data (120 days) ####" >&2
    echo ""
    if [ -d "$HOME/Documents/tests" ]; then
        cleanOldDirs "$HOME/Documents/tests" 60
        cleanOldDBs "$HOME/Documents/tests"
     fi

    if [ -d "${_ext_backup}" ]; then
        echo ""
        echo "#### Cleaning up older than 30 days files from ${_ext_backup} ####" >&2
        echo ""
        # Should backup something to the external backup location?
        #rsync -Pvaz --bwlimit=10240 --max-size=10000k --modify-window=1 --exclude '*_tmp' --exclude '_*' ${_src%/}/ ${_dst%/}/
        ${_find} "${_ext_backup%/}" -maxdepth 1 -type d -name "*_wal" -print0 | xargs -0 -P4 -I{} -t ${_find} {} -type f -mtime +30 -delete
    fi

    if [ ! -d "${_src}" ]; then
        echo "# Source ${_src} is not set nor directory. Ending this function." >&2
        return 1
    fi
    echo ""
    echo "#### Moving up old (90 days) directories from ${_src} into Trash ####" >&2
    echo ""
    ## Special: support_tmp directory or .tmp or .out file wouldn't need to backup (not using atime as directory doesn't work)
    # NOTE: xargs may not work with very long file name 'mv: rename {} to /Users/hosako/.Trash/{}: No such file or directory', so not using.
    _src="$(realpath "${_src}")"    # because find -L ... -delete does not work
    [ -z "${_src%/}" ] && return 12
    # Find directories from the src and if no files newer than 120 days, then move to trash (no background)
    find ${_src%/} -mindepth 1 -maxdepth 1 -type d -print | xargs -I{} -t -P4 bash -c "find {} -type f -mtime -90 ! -name '.*' | head -n1 | grep -q -E '.+' || mv {} $HOME/.Trash/"
    echo ""
    echo "#### Cleaning up tmp and old+large files from ${_src} ####" >&2
    echo ""
    # Delete empty and tmp/log files/directories
    ${_find} ${_src%/} -type f -mtime +7 -size 0 \( ! -name "._*" \) -delete 2>/dev/null &
    ${_find} ${_src%/} -type d -mtime +14 -name '*_tmp' -delete 2>/dev/null &
    ${_find} ${_src%/} -type f -mtime +14 -name '*.tmp' -delete 2>/dev/null &
    ${_find} ${_src%/} -type f -mtime +60 -name "*.log" -delete 2>/dev/null &
    # Delete large and old files
    ${_find} ${_src%/} -type f -mtime +90 -size +128000k -delete 2>/dev/null &
    ${_find} ${_src%/} -type f -mtime +180 -delete 2>/dev/null &

    jobs -l
    wait

    # Wait then deleting empty directories. NOTE: this find command requires "/*"
    ${_find} ${_src%/}/* -type d -mtime +2 -empty -delete
    wait

    echo ""
    echo "#### Listing any large directories ####" >&2
    echo ""
    if [ "Darwin" = "$(uname)" ]; then
        if type gdu &>/dev/null; then
            #gdu -Shx ${_src} | sort -h | tail -n40
            listLargeDirs "${_src}" 20
        else
            echo "# mdfind 'kMDItemFSSize > 209715200 && kMDItemContentModificationDate < \$time.now(-2419200)' | LC_ALL=C sort" >&2   # -onlyin "${_src}"
            mdfind 'kMDItemFSSize > 209715200 && kMDItemContentModificationDate < $time.now(-2419200)' | LC_ALL=C sort | rg -v -w 'cases_local' | while read -r _l;do ls -lh "${_l}"; done | sort -k5 -h | tail -n40
        fi
    else
        listLargeDirs "${_src}" 20
        #echo "# du -Shx ${_src} | sort -h | tail -n40" >&2
        #du -Shx ${_src} | sort -h | tail -n40
    fi

    # Currently updatedb may not index external drive (maybe because exFat?)
    if type updatedb &>/dev/null; then
        #alias of 'updatedb' = sudo FILESYSTEMS="hfs ufs apfs exfat" /usr/libexec/locate.updatedb
        echo ""
        echo "#### Executing updatedb (may ask sudo password) ####" >&2
        echo ""
        updatedb && ls -lh /var/db/locate.database
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
    local _backup_server="${1:-"dh1"}"
    if ! ping -c1 -t1 ${_backup_server}>/dev/null; then
        echo "Can't reach ${_backup_server}" >&2
    else
        [ $HOME/IdeaProjects/work/bash/install_nexus.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/work/bash/install_nexus.sh ${_backup_server}:/var/tmp/share/sonatype/ && cp -v -f $HOME/IdeaProjects/work/bash/install_nexus.sh $HOME/share/sonatype/
        [ $HOME/IdeaProjects/work/bash/install_sonatype.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/work/bash/install_sonatype.sh ${_backup_server}:/var/tmp/share/sonatype/ && cp -v -f $HOME/IdeaProjects/work/bash/install_sonatype.sh $HOME/share/sonatype/
        [ $HOME/IdeaProjects/samples/bash/setup_standalone.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/setup_standalone.sh ${_backup_server}:/usr/local/bin/
        [ $HOME/IdeaProjects/samples/runcom/nexus_alias.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/runcom/nexus_alias.sh ${_backup_server}:/var/tmp/share/sonatype/
        [ $HOME/IdeaProjects/samples/bash/utils.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/utils.sh ${_backup_server}:/var/tmp/share/ && cp -v -f $HOME/IdeaProjects/samples/bash/utils.sh $HOME/share/sonatype/
        [ $HOME/IdeaProjects/samples/bash/utils_db.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/utils_db.sh ${_backup_server}:/var/tmp/share/ && cp -v -f $HOME/IdeaProjects/samples/bash/utils_db.sh $HOME/share/sonatype/
        [ $HOME/IdeaProjects/samples/bash/utils_container.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/utils_container.sh ${_backup_server}:/var/tmp/share/ && cp -v -f $HOME/IdeaProjects/samples/bash/utils_container.sh $HOME/share/sonatype/
        [ $HOME/IdeaProjects/samples/bash/_setup_host.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/_setup_host.sh ${_backup_server}:/var/tmp/share/
        [ $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh ${_backup_server}:/var/tmp/share/sonatype/ && cp -v -f $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh $HOME/share/sonatype/ && cp -v -f $HOME/IdeaProjects/samples/bash/setup_nexus3_repos.sh $HOME/IdeaProjects/nexus-toolbox/scripts/
        [ $HOME/IdeaProjects/samples/bash/patch_java.sh -nt /tmp/pubS.last ] && scp -C $HOME/IdeaProjects/samples/bash/patch_java.sh ${_backup_server}:/var/tmp/share/java/
        [ $HOME/IdeaProjects/samples/misc/orient-console.jar -nt /tmp/pubS.last ] && scp $HOME/IdeaProjects/samples/misc/orient-console.jar ${_backup_server}:/var/tmp/share/java/
        [ $HOME/IdeaProjects/samples/misc/h2-console.jar -nt /tmp/pubS.last ] && scp $HOME/IdeaProjects/samples/misc/h2-console.jar ${_backup_server}:/var/tmp/share/java/
        [ $HOME/IdeaProjects/samples/misc/filelist_Linux_x86_64 -nt /tmp/pubS.last ] && scp $HOME/IdeaProjects/samples/misc/filelist_Linux_x86_64 ${_backup_server}:/var/tmp/share/bin/
    fi
    # If no directories, would like to see errors
    [ $HOME/IdeaProjects/work/bash/log_tests_nxrm.sh -nt /tmp/pubS.last ] && cp -v -f $HOME/IdeaProjects/work/bash/log_tests_nxrm.sh $HOME/IdeaProjects/nexus-toolbox/scripts/log_check_scripts/
    [ $HOME/IdeaProjects/samples/bash/monitoring/nrm3-threaddumps.sh -nt /tmp/pubS.last ] && cp -v -f $HOME/IdeaProjects/samples/bash/monitoring/*.sh $HOME/IdeaProjects/nexus-monitoring/scripts/
    #cp -v -f $HOME/IdeaProjects/work/nexus-groovy/src2/TrustStoreConverter.groovy $HOME/IdeaProjects/nexus-toolbox/scripts/
    [ $HOME/IdeaProjects/samples/java/asset-dupe-checker/src/main/java/AssetDupeCheckV2.java -nt /tmp/pubS.last ] && cp -v -f $HOME/IdeaProjects/samples/java/asset-dupe-checker/src/main/java/AssetDupeCheckV2.java $HOME/IdeaProjects/nexus-toolbox/asset-dupe-checker/src/main/java/ && cp -v -f $HOME/IdeaProjects/samples/misc/asset-dupe-checker-v2.jar $HOME/IdeaProjects/nexus-toolbox/asset-dupe-checker/

    if [ -d "$HOME/IdeaProjects/nexus-monitoring/resources" ]; then
        if [ $HOME/IdeaProjects/samples/misc/h2-console.jar -nt /tmp/pubS.last ]; then
            cp -v -f $HOME/IdeaProjects/samples/misc/*-console*.jar $HOME/IdeaProjects/nexus-monitoring/resources/
        fi
        if [ $HOME/IdeaProjects/samples/misc/filelist_Linux_x86_64 -nt /tmp/pubS.last ]; then
            cp -v -f $HOME/IdeaProjects/samples/misc/filelist_* $HOME/IdeaProjects/nexus-monitoring/resources/
        fi
    fi

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
    local _truststore="${3}"
    if [ -z "${_truststore}" ]; then
        if [ -f "${JAVA_HOME%/}/jre/lib/security/cacerts" ]; then
            _truststore="${JAVA_HOME%/}/jre/lib/security/cacerts"
        elif [ -f "${JAVA_HOME%/}/lib/security/cacerts" ]; then
            _truststore="${JAVA_HOME%/}/lib/security/cacerts"
        else
            return 2
        fi
    fi
    [ -z "${JAVA_HOME}" ] && return 1
    [ ! -f "${_pem}" ] && return 3
    [ -z "${_alias}" ] && _alias="$(basename "${_pem%%.*}")"
    echo 'keytool -import -alias "'${_alias}'" -keystore "'${_truststore}'" -file "'${_pem}'" -noprompt -storepass changeit' >&2
    keytool -import -alias "${_alias}" -keystore "${_truststore}" -file "${_pem}" -noprompt -storepass changeit
}



function startCommonUtils() {
    pgStatus start
    #tabby_start
    slackS
    #chrome-work
    #open -na "Google Chrome"

    if type ollama &>/dev/null; then
        ollama serve &>/tmp/ollama.log &
        sleep 3
        ollama list
    fi
    # no webUI required for pandasai or jupyterlab-ai
    #if  [ -s "$HOME/.vnevAi/bin/open-webui" ]; then
    #    source $HOME/.vnevAi/bin/activate && open-webui serve --host 127.0.0.1 --port 48080 &>/tmp/open-webui.log &
    #fi
}