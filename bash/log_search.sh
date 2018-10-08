#!/usr/bin/env bash
#
# Bunch of grep functions to search log files
# Don't use complex one, so that each function can be easily copied and pasted
#
# DOWNLOAD:
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/bash/log_search.sh
#
# TODO: tested on Mac only (eg: sed -E, ggrep)
# brew install grep     # 'grep' will install ggrep
# brew install gnu-sed  # for gsed
# brew install dateutils # for dateconv
# brew install coreutils # for gtac gdate
# curl https://raw.githubusercontent.com/hajimeo/samples/master/python/line_parser.py -o /usr/local/bin/line_parser.py
#

[ -n "$_DEBUG" ] && (set -x; set -e)

usage() {
    echo "HELP/USAGE:"
    echo "This script contains useful functions to search log files.

How to use: source, then use some function
    source ${BASH_SOURCE}
    help f_someFunctionName

    Examples:
    # Check what kind of caused by is most
    f_topCausedByExceptions ./yarn_application.log | tail -n 10

    # Check what kind of ERROR is most
    f_topErrors ./yarn_application.log | tail -n 10
Or
    ${BASH_SOURCE} -f log_file_path [-s start_date] [-e end_date] [-t log_type]
    NOTE:
      For start and end date, as using grep, may not return good result if you specify minutes or seconds.
      'log_type' currently accepts only 'ya' (yarn app log)

"
    echo "Available functions:"
    _list
}
### Public functions ###################################################################################################

function p_support() {
    local __doc__="Scan a support bundle"
    local _regex="$1"

    echo "# Version information"
    echo "## version files"
    #local _build_yaml="`find . -type f -name build.yaml -print | head -n1`"
    find . -type f -name 'versions.*.yml' -print | tee /tmp/versions_$$.out
    local _versions_yaml="`cat /tmp/versions_$$.out | sort -n | tail -n1`"
    if [ -s "${_versions_yaml}" ]; then
        echo " "
        echo "## ${_versions_yaml}"
        cat "${_versions_yaml}"
        echo " "
    fi
    echo " "

    echo "# settings.json last 3 settings changes"
    _find_and_cat "settings.json" | python -c "import sys,json;a=json.loads(sys.stdin.read());print json.dumps(a[-3:], indent=4)"
    echo " "
    echo " "

    echo "# config-custom.yaml"
    _find_and_cat "config-custom.yaml"
    echo " "
    echo " "

    echo "# (deprecated) config.yaml - Kerberos|ssl information"
    _find_and_cat "config.yaml" | grep -E '(^kerberos\.|^ssl\.|key\.path|cert\.path)'
    echo " "
    echo " "

    #echo "# config.yaml | grep -iE '(max|size|pool).+000$' | grep -vi 'time'"
    # Exact config parameter(s) which might cause issue
    # TODO: Aggregate Batch <UUID> failed creating a build order for rebuilding aggregates.
    # TODO: aggregates.maxExternalRequestDuration.timeout|aggregates.batch.buildFromExisting'
    # Try finding parameters which value might be too big
    #_find_and_cat "config.yaml" | grep -iE '(max|size|pool).+(000|mins|hours)$' | grep -vi "time"
    #echo " "
    #echo " "

    echo "# Connection pool"    # TODO: use connection_groups.json
    _find_and_cat "connection_groups.json" | python -m json.tool
    echo "--------------------------------"
    _find_and_cat "pool.json"   # check maxConnections, consecutiveFailures
    echo " "
    echo " "

    echo "# runtime.yaml"
    _find_and_cat "runtime.yaml"
    echo " "
    echo " "

    echo "# current-status.json Cache status"
    _find_and_cat "current-status.json"
    echo " "
    echo " "

    echo "# properties.json Engine properties for last 20 lines"
    _find_and_cat "properties.json" | tail -n 20
    echo " "
    echo " "

    echo "# directory_configurations.json"
    _find_and_cat "directory_configurations.json"
    echo " "
    echo " "
    f_genLdapsearch
    echo " "
    echo " "

    echo "# tableSizes.tsv 10 large tables (by num rows)"
    _find_and_cat "tableSizes.tsv" | sort -n -k2 | tail -n 10
    echo " "
}

function p_performance() {
    local _glob="${1}"
    local _date_regex="${2}"
    local _n="${3:-20}"
    local _exclude_slow_one="$4"

    # Prepare command list for _mexec (but as rg is already multi-threading, not much diff)
    if [[ ! "${_exclude_slow_one}" =~ ^(y|Y) ]]; then
        cat << EOF > /tmp/perform_cmds.tmp
f_topSlowLogs "^${_date_regex}" "${_glob}" "" "" "${_n}"                           > /tmp/perform_f_topSlowLogs_$$.out
f_topErrors "${_glob}" "${_date_regex}" "" "" "${_n}"                              > /tmp/perform_f_topErrors_$$.out
EOF
    fi
    cat << EOF >> /tmp/perform_cmds.tmp
f_checkResultSize "${_date_regex}" "${_glob}" "${_n}"                              > /tmp/perform_f_checkResultSize_$$.out
f_checkMaterializeWorkers "${_date_regex}" "${_glob}" "${_n}"                      > /tmp/perform_f_checkMaterializeWorkers_$$.out
f_failedQueries "${_date_regex}" "${_glob}" "${_n}"                                > /tmp/perform_f_failedQueries_$$.out
f_preCheckoutDuration "${_date_regex}" "${_glob}" ${_n}                            > /tmp/perform_f_preCheckoutDuration_$$.out
f_aggBatchKickoffSize "${_date_regex}" "${_glob}" ${_n}                            > /tmp/perform_f_aggBatchKickoffSize_$$.out
f_count_lines                                                                      > /tmp/perform_f_count_lines_$$.out
f_count_threads "" "${_n}"                                                         > /tmp/perform_f_count_threads_$$.out
EOF
    _mexec /tmp/perform_cmds.tmp "source $BASH_SOURCE;"

    echo "# f_checkResultSize success query size from the engine log (datetime, queryId, size, time)"
    cat /tmp/perform_f_checkResultSize_$$.out
    echo " "

    echo "# f_checkMaterializeWorkers Materialization queue size from the engine debug log"
    cat /tmp/perform_f_checkMaterializeWorkers_$$.out
    echo " "

    echo "# f_failedQueries failed queries from the engine log (datetime, queryId, time) and top ${_n}"
    cat /tmp/perform_f_failedQueries_$$.out
    echo " "

    echo "# f_preCheckoutDuration from the engine debug log (datetime, statement duration, test duration) and top ${_n}"
    cat /tmp/perform_f_preCheckoutDuration_$$.out
    echo " "

    echo "# f_aggBatchKickoffSize from the engine debug log (datetime, batchId, how many, isFullBuild) and top ${_n}"
    cat /tmp/perform_f_aggBatchKickoffSize_$$.out
    echo " "

    echo "# f_count_lines and f_count_threads against the last periodic.log for top ${_n}"
    cat /tmp/perform_f_count_lines_$$.out
    cat /tmp/perform_f_count_threads_$$.out
    echo " "

    if [[ ! "${_exclude_slow_one}" =~ ^(y|Y) ]]; then
        echo "# f_topSlowLogs from engine *debug* log if no _glob, and top ${_n}"
        cat /tmp/perform_f_topSlowLogs_$$.out
        echo " "

        echo "# f_topErrors from engine log and top ${_n}"
        cat /tmp/perform_f_topErrors_$$.out
        echo " "
    fi

    if [ -n "${_glob}" ]; then
        echo "# f_list_start_end (start time, end time, difference(sec), filesize)"
        f_list_start_end "${_glob}" "${_date_regex}"
    fi

    # TODO: hiveserver2.log Total time spent in this metastore function was greater than
}

function f_checkResultSize() {
    local __doc__="Get result sizes from the engine debug log (datetime, queryId, size, time)"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine*.log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    rg -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+ queryId=(........-....-....-....-............).+ size = ([^,]+), time = ([^,]+)," -r '${1}|${2}|${3}|${4}' | sort -n | uniq > /tmp/f_checkResultSize_$$.out
    echo "### histogram (time vs query result size) #################################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2} ${4}' /tmp/f_checkResultSize_$$.out | bar_chart.py -A
    echo ' '
    echo "### histogram (time vs query requests) ####################################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2}' /tmp/f_checkResultSize_$$.out | bar_chart.py
    echo ' '
    echo "### Large size (datetime|queryId|size|time) ###############################################"
    cat /tmp/f_checkResultSize_$$.out | sort -t '|' -nk3 | tail -n${_n} | tr '|' '\t'
    echo ' '
    echo "### Slow query (datetime|queryId|size|time) ###############################################"
    cat /tmp/f_checkResultSize_$$.out | grep ' s$' | sort -t '|' -nk4 | tail -n${_n} | tr '|' '\t'
    echo " "
    ls -lh /tmp/f_checkResultSize_$$.out
}

function f_checkMaterializeWorkers() {
    local __doc__="Check Materialization worker size (datetime, queryId, size, time)"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-debug*.log*}" # As TRACE log, needs debug log
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    local _waiting="$(rg -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+TRACE .+ No workers available for request, adding to queue of size (\d+)" -r '${1}|${2}')"
    local _working="$(rg -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+TRACE .+ Worker .+ is available to handle request" -r '${1}|-1')"
    ( echo  "${_waiting}"; echo "${_working}" ) | awk -F"|" '{print $1"|"$2+1}' | sort -n > /tmp/f_checkMaterializeWorkers_$$.out
    # Shouldn't accumulate queue size (need windowing...)
    echo "### histogram (time vs worker queue (waiting) size) #######################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)" -r '${1}T${2} ${3}' /tmp/f_checkMaterializeWorkers_$$.out | sort -n | uniq  | sort -k1,1r -k2,2nr > /tmp/f_checkMaterializeWorkers_filtered_$$.out
    for _dt in `cat /tmp/f_checkMaterializeWorkers_filtered_$$.out | cut -d" " -f1 | sort -n | uniq`; do
        grep -m 1 "^${_dt}" /tmp/f_checkMaterializeWorkers_filtered_$$.out
    done | bar_chart.py -A
    echo ' '
    echo "### histogram (time vs materialize request count) #########################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)" -r '${1}T${2}' /tmp/f_checkMaterializeWorkers_$$.out | bar_chart.py
    echo ' '
    echo "### Large materialize queue size (datetime|size) ##########################################"
    cat /tmp/f_checkMaterializeWorkers_$$.out | sort -t '|' -nk2 | tail -n${_n} | tr '|' '\t'
    echo " "
    ls -lh /tmp/f_checkMaterializeWorkers_$$.out
}

function f_failedQueries() {
    local __doc__="Get Logging query failures (datetime, queryId, time)"
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine*.log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    rg -N --no-filename -g "${_glob}" -i -o "^(${_date_regex}).+ queryId=(........-....-....-....-............).+ Logging query failure.+ time = ([^,]+)," -r '${1}|${2}|${3}' | sort -n | uniq > /tmp/f_failedQueries_$$.out
    echo "### histogram (time vs failed query count) ################################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)\|([^|]+)" -r '${1}T${2}' /tmp/f_failedQueries_$$.out | bar_chart.py
    echo ' '
    echo "### Slow failed query (datetime|queryId|time) #############################################"
    cat /tmp/f_failedQueries_$$.out | grep ' s$' | sort -t '|' -nk3 | tail -n${_n} | tr '|' '\t'
    echo " "
    ls -lh /tmp/f_failedQueries_$$.out
}

function f_preCheckoutDuration() {
    local __doc__="Get 'preCheckout timing report' from the engine debug log (datetime, statement duration, test duration)"
    # f_preCheckoutDuration | sort -t'|' -nk3 | tail -n 10
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine*.log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    # NOTE: queryId sometime is not included
    rg -N --no-filename -g "${_glob}" -o "^(${_date_regex}).+preCheckout timing report:.+statementDurations=[^=]+=([0-9,.]+) (.+)\].+testDuration=[^=]+=([0-9,.]+) (.+)\]" -r '${1}|${2}${3}|${4}${5}' | _sed -r 's/([0-9]+)\.([0-9]{2})s/\1\20ms/g' > /tmp/f_preCheckoutDuration_$$.out

    cat /tmp/f_preCheckoutDuration_$$.out | sort -t'|' -nk3 | tail -n ${_n}
    echo " "
    ls -lh /tmp/f_preCheckoutDuration_$$.out
}

function f_aggBatchKickoffSize() {
    local __doc__="Check Agg Batch Kick off count from the engine debug log (datetime, batchId, how many, isFullBuild)"
    # f_aggBatchKickoffSize | sort -t'|' -nk3 | tail -n 10
    local _date_regex="${1}"    # No need ^
    local _glob="${2:-engine*.log*}"
    local _n="${3:-20}"
    [ -z "${_date_regex}" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d+"

    rg -N --no-filename -g "${_glob}" -o "^(${_date_regex}).+ Kickoff batch (........-....-....-....-............) with ([0-9,]+) aggregate\(s\) and isFullBuild (.+)" -r '${1}|${2}|${3}|${4}' | sort > /tmp/f_aggBatchKickoffSize_$$.out

    rg -N --no-filename -g "${_glob}" -o "^(${_date_regex}).+WARN.+ Aggregate Batch.+(........-....-....-....-............).+failed with error message" -r '${1}|${2}' | sort > /tmp/f_aggBatchKickoffSize_failed_$$.out

    echo "### histogram (time vs batch aggregate size) ##############################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2} ${4}' /tmp/f_aggBatchKickoffSize_$$.out | bar_chart.py -A
    echo ' '
    echo "### histogram (time vs batch count) #######################################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)\|([^|]+)\|([^|]+)" -r '${1}T${2}' /tmp/f_aggBatchKickoffSize_$$.out | bar_chart.py
    echo ' '
    echo "### histogram (time vs failed batch count) ################################################"
    rg -N --no-filename "^(${_DATE_FORMAT}).(${_TIME_FMT4CHART}).*\|([^|]+)" -r '${1}T${2}' /tmp/f_aggBatchKickoffSize_failed_$$.out | bar_chart.py
    echo ' '
    echo "### Large size (datetime|batchId|size|full) ###############################################"
    cat /tmp/f_aggBatchKickoffSize_$$.out | sort -t '|' -nk3 | tail -n${_n} | tr '|' '\t'
    echo ' '
}

function f_rg() {
    local __doc__="Search current directory with rg"
    # f_rg '^2018-07-27 1[3-5]:.+"
    local _regex="$1"
    local _thread_num="${2:-6}"
    local _rg_opts="$3"

    if ! which rg &>/dev/null; then
        echo "'rg' is required (eg: brew install rg)" >&2
        return 101
    fi
    if [ -z "${_regex}" ]; then
        echo "No regular expression" >&2
        return 102
    fi

    local _def_rg_opts="--search-zip --no-line-number" # -g '*.json' -g '*.xml' -g '*.yaml' -g '*.yml' -g '*.log*' --heading
    # TODO: currently only ISO format YYYY-MM-DD hh:mX:XX
    local _date_regex="^[0-9-/]+ \d\d:\d"
    local _tmpfile_pfx="./rg_"
    local _regex_escaped="`echo "${_regex}" | sed "s/[^[:alnum:].-]/_/g"`"

    [ -n "${_rg_opts% }" ] && _rg_opts="${_rg_opts% } "

    # If _regex is UUID, checking if it's query ID TODO: add more logic for other types of UUID
    if [[ "${_regex}" =~ .{8}-.{4}-.{4}-.{12} ]]; then
        echo "# checking if this UUID is a query ID by searching *only* queries.log files"
        rg ${_def_rg_opts} -g 'queries.log*' "^${_DATE_FORMAT}.+${_regex}.+ (Received|Executing) (SQL|Analysis) [Qq]uery" -A 3
        echo " "
    fi

    echo "# counting matches"
    rg ${_def_rg_opts} -H -g '!*.ipynb' -g '!*.tmp' ${_rg_opts}-c "${_regex}"
    echo " "

    echo "# busy threads matching regex"
    echo "# REGEX = ${_regex}" > "${_tmpfile_pfx}1_${_regex_escaped}.tmp"
    rg ${_def_rg_opts} --no-filename -g '*.log*' ${_rg_opts}"${_regex}" \
     | sed 's/^\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)T/\1 /' \
     | sort -n | uniq >> "${_tmpfile_pfx}1_${_regex_escaped}.tmp"

    if [ "`wc -l "${_tmpfile_pfx}1_${_regex_escaped}.tmp" | awk '{print $1}'`" -gt 1 ]; then
        rg ${_def_rg_opts} -o "\b(FATAL|ERROR|WARN|WARNING|INFO|DEBUG|TRACE) +\[[^\[]+\]" \
         "${_tmpfile_pfx}1_${_regex_escaped}.tmp" > "/tmp/_f_rg_loglevels_threads_$$.tmp"
        cat "/tmp/_f_rg_loglevels_threads_$$.tmp" | sort | uniq -c | sort -rn | head -n 40

        local _first_dt="`rg ${_def_rg_opts} -m 1 -o "${_date_regex}" "${_tmpfile_pfx}1_${_regex_escaped}.tmp"`"
        local _last_cmd="tail -n1"
        which tac &>/dev/null && _last_cmd="tac"
        which gtac &>/dev/null && _last_cmd="gtac"
        local _last_dt="`${_last_cmd} "${_tmpfile_pfx}1_${_regex_escaped}.tmp" | rg ${_def_rg_opts} -m 1 -o "${_date_regex}"`"

        # @see https://raw.githubusercontent.com/hajimeo/samples/master/golang/dateregex.go
        local _date_regex_t="${_first_dt}"
        if which dateregex &>/dev/null && [ -n "${_last_dt}" ]; then
            local _date_regex_t="`dateregex "${_first_dt}0" "${_last_dt}9"`" || return $?
        fi

        # generating thread level logs for top _thread_num threads
        local _threads="$(cat "/tmp/_f_rg_loglevels_threads_$$.tmp" | awk '{print $2}' | sort | uniq -c | sort -rn | head -n ${_thread_num} | awk '{print $2}' | sed 's/[][]//g')"
        for _t in ${_threads}; do
            echo "rg ${_def_rg_opts} --no-filename -g '*.log*' ${_rg_opts}'^(${_date_regex_t}).+\[${_t}\]' | sort -n | uniq > ${_tmpfile_pfx}2_${_t}.tmp" > /tmp/f_rg_xargs_${_t}_$$.sh
        done
        # seems xargs has command length limit and -s 40K didn't work
        echo ${_threads} | xargs -n1 -P3 -I @@ bash /tmp/f_rg_xargs_@@_$$.sh

        # just for fun, drawing bar chart
        if which bar_chart.py &>/dev/null; then
            #sudo -H python -mpip install matplotlib
            #sudo -H pip install data_hacks
            [ "`wc -l "${_tmpfile_pfx}1_${_regex_escaped}.tmp" | awk '{print $1}'`" -lt 400 ] && _date_regex="^[0-9-/]+ \d\d:\d\d"
            echo ' '
            rg ${_def_rg_opts} -o "${_date_regex}" "${_tmpfile_pfx}1_${_regex_escaped}.tmp" | bar_chart.py # no longer needs sed 's/T/ /' as it's already done
        fi
    fi
    echo ' '

    echo "# grep-ing json for max 10 each..." >&2
    rg ${_def_rg_opts} -H -g '*.json' ${_rg_opts} -m 10 "${_regex}"
    echo ' '

    echo "# generated temp files (file name    start    end    diff_sec    size)" >&2
    f_list_start_end "${_tmpfile_pfx}*.tmp"
    echo ' '
    echo "# May want to also run
        f_topErrors \"engine.*log*\" '${_first_dt}0' '${_last_dt}9'
        f_checkResultSize '${_first_dt}'    # until ${_last_dt}
        f_count_lines
        f_count_threads
    " >&2
}

function f_getQueries() {
    local __doc__="Get Inbound and outbound queries with query ID from queries.log"
    # for _q in `cat /tmp/f_checkResultSize_$$.out | grep ' s$' | sort -t'|' -nrk4 | head -n20 | awk -F'|' '{print $2}'`; do echo "# $_q";f_getQueries $_q; done
    local _uuid="$1"
    local _path="$2"

    #Logging query estimation:
    #Logging query failure:         , time = \d+ (ms|s),
    #Logging query part planned:
    #Logging query planned:
    #Logging query received:
    #Logging query success:         , size = 154, time = \d+ (ms|s),
    #Logging subquery failure:      , time = \d+ (ms|s),
    #Logging subquery part planned:
    #Logging subquery started:
    #Logging subquery success:      , resultSize = 154, time = \d+ (ms|s),

    if [ -z "${_path}" ]; then
        _path="`rg -l "queryId=${_uuid}.+ (Received|Executing) (.+) [Qq]uery" | sort | head -n1`"
        [ -z "${_path}" ] && return 1
    fi

    #_grep -m 1 -Pz "(?s)queryId=${_uuid}\} - Received .+?20\d\d-\d\d-\d\d" ${_path}
    _getAfterFirstMatch "${_path}" "queryId=${_uuid}.+ (Received|Executing) (.+) [Qq]uery" "^20\d\d-\d\d-\d\d" "Y"
}

function f_genLdapsearch() {
    local __doc__="Generate ldapsearch command from a json file"
    _find_and_cat "directory_configurations.json" | python -c 'import sys,re,json
a=json.loads(sys.stdin.read());l=a[0]
p="ldaps" if l["use_ssl"] else "ldap"
r=re.search(r"^[^=]*?=?([^=]+?)[ ,@]", l["username"])
u=r.group(1) if bool(r) else l["username"]
print "LDAPTLS_REQCERT=never ldapsearch -H %s://%s:%s -D \"%s\" -b \"%s\" -W \"(%s=%s)\"" % (p, l["host_name"], l["port"], l["username"], l["base_dn"], l["user_configuration"]["unique_id_attribute"], u)'
}

function f_topCausedByExceptions() {
    local __doc__="List Caused By xxxxException (Requires rg)"
    local _path="$1"
    local _is_shorter="$2"
    local _regex="Caused by.+Exception"

    if [[ "$_is_shorter" =~ (^y|^Y) ]]; then
        _regex="Caused by.+?Exception"
    fi
    rg -N -o "$_regex" "$_path" | sort | uniq -c | sort -n
}

function f_topErrors() {
    local __doc__="List top ERRORs. NOTE: with _date_from and without may produce different result (ex: Caused by)"
    local _glob="${1:-engine*.log*}"        # file path which rg accepts and NEEDS double-quotes
    local _date_from="$2"   # ISO format datetime
    local _date_to="$3"     # ISO format datetime
    local _regex="$4"       # to overwrite default regex to detect ERRORs
    local _top_N="${5:-10}" # how many result to show

    if ! which rg &>/dev/null; then
        echo "'rg' is required (eg: brew install rg)" >&2
        return 101
    fi

    if [ -z "$_regex" ]; then
        _regex="\b(WARN|ERROR|SEVERE|FATAL|SHUTDOWN|Caused by|.+?Exception|[Ff]ailed)\b.+"
    fi

    if [ -n "${_date_from}" ]; then
        if ! which dateregex &>/dev/null; then
            echo "'dateregex' is required (@see https://raw.githubusercontent.com/hajimeo/samples/master/golang/dateregex.go)" >&2
            return 101
        fi
        local _date_regex="`dateregex "${_date_from}" "${_date_to}"`" || return $?
        _regex="^(${_date_regex}).+${_regex}"
    fi

    echo "# Regex = '${_regex}'"
    #rg --search-zip -c -g "${_glob}" "${_regex}"
    rg --search-zip --no-line-number --no-filename -g "${_glob}" -o "${_regex}" > /tmp/f_topErrors.$$.tmp

    # just for fun, drawing bar chart
    if [ -n "${_date_from}" ] && which bar_chart.py &>/dev/null; then
        local _date_regex2="^[0-9-/]+ \d\d:\d"
        [ "`wc -l /tmp/f_topErrors.$$.tmp | awk '{print $1}'`" -lt 400 ] && _date_regex2="^[0-9-/]+ \d\d:\d\d"
        echo ' '
        rg --search-zip --no-line-number --no-filename -o "${_date_regex2}" /tmp/f_topErrors.$$.tmp | sed 's/T/ /' | bar_chart.py
        echo " "
    fi

    cat "/tmp/f_topErrors.$$.tmp" | _replace_number | sort | uniq -c | sort -n | tail -n ${_top_N}
}

function f_topSlowLogs() {
    local __doc__="List top performance related log entries."
    local _date_regex="$1"
    local _glob="${2:-debug.*log*}"
    local _regex="$3"
    local _not_hiding_number="$4"
    local _top_N="${5:-10}" # how many result to show

    if [ -z "$_regex" ]; then
        _regex="\b(Caused by|slow|delay|delaying|latency|too many|not sufficient|lock held|took [1-9][0-9]+ ?ms|timeout|timed out|going into queue, is \[...+\] in line|rejecting)\b.+"
    fi
    if [ -n "${_date_regex}" ]; then
        _regex="^${_date_regex}.+${_regex}"
    fi

    echo "# Regex = '${_regex}'"
    #rg --search-zip -c -g "${_glob}" -wio "${_regex}"
    if [[ "$_not_hiding_number" =~ (^y|^Y) ]]; then
        rg --search-zip -N --no-filename -g "${_glob}" -io "$_regex" | sort | uniq -c | sort -n
    else
        # ([0-9]){2,4} didn't work also (my note) sed doesn't support \d
        rg --search-zip -N --no-filename -g "${_glob}" -io "$_regex" | _replace_number | sort | uniq -c | sort -n | tail -n ${_top_N}
    fi
}

function f_errorsAt() {
    local __doc__="List ERROR date and time"
    local _path="$1"
    local _is_showing_longer="$2"
    local _is_including_warn="$3"
    local _regex="(ERROR|SEVERE|FATAL)"

    if [[ "$_is_including_warn" =~ (^y|^Y) ]]; then
        _regex="(ERROR|SEVERE|FATAL|WARN)"
    fi

    if [[ "$_is_showing_longer" =~ (^y|^Y) ]]; then
        _regex="${_regex}.+$"
    fi

    egrep -wo "^20[12].+? $_regex" "$_path" | sort
}

function f_appLogContainersAndHosts() {
    local __doc__="List containers ID and host (from YARN app log)"
    local _path="$1"
    local _sort_by_host="$2"

    if [[ "$_sort_by_host" =~ (^y|^Y) ]]; then
        _grep "^Container: container_" "$_path" | sort -k4 | uniq
    else
        _grep "^Container: container_" "$_path" | sort | uniq
    fi
}

function f_appLogContainerCountPerHost() {
    local __doc__="Count container per host (from YARN app log)"
    local _path="$1"
    local _sort_by_host="$2"

    if [[ "$_sort_by_host" =~ (^y|^Y) ]]; then
        f_appLogContainersAndHosts "$1" | awk '{print $4}' | sort | uniq -c
    else
        f_appLogContainersAndHosts "$1" | awk '{print $4}' | sort | uniq -c | sort -n
    fi
}

function f_appLogJobCounters() {
    local __doc__="List the Job Final counters (Tez only?) (from YARN app log)"
    local _path="$1"
    local _line=""
    local _regex="(Final Counters for [^ :]+)[^\[]+(\[.+$)"

    _grep -oP "Final Counters for .+$" "$_path" | while read -r _line ; do
        if [[ "$_line" =~ ${_regex} ]]; then
            echo "# ${BASH_REMATCH[1]}"
            # TODO: not clean enough. eg: [['File System Counters HDFS_BYTES_READ=1469456609',
            echo "${BASH_REMATCH[2]}" | _sed -r 's/\[([^"\[])/\["\1/g' | _sed -r 's/([^"])\]/\1"\]/g' | _sed -r 's/([^"]), ([^"])/\1", "\2/g' | _sed -r 's/\]\[/\], \[/g' | python -m json.tool
            echo ""
        fi
    done
}

function f_appLogJobExports() {
    local __doc__="List exports in the job (from YARN app log)"
    local _path="$1"
    local _regex="^export "

    egrep "$_regex" "$_path" | sort | uniq -c
}

function f_appLogFindFirstSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was started first."
    local _dir_path="${1-.}"
    local _num="${2-10}"

    ( find "${_dir_path%/}" -name "*.syslog" | xargs -I {} bash -c "_grep -oHP '^${_DATE_FORMAT} \d\d:\d\d:\d\d' -m 1 {}" | awk -F ':' '{print $2":"$3":"$4" "$1}' ) | sort -n | head -n $_num
}

function f_appLogFindLastSyslog() {
    local __doc__="After yarn_app_logs_splitter, find which one was ended in the last. gtac/tac is required"
    local _dir_path="${1-.}"
    local _num="${2-10}"
    local _regex="${3}"

    if [ -n "$_regex" ]; then
        ( for _f in `_grep -l "$_regex" ${_dir_path%/}/*.syslog`; do _dt="`_tac $_f | _grep -oP "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    else
        ( for _f in `find "${_dir_path%/}" -name "*.syslog"`; do _dt="`_tac $_f | _grep -oP "^${_DATE_FORMAT} \d\d:\d\d:\d\d" -m 1`" && echo "$_dt $_f"; done ) | sort -nr | head -n $_num
    fi
}

function f_hdfsAuditLogCountPerTime() {
    local __doc__="Count a log file (eg.: HDFS audit) per 10 minutes"
    local _path="$1"
    local _datetime_regex="$2"

    if [ -z "$_datetime_regex" ]; then
        _datetime_regex="^${_DATE_FORMAT} \d\d:\d"
    fi

    if ! which bar_chart.py &>/dev/null; then
        echo "### bar_chart.py is missing..."
        echo "# sudo -H python -mpip install matplotlib"
        echo "# sudo -H pip install data_hacks"
        local _cmd="uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    _grep -oP "$_datetime_regex" $_path | $_cmd
}

function f_hdfsAuditLogCountPerCommand() {
    local __doc__="Count HDFS audit per command for some period"
    local _path="$1"
    local _datetime_regex="$2"

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="sort | uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    # TODO: not sure if sed regex is good (seems to work, Mac sed / gsed doesn't like +?)、Also sed doen't support ¥d
    if [ ! -z "$_datetime_regex" ]; then
        _sed -n "s@\($_datetime_regex\).*\(cmd=[^ ]*\).*src=.*\$@\1,\2@p" $_path | $_cmd
    else
        _sed -n 's:^.*\(cmd=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_hdfsAuditLogCountPerUser() {
    local __doc__="Count HDFS audit per user for some period"
    local _path="$1"
    local _per_method="$2"
    local _datetime_regex="$3"

    if [ ! -z "$_datetime_regex" ]; then
        _grep -P "$_datetime_regex" $_path > /tmp/f_hdfs_audit_count_per_user_$$.tmp
        _path="/tmp/f_hdfs_audit_count_per_user_$$.tmp"
    fi

    if ! which bar_chart.py &>/dev/null; then
        echo "## bar_chart.py is missing..."
        local _cmd="sort | uniq -c"
    else
        local _cmd="bar_chart.py"
    fi

    # TODO: not sure if sed regex is good (seems to work, Mac sed / gsed doesn't like +?)
    if [[ "$_per_method" =~ (^y|^Y) ]]; then
        _sed -n 's:^.*\(ugi=[^ ]*\) .*\(cmd=[^ ]*\).*src=.*$:\1,\2:p' $_path | $_cmd
    else
        _sed -n 's:^.*\(ugi=[^ ]*\) .*$:\1:p' $_path | $_cmd
    fi
}

function f_longGC() {
    local __doc__="List long GC (real >= 1)"
    local _path="$1"
    local _regex=", real=[1-9]"

    egrep "$_regex" "$_path"
}

function f_listPerflogEnd() {
    local __doc__="_grep </PERFLOG ...> to see duration"
    local _path="$1"
    local _sort_by_duration="$2"

    if [[ "$_sort_by_duration" =~ (^y|^Y) ]]; then
        # expecting 5th one is duration after removing start and end time
        #egrep -wo '</PERFLOG .+>' "$_path" | sort -t'=' -k5n
        # removing start and end so that we can easily compare two PERFLOG outputs
        rg -wo '</PERFLOG .+>' "$_path" | _sed -r "s/ (start|end)=[0-9]+//g" | sort -t'=' -k3n
    else
        # sorting with start time
        rg -wo '</PERFLOG .+>' "$_path" | sort -t'=' -k3n
    fi
}

function f_getPerflog() {
    local __doc__="Get lines between PERFLOG method=xxxxx"
    local _path="$1"
    local _approx_datetime="$2"
    local _thread_id="$3"
    local _method="${4-compile}"

    _getAfterFirstMatch "$_path" "^${_approx_datetime}.+ Thread-${_thread_id}\]: .+<PERFLOG method=${_method} " "Thread-${_thread_id}\]: .+<\/PERFLOG method=${_method} " | _grep -vP ": Thread-(?!${_thread_id})\]"
}

function f_findJarByClassName() {
    local __doc__="Find jar by class name (add .class in the name). If symlink needs to be followed, add -L in _search_path"
    local _class_name="$1"
    local _search_path="${2-/usr/hdp/current/*/}" # can be PID too

    # if search path is an integer, treat as PID
    if [[ $_search_path =~ ^-?[0-9]+$ ]]; then
        lsof -nPp $_search_path | _grep -oE '/.+\.(jar|war)$' | sort | uniq | xargs -I {} bash -c "less {} | _grep -qm1 -w $_class_name && echo {}"
        return
    fi
    # NOTE: some 'less' can't read jar, in that case, replace to 'jar -tvf', but may need to modify $PATH
    find $_search_path -type f -name '*.jar' -print0 | xargs -0 -n1 -I {} bash -c "less {} | _grep -m 1 -w $_class_name > /tmp/f_findJarByClassName_$$.tmp && ( echo {}; cat /tmp/f_findJarByClassName_$$.tmp )"
    # TODO: it won't search war file...
}

function f_searchClass() {
    local __doc__="Find jar by *full* class name (without .class) by using PID, which means that component needs to be running, and then export CLASSPATH, and compiles if class_name.java exists"
    local _class_name="$1"  # should be full class name but without .class
    local _pid="$2"         # PID or directory

    local _class_file_path="$( echo "${_class_name}" | sed 's/\./\//g' )"
    local _basename="$(basename ${_class_file_path})"

    if [ -d "${_pid}" ]; then
        _grep -l -Rs "${_class_file_path}" "${_pid}"
        return $?
    fi

    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe`)" || return $?
    which ${_cmd_dir}/jar &>/dev/null || return 1

    if [ ! -s /tmp/f_searchClass_${_basename}_jars.out ]; then
        ls -l /proc/${_pid}/fd | _grep -oE '/.+\.(jar|war)$' > /tmp/f_searchClass_${_pid}.out
        cat /tmp/f_searchClass_${_pid}.out | sort | uniq | xargs -I {} bash -c ${_cmd_dir}'/jar -tvf {} | _grep -E "'${_class_file_path}'.class" > /tmp/f_searchClass_'${_basename}'_tmp.out && echo {} && cat /tmp/f_searchClass_'${_basename}'_tmp.out >&2' | tee /tmp/f_searchClass_${_basename}_jars.out
    else
        cat /tmp/f_searchClass_${_basename}_jars.out
    fi
}

function f_classpath() {
    local __doc__="Ooutput classpath of the given PID"
    local _pid="$1"
    local _user="`stat -c '%U' /proc/${_pid}`" || return $?
    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe`)" || return $?
    sudo -u ${_user} ${_cmd_dir}/jcmd ${_pid} VM.system_properties | _grep '^java.class.path=' | sed 's/\\:/:/g' | cut -d"=" -f 2
}

function f_patchJar() {
    local __doc__="Find jar by *full* class name (without .class) by using PID, which means that component needs to be running, and then export CLASSPATH, and compiles if class_name.java exists"
    local _class_name="$1" # should be full class name but without .class
    local _pid="$2"

    local _class_file_path="$( echo "${_class_name}" | sed 's/\./\//g' )"
    local _basename="$(basename ${_class_file_path})"
    local _dirname="$(dirname ${_class_file_path})"
    local _cmd_dir="$(dirname `readlink /proc/${_pid}/exe`)" || return $?
    which ${_cmd_dir}/jar &>/dev/null || return 1
    ls -l /proc/${_pid}/fd | _grep -oE '/.+\.(jar|war)$' > /tmp/f_patchJar_${_pid}.out

    # If needs to compile but _jars.out exist, don't try searching as it takes long time
    if [ ! -s /tmp/f_patchJar_${_basename}_jars.out ]; then
        cat /tmp/f_patchJar_${_pid}.out | sort | uniq | xargs -I {} bash -c ${_cmd_dir}'/jar -tvf {} | _grep -E "'${_class_file_path}'.class" > /tmp/f_patchJar_'${_basename}'_tmp.out && echo {} && cat /tmp/f_patchJar_'${_basename}'_tmp.out >&2' | tee /tmp/f_patchJar_${_basename}_jars.out
    else
        echo "/tmp/f_patchJar_${_basename}_jars.out exists. Reusing..."
    fi

    if [ -e "${_cmd_dir}/jcmd" ]; then
        local _cp="`f_classpath ${_pid}`"
    else
        # if wokring classpath exist, use it
        if [ -s /tmp/f_patchJar_${_basename}_${_pid}_cp.out ]; then
            local _cp="$(cat /tmp/f_patchJar_${_basename}_${_pid}_cp.out)"
        else
            local _cp=$(cat /tmp/f_patchJar_${_pid}.out | tr '\n' ':')
        fi
    fi

    if [ -r "${_basename}.java" ]; then
        [ -z "${_cp}" ] && return 1

        if [ -z "$_CLASSPATH" ]; then
            export CLASSPATH="${_cp%:}"
        else
            export CLASSPATH="${_cp%:}:$_CLASSPATH"
        fi

        # Compile
        ${_cmd_dir}/javac "${_basename}.java" || return $?
        # Saving workign classpath if able to compile
        echo $CLASSPATH > /tmp/f_patchJar_${_basename}_${_pid}_cp.out
        [ -d "${_dirname}" ] || mkdir -p ${_dirname}
        mv -f ${_basename}*class "${_dirname%/}/" || return $?

        for _j in `cat /tmp/f_patchJar_${_basename}_jars.out`; do
            local _j_basename="$(basename ${_j})"
            # If jar file hasn't been backed up, taking one, and if backup fails, skip this jar.
            if [ ! -s ${_j_basename} ]; then
                cp -p ${_j} ./${_j_basename} || continue
            fi
            eval "${_cmd_dir}/jar -uf ${_j} ${_dirname%/}/${_basename}*class"
            ls -l ${_j}
            ${_cmd_dir}/jar -tvf ${_j} | _grep -F "${_dirname%/}/${_basename}"
        done
    else
        echo "${_basename}.java is not readable."
    fi
}

# TODO: find hostname and container, splits, actual query (mr?) etc from app log

function f_extractByDates() {
    local __doc__="Grep large file with date string"
    local _log_file_path="$1"
    local _start_date="$2"
    local _end_date="$3"
    local _date_format="$4"
    local _is_utc="$6"

    local _date_regex=""
    local _date="_date"

    # in case file path includes wildcard
    ls -1 $_log_file_path &>/dev/null
    if [ $? -ne 0 ]; then
        return 3
    fi

    if [ -z "$_start_date" ]; then
        return 4
    fi

    if [ -z "$_date_format" ]; then
        _date_format="%Y-%m-%d %H:%M:%S"
    fi

    if [[ "$_is_utc" =~ (^y|^Y) ]]; then
        _date="_date -u"
    fi

    # if _start_date is integer, treat as from X hours ago
    if [[ $_start_date =~ ^-?[0-9]+$ ]]; then
        _start_date="`$_date +"$_date_format" -d "${_start_date} hours ago"`" || return 5
    fi

    # if _end_date is integer, treat as from X hours ago
    if [[ $_end_date =~ ^-?[0-9]+$ ]]; then
        _end_date="`$_date +"$_date_format" -d "${_start_date} ${_end_date} hours ago"`" || return 6
    fi

    eval "_getAfterFirstMatch \"$_log_file_path\" \"$_start_date\" \"$_end_date\""

    return $?
}

function f_splitApplog() {
    local __doc__="Split YARN App log with yarn_app_logs_splitter.py"
    local _app_log="$1"
    local _out_name="containers_`basename $_app_log .log`"
    # Assuming yarn_app_logs_splitter.py is in the following location
    local _script_path="$(dirname "$_SCRIPT_DIR")/misc/yarn_app_logs_splitter.py"
    if [ ! -s "$_script_path" ]; then
        echo "$_script_path does not exist. Downloading..."
        if [ ! -d "$(dirname "${_script_path}")" ]; then
            mkdir -p "$(dirname "${_script_path}")" || return $?
        fi
        curl -so "${_script_path}" https://raw.githubusercontent.com/hajimeo/samples/master/misc/yarn_app_logs_splitter.py || return $?
    fi
    if [ ! -r "$_app_log" ]; then
        echo "$_app_log is not readable"
        return 1
    fi
    #_grep -Fv "***********************************************************************" $_app_log > /tmp/${_app_log}.tmp
    python "$_script_path" --container-log-dir $_out_name --app-log "$_app_log"
}

function f_swimlane() {
    local __doc__="TODO: use swimlane (but broken?)"
    local _app_log="$1"
    local _out_name="`basename $_app_log .log`.svg"
    local _tmp_name="`basename $_app_log .log`.tmp"
    local _script_path="`dirname $(dirname $(dirname $BASH_SOURCE))`/tez/tez-tools/swimlanes/swimlane.py"
    _grep 'HISTORY' $_app_log > ./$_tmp_name
    if [ ! -s "$_tmp_name" ]; then
        echo "$_tmp_name is empty."
        return 1
    fi
    if [ ! -s "$_script_path" ]; then
        echo "$_script_path does not exist"
        return 1
    fi
    python "$_script_path" -o $_out_name $_tmp_name
}

function f_list_start_end(){
    local __doc__="Output start time, end time, difference(sec), (filesize) from *multiple* log files"
    local _glob="${1}"
    local _date_regex="${2:-${_DATE_FORMAT}.\d\d:\d\d:\d\d}"
    local _sort="${3:-2}"
    # If no file(s) given, check current working directory
    if [ -n "${_glob}" ]; then
        _files="`find . -type f -name "${_glob}" -print`"
    else
        local _files="`ls -1`"
    fi
    for _f in `echo ${_files}`; do f_start_end_time_with_diff $_f "^${_date_regex}"; done | sort -t$'\t' -k${_sort}
}

function f_start_end_time_with_diff(){
    local __doc__="Output start time, end time, difference(sec), (filesize) from a log file (eg: for _f in \`ls\`; do f_start_end_time_with_diff \$_f \"^${_DATE_FORMAT}.\d\d:\d\d:\d\d,\d\d\d\"; done | sort -t$'\\t' -k2)"
    local _log="$1"
    local _date_regex="${2}"
    [ -z "$_date_regex" ] && _date_regex="${_DATE_FORMAT}.\d\d:\d\d:\d\d"

    local _start_date=`rg --search-zip -N -om1 "^$_date_regex" ${_log} | sed 's/T/ /'` || return $?
    local _extension="${_log##*.}"
    if [ "${_extension}" = 'gz' ]; then
        local _end_date=`gunzip -c ${_log} | _tac | rg -N -om1 "^$_date_regex" | sed 's/T/ /'` || return $?
    else
        local _end_date=`_tac ${_log} | rg --search-zip -N -om1 "^$_date_regex" | sed 's/T/ /'` || return $?
    fi
    local _start_int=`_date2int "${_start_date}"`
    local _end_int=`_date2int "${_end_date}"`
    local _diff=$(( $_end_int - $_start_int ))
    # Filename, start datetime, enddatetime, difference, (filesize)
    echo -e "`basename ${_log}`\t${_start_date}\t${_end_date}\t${_diff}s\t$((`wc -c <${_log}` / 1024))KB"
}

function f_split_strace() {
    local __doc__="Split a strace output, which didn't use -ff, per PID. As this function may take time, it should be safe to cancel at any time, and re-run later"
    local _strace_file="$1"
    local _save_dir="${2-./}"
    local _reverse="$3"

    local _cat="cat"
    if [[ "${_reverse}" =~ (^y|^Y) ]]; then
        which tac &>/dev/null && _cat="tac"
        which gtac &>/dev/null && _cat="gtac"
    fi

    [ ! -d "${_save_dir%/}" ] && ( mkdir -p "${_save_dir%/}" || return $? )
    if [ ! -s "${_save_dir%/}/_pid_list.tmp" ]; then
        awk '{print $1}' "${_strace_file}" | sort -n | uniq > "${_save_dir%/}/_pid_list.tmp"
    else
        echo "${_save_dir%/}/_pid_list.tmp exists. Reusing..." 1>&2
    fi

    for _p in `${_cat} "${_save_dir%/}/_pid_list.tmp"`
    do
        if [ -s "${_save_dir%/}/${_p}.out" ]; then
            if [[ "${_reverse}" =~ (^y|^Y) ]]; then
                echo "${_save_dir%/}/${_p}.out exists. As reverse mode, exiting..." 1>&2
                return
            fi
            echo "${_save_dir%/}/${_p}.out exists. skipping..." 1>&2
            continue
        fi
        _grep "^${_p} " "${_strace_file}" > "${_save_dir%/}/.${_p}.out" && mv -f "${_save_dir%/}/.${_p}.out" "${_save_dir%/}/${_p}.out"
    done
}


function f_git_search() {
    local __doc__="Grep git comments to find matching branch or tag"
    local _search="$1"
    local _git_dir="$2"
    local _is_fetching="$3"
    local _is_showing_grep_result="$4"

    if [ -d "$_git_dir" ]; then
       cd "$_git_dir"
    fi

    if [[ "$_is_fetching" =~ (^y|^Y) ]]; then
        git fetch
    fi

    local _grep_result="`git log --all --grep "$_search"`"
    if [[ "$_is_showing_grep_result" =~ (^y|^Y) ]]; then
        echo "$_grep_result"
    fi

    local _commits_only="`echo "$_grep_result" | _grep ^commit | cut -d ' ' -f 2`"

    echo "# Searching branches ...."
    for c in $_commits_only; do git branch -r --contains $c; done | sort
    echo "# Searching tags ...."
    for c in $_commits_only; do git tag --contains $c; done | sort
}

function f_os_checklist() {
    local __doc__="Check OS kernel parameters"
    local _conf="${1-./}"

    #cat /sys/kernel/mm/transparent_hugepage/enabled
    #cat /sys/kernel/mm/transparent_hugepage/defrag

    # 1. check "sysctl -a" output
    local _props="vm.zone_reclaim_mode vm.swappiness vm.dirty_ratio vm.dirty_background_ratio kernel.shmmax vm.oom_dump_tasks net.core.somaxconn net.core.netdev_max_backlog net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.ipv4.ip_local_port_range net.ipv4.tcp_mtu_probing net.ipv4.tcp_fin_timeout net.ipv4.conf.*.forwarding"

    _search_properties "${_conf%/}" "${_props}"
}

function f_hdfs_checklist() {
    local __doc__="Store HDFS config checklist in this function"
    local _conf="${1-./}"

    # 1. check the following properties' values
    local _props="dfs.namenode.audit.log.async dfs.namenode.servicerpc-address dfs.namenode.handler.count dfs.namenode.service.handler.count dfs.namenode.lifeline.rpc-address ipc.[0-9]+.backoff.enable ipc.[0-9]+.callqueue.impl dfs.namenode.name.dir< dfs.journalnode.edits.dir dfs.namenode.accesstime.precision"

    _search_properties "${_conf%/}/*-site.xml" "${_props}" "Y"

    # 2. Check log4j config for performance
    _grep -P '^log4j\..+\.(BlockStateChange|StateChange)' ${_conf%/}/log4j.properties
}

function f_hive_checklist() {
    local __doc__="Store Hive config checklist in this function"
    local _conf="${1-./}"   # set / set -v output or hive-site.xml
    local _others="$2"      # check HDFS, YARN, MR2 configs if 'y'

    # 1. check the following properties' values
    # _grep -ohP '\(property\(.+$' * | cut -d '"' -f 2 | tr '\n' ' '

    echo "# Hive config check" >&2
    local _props="hive.auto.convert.join hive.merge.mapfiles hive.merge.mapredfiles hive.exec.compress.intermediate hive.exec.compress.output datanucleus.cache.level2.type hive.default.fileformat.managed hive.default.fileformat fs.hdfs.impl.disable.cache fs.file.impl.disable.cache hive.cbo.enable hive.compute.query.using.stats hive.stats.fetch.column.stats hive.stats.fetch.partition.stats hive.execution.engine datanucleus.fixedDatastore hive.exim.strict.repl.tables datanucleus.autoCreateSchema hive.exec.parallel hive.plan.serialization.format hive.server2.tez.initialize.default.sessions hive.vectorized.execution.enabled hive.vectorized.execution.reduce.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Tez config check" >&2
    _props="tez.am.am-rm.heartbeat.interval-ms.max tez.runtime.transfer.data-via-events.enabled tez.session.am.dag.submit.timeout.secs tez.am.container.reuse.enabled tez.runtime.io.sort.mb tez.session.client.timeout.secs tez.runtime.shuffle.memory-to-memory.enable tez.runtime.task.input.post-merge.buffer.percent tez.am.container.session.delay-allocation-millis tez.session.am.dag.submit.timeout.secs tez.runtime.shuffle.fetch.buffer.percent tez.task.am.heartbeat.interval-ms.max tez.task.am.heartbeat.counter.interval-ms.max tez.task.get-task.sleep.interval-ms.max tez.task.scale.memory.enabled"
    _search_properties "${_conf%/}" "${_props}"

    echo -e "\n# Hive extra config check" >&2
    _props="hive.metastore.client.connect.retry.delay hive.metastore.client.connect.retry.delay hive.metastore.failure.retries hive\..*aux.jars.path hive.server2.async.exec.threads hive\.server2\..*\.threads hive.tez.java.opts hive.server2.idle.session.check.operation hive.server2.session.check.interval hive.server2.idle.session.timeout hive.server2.idle.operation.timeout tez.session.am.dag.submit.timeout.secs tez.yarn.ats.event.flush.timeout.millis hive.llap.* fs.permissions.umask-mode hive.optimize.reducededuplication"
    _search_properties "${_conf%/}" "${_props}"

    # 2. Extra properties from set output
    echo -e "\n# hadoop common (mainly from core-site.xml and set -v required)" >&2
    _props="hadoop\.proxyuser\..* hadoop\.ssl\..* hadoop\.http\.authentication\..* ipc\.client\..*"
    _search_properties "${_conf%/}" "${_props}"

    if [[ "$_others" =~ (^y|^Y) ]]; then
        echo -e "\n# HDFS config check" >&2
        _props="hdfs.audit.logger dfs.block.access.token.enable dfs.blocksize dfs.namenode.checkpoint.period dfs.datanode.failed.volumes.tolerated dfs.datanode.max.transfer.threads dfs.permissions.enabled hadoop.security.group.mapping fs.defaultFS dfs.namenode.accesstime.precision dfs.ha.automatic-failover.enabled dfs.namenode.checkpoint.txns dfs.namenode.stale.datanode.interval dfs.namenode.name.dir dfs.namenode.handler.count dfs.namenode.metrics.logger.period.seconds dfs.namenode.name.dir dfs.namenode.top.enabled fs.protected.directories dfs.replication dfs.namenode.name.dir.restore dfs.namenode.safemode.threshold-pct dfs.namenode.avoid.read.stale.datanode dfs.namenode.avoid.write.stale.datanode dfs.replication dfs.client.block.write.replace-datanode-on-failure.enable dfs.client.block.write.replace-datanode-on-failure.policy dfs.client.block.write.replace-datanode-on-failure.best-effort dfs.datanode.du.reserved hadoop.security.logger dfs.client.read.shortcircuit dfs.domain.socket.path fs.trash.interval ha.zookeeper.acl ha.health-monitor.rpc-timeout.ms dfs.namenode.replication.work.multiplier.per.iteration"
        _search_properties "${_conf%/}" "${_props}"

        echo -e "\n# YARN config check" >&2
        _props="yarn.timeline-service.generic-application-history.save-non-am-container-meta-info yarn.timeline-service.enabled hadoop.security.authentication yarn.timeline-service.http-authentication.type yarn.timeline-service.store-class yarn.timeline-service.ttl-enable yarn.timeline-service.ttl-ms yarn.acl.enable yarn.log-aggregation-enable yarn.nodemanager.recovery.enabled yarn.resourcemanager.recovery.enabled yarn.resourcemanager.work-preserving-recovery.enabled yarn.nodemanager.local-dirs yarn.nodemanager.log-dirs yarn.nodemanager.resource.cpu-vcores yarn.nodemanager.vmem-pmem-ratio"
        _search_properties "${_conf%/}" "${_props}"

        echo -e "\n# MR config check" >&2
        _props="mapreduce.map.output.compress mapreduce.output.fileoutputformat.compress io.sort.factor mapreduce.task.io.sort.mb mapreduce.map.sort.spill.percent mapreduce.map.speculative mapreduce.input.fileinputformat.split.maxsize mapreduce.input.fileinputformat.split.minsize mapreduce.reduce.shuffle.parallelcopies mapreduce.reduce.speculative mapreduce.job.reduce.slowstart.completedmaps mapreduce.tasktracker.group"
        _search_properties "${_conf%/}" "${_props}"
    fi

    # 3. Extra properties from set output
    if [ -f "$_conf" ]; then
        echo -e "\n# System:java" >&2
        # |system:java\.class\.path
        _grep -P '^(env:HOSTNAME|env:HADOOP_HEAPSIZE|env:HADOOP_CLIENT_OPTS|system:hdp\.version|system:java\.home|system:java\.vm\.*|system:java\.io\.tmpdir|system:os\.version|system:user\.timezone)=' "$_conf"
    fi
}

_COMMON_QUERIE_UPDATES="UPDATE users SET user_password='538916f8943ec225d97a9a86a2c6ec0818c1cd400e09e03b660fdaaec4af29ddbb6f2b1033b81b00' WHERE user_name='admin' and user_type='LOCAL';"
_COMMON_QUERIE_SELECTS="select * from metainfo where metainfo_key = 'version';select repo_version_id, stack_id, display_name, repo_type, substring(repositories, 1, 500) from repo_version order by repo_version_id desc limit 5;SELECT * FROM clusters WHERE security_type = 'KERBEROS';"
function f_load_ambaridb_to_postgres() {
    local __doc__="Load ambari DB sql file into Mac's (locals) PostgreSQL DB"
    local _sql_file="$1"
    local _missing_tables_sql="$2"
    local _sudo_user="${3-$USER}"
    local _ambari_pwd="${4-bigdata}"

    # If a few tables are missing, need missing tables' schema
    # pg_dump -Uambari -h `hostname -f` ambari -s -t alert_history -t host_role_command -t execution_command -t request > ambari_missing_table_ddl.sql

    if ! sudo -u ${_sudo_user} -i psql template1 -c '\l+'; then
        echo "Connecting to local postgresql failed. Is PostgreSQL running?"
        echo "pg_ctl -D /usr/local/var/postgres -l ~/postgresql.log restart"
        return 1
    fi
    sleep 3q

    #echo "sudo -iu ${_sudo_user} psql template1 -c 'DROP DATABASE ambari;'"
    if ! sudo -iu ${_sudo_user} psql template1 -c 'ALTER DATABASE ambari RENAME TO ambari_'$(date +"%Y%m%d%H%M%S") ; then
        sudo -iu ${_sudo_user} psql template1 -c "select pid, usename, application_name, client_addr, client_port, waiting, state, query_start, query, xact_start from pg_stat_activity where datname='ambari'"
        return 1
    fi
    sudo -iu ${_sudo_user} psql template1 -c 'CREATE DATABASE ambari;'
    sudo -iu ${_sudo_user} psql template1 -c "CREATE USER ambari WITH LOGIN PASSWORD '${_ambari_pwd}';"
    sudo -iu ${_sudo_user} psql template1 -c 'GRANT ALL PRIVILEGES ON DATABASE ambari TO ambari;'

    export PGPASSWORD="${_ambari_pwd}"
    psql -Uambari -h `hostname -f` ambari -c 'CREATE SCHEMA ambari;ALTER SCHEMA ambari OWNER TO ambari;'

    # TODO: may need to replace the schema if not 'ambari'
    #_sed -i'.bak' -r 's/\b(custom_schema|custom_owner)\b/ambari/g' ambari.sql

    # It's OK to see relation error for index (TODO: upgrade table may fail)
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` ambari < ${_sql_file}
    [ -s "$_missing_tables_sql" ] && psql -Uambari -h `hostname -f` ambari < ${_missing_tables_sql}
    psql -Uambari -h `hostname -f` -c "${_COMMON_QUERIE_UPDATES}"
    psql -Uambari -h `hostname -f` -c "${_COMMON_QUERIE_SELECTS}"

    echo "psql -Uambari -h `hostname -f` -xc \"UPDATE clusters SET security_type = 'NONE' WHERE provisioning_state = 'INSTALLED' and security_type = 'KERBEROS';\""
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/services/KERBEROS"
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/artifacts/kerberos_descriptor"
    unset PGPASSWORD
}

function f_load_ambaridb_to_mysql() {
    local __doc__="Load ambari DB sql file into Mac's (locals) MySQL DB"
    local _sql_file="$1"
    local _missing_tables_sql="$2"
    local _sudo_user="${3-$USER}"
    local _ambari_pwd="${4-bigdata}"

    # If a few tables are missing, need missing tables' schema
    # pg_dump -Uambari -h `hostname -f` ambari -s -t alert_history -t host_role_command -t execution_command -t request > ambari_missing_table_ddl.sql

    if ! mysql -u root -e 'show databases'; then
        echo "Connecting to local MySQL failed. Is MySQL running?"
        echo "brew services start mysql"
        return 1
    fi

    mysql -u root -e "CREATE USER 'ambari'@'%' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'%';
CREATE USER 'ambari'@'localhost' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'localhost';
CREATE USER 'ambari'@'`hostname -f`' IDENTIFIED BY '${_ambari_pwd}';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'`hostname -f`';
FLUSH PRIVILEGES;"

    if ! mysql -uambari -p${_ambari_pwd} -h `hostname -f` -e 'create database ambari'; then
        echo "Please drop the database first as renaming DB on MySQL is hard"
        echo "mysql -uambari -p${_ambari_pwd} -h `hostname -f` -e 'DROP DATABASE ambari;'"
        return
    fi

    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari < "${_sql_file}"

    # TODO: _missing_tables_sql
    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e "${_COMMON_QUERIE_UPDATES}"
    mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e "${_COMMON_QUERIE_SELECTS}"

    echo "mysql -u ambari -p${_ambari_pwd} -h `hostname -f` ambari -e \"UPDATE clusters SET security_type = 'NONE' WHERE provisioning_state = 'INSTALLED' and security_type = 'KERBEROS';\""
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/services/KERBEROS"
    #curl -i -H "X-Requested-By:ambari" -u admin:admin -X DELETE "http://$AMBARI_SERVER:8080/api/v1/clusters/$CLUSTER/artifacts/kerberos_descriptor"
}

function f_gc_before_after_check() {
    local __doc__="TODO: add PrintClassHistogramBeforeFullGC, and parse log to find which objects are increasing"
    return
    # TODO: _grep -F '#instances' -A 20 solr_gc.log | _grep -E -- '----------------|org.apache'
    export JAVA_GC_LOG_DIR="/some/location"
    export JAVA_GC_OPTS="-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${JAVA_GC_LOG_DIR%/}/ \
    -XX:+PrintClassHistogramBeforeFullGC -XX:+PrintClassHistogramAfterFullGC \
    -XX:+TraceClassLoading -XX:+TraceClassUnloading \
    -verbose:gc -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps \
    -Xloggc:${JAVA_GC_LOG_DIR}/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1024k"
}

function f_validate_siro_ini() {
    local __doc__="TODO: Read shiro config file and, at least, generate ldapsarch command"
    return
}

function f_count_lines() {
    local __doc__="Count lines between _search_regex of periodic.log"
    local _file="$1"
    local _search_regex="${2:-"^20\\d\\d-\\d\\d-\\d\\d .+Periodic stack trace 1"}"
    [ -z "${_file}" ] && _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    local _ext="${_file##*.}"
    if [[ "${_ext}" =~ gz ]]; then
        local _line_num=`gunzip -c ${_file} | wc -l`
        _grep -nP "${_search_regex}" <(gunzip -c ${_file}) | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    else
        local _line_num=`wc -l ${_file}`
        _grep -nP "${_search_regex}" ${_file} | rg -o '^(\d+):(2\d\d\d-\d\d-\d\d) (\d\d:\d\d)' -r '${2}T${3} ${1}' | line_parser.py thread_num ${_line_num} | bar_chart.py -A
    fi
}

function f_count_threads() {
    local __doc__="Grep periodic log and count threads of periodic.log"
    local _file="$1"
    local _tail_n="${2-10}"
    [ -z "${_file}" ] &&  _file="`find . -name periodic.log -print | head -n1`" && ls -lh ${_file}
    if [ -n "${_tail_n}" ]; then
        rg -N -o '^"([^"]+)"' -r '$1' "${_file}" | _sed -r 's/-[0-9]+$//g' | sort | uniq -c | sort -n | tail -n ${_tail_n}
    else
        rg -N -o '^"([^"]+)"' -r '$1' "${_file}" | sort | uniq
    fi
}


### Private functions ##################################################################################################

function _mexec() {
    local __doc__="Execute multple commands concurrently. NOTE: seems Mac's xargs has command length limit and no -r to ignore empty line"
    local _cmds_list="$1"
    local _prefix_cmd="$2"  # NOTE: no ";"
    local _suffix_cmd="$3"  # NOTE: no ";"
    local _num_process="${4:-3}"
    if [ -f "${_cmds_list}" ]; then
        cat "${_cmds_list}"
    else
        echo ${_cmds_list}
    fi | tr '\n' '\0' | xargs -0 -n1 -P${_num_process} -I @@ bash -c "${_prefix_cmd}@@${_suffix_cmd}"
}

function _split() {
    local _rtn_var_name="$1"
    local _string="$2"
    local _delimiter="${3-,}"
    local _original_IFS="$IFS"
    eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
    IFS="$_original_IFS"
}

function _getAfterFirstMatch() {
    local _file_path="$1"
    local _start_regex="$2"
    local _end_regex="$3"
    local _exclude_first_line="$4"
    local _extension="${_file_path##*.}"

    local _start_line_num=`rg -n -m1 "$_start_regex" "$_file_path" | cut -d ":" -f 1`
    if [ -n "$_start_line_num" ]; then
        local _end_line_num="\$"
        if [ -n "$_end_regex" ]; then
            #_sed -n "${_start_line_num},\$s/${_end_regex}/&/p" "$_file_path"
            local _tmp_start_line_num=$_start_line_num
            [[ "$_exclude_first_line" =~ ^(y|Y) ]] && _tmp_start_line_num=$(($_start_line_num + 1))
            if [ "${_extension}" = 'gz' ]; then
                _end_line_num=`gunzip -c "$_file_path" | tail -n +${_tmp_start_line_num} | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            else
                _end_line_num=`tail -n +${_tmp_start_line_num} "$_file_path" | _grep -m1 -nP "$_end_regex" | cut -d ":" -f 1`
            fi
            _end_line_num=$(( $_end_line_num + $_start_line_num - 1 ))
        fi
        if [ "${_extension}" = 'gz' ]; then
            gunzip -c "${_file_path}" | _sed -n "${_start_line_num},${_end_line_num}p"
        else
            _sed -n "${_start_line_num},${_end_line_num}p" "${_file_path}"
        fi
    fi
}

function _date2int() {
    local _date_str="$1"
    [[ "${_date_str}" =~ ^[0-9][0-9]\/[0-9][0-9]\/[0-9][0-9].[0-9][0-9]:[0-9][0-9]:[0-9][0-9] ]] && _date_str="`dateconv "${_date_str}" -i "%y/%m/%d %H:%M:%S" -f "%Y-%m-%d %H:%M:%S"`"
    _date -d "${_date_str}" +"%s"
}

function _find_and_cat() {
    local _f="`find . -name "$1" -print`"
    cat "${_f}"
}

function _replace_number() {
    _sed -r "s/[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+/__UUID__/g" \
     | _sed -r "s/0x[0-9a-f][0-9a-f]+/0x_HEX_/g" \
     | _sed -r "s/20[0-9][0-9][-/][0-9][0-9][-/][0-9][0-9][ T]/_DATE_ /g" \
     | _sed -r "s/[0-2][0-9]:[0-6][0-9]:[0-6][0-9][.,0-9]*/_TIME_/g" \
     | _sed -r "s/-[0-9]+\]\s+\{/-N] {/g" \
     | _sed -r "s/[0-9][0-9][0-9][0-9][0-9]+/_NUM_/g"
}

function _search_properties() {
    local _path="${1-./}"
    local _props="$2" # space separated regex
    local _is_name_value_xml="$3"

    for _p in ${_props}; do
        if [[ "${_is_name_value_xml}" =~ (^y|^Y) ]]; then
            local _out="`_grep -Pzo "(?s)<name>${_p}</name>.+?</value>" ${_path}`"
            [[ "${_out}" =~ (<value>)(.*)(</value>) ]]
            echo "${_p}=${BASH_REMATCH[2]}"
        else
            # Expecting hive 'set' command output or similar style (prop=value)
            _grep -P "${_p}" ${_path}
        fi
    done
}

function _sed() {
    local _cmd="sed"; which gsed &>/dev/null && _cmd="gsed"
    ${_cmd} "$@"
}
function _grep() {
    local _cmd="grep"; which grep &>/dev/null && _cmd="ggrep"
    ${_cmd} "$@"
}
function _date() {
    local _cmd="date"; which gdate &>/dev/null && _cmd="gdate"
    ${_cmd} "$@"
}
function _tac() {
    local _cmd="tac"; which gtac &>/dev/null && _cmd="gtac"
    ${_cmd} "$@"
}



### Help ###############################################################################################################

help() {
    local _function_name="$1"
    local _show_code="$2"
    local _doc_only="$3"

    if [ -z "$_function_name" ]; then
        echo "help <function name> [Y]"
        echo ""
        _list "func"
        echo ""
        return
    fi

    local _output=""
    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | _grep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            echo "Function name '$_function_name' does not exist."
            return 1
        fi

        eval "$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        if [ -z "$__doc__" ]; then
            _output="No help information in function name '$_function_name'.\n"
        else
            _output="$__doc__"
            if [[ "${_doc_only}" =~ (^y|^Y) ]]; then
                echo -e "${_output}"; return
            fi
        fi

        local _params="$(type $_function_name 2>/dev/null | _grep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | _grep -v awk)"
        if [ -n "$_params" ]; then
            _output="${_output}Parameters:\n"
            _output="${_output}${_params}\n"
        fi
        if [[ "${_show_code}" =~ (^y|^Y) ]] ; then
            _output="${_output}\n${_code}\n"
            echo -e "${_output}" | less
        elif [ -n "$_output" ]; then
            echo -e "${_output}"
            echo "(\"help $_function_name y\" to show code)"
        fi
    else
        echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}
_list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | _grep -P '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | _sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | _grep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | _grep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | _grep ^[r]_
    fi
}

### Global variables ###################################################################################################
# TODO: Not using at this moment
_IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
_IP_RANGE_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])?$'
_HOSTNAME_REGEX='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
_TEST_REGEX='^\[.+\]$'
[ -z "$_DATE_FORMAT" ] && _DATE_FORMAT="\d\d\d\d-\d\d-\d\d"
[ -z "$_TIME_FMT4CHART" ] && _TIME_FMT4CHART="\d\d:\d"
_SCRIPT_DIR="$(dirname $(realpath "$BASH_SOURCE"))"


### Main ###############################################################################################################
if [ "$0" = "$BASH_SOURCE" ]; then
    # parsing command options
    while getopts "f:s:e:t:h" opts; do
        case $opts in
            f)
                _FILE_PATH="$OPTARG"
                ;;
            s)
                _START_DATE="$OPTARG"
                ;;
            e)
                _END_DATE="$OPTARG"
                ;;
            t)
                _LOG_TYPE="$OPTARG"
                ;;
            h)
                usage | less
                exit 0
        esac
    done

    if [ -z "$_FILE_PATH" ]; then
        usage
        exit
    fi

    if [ ! -s "$_FILE_PATH" ]; then
        echo "$_FILE_PATH is not a right file. (-h for help)"
        exit 1
    fi

    _file_path="$_FILE_PATH"
    if [ -n "$_START_DATE" ]; then
        echo "# Extracting $_START_DATE $_END_DATE into a temp file ..." >&2
        f_extractByDates "$_FILE_PATH" "$_START_DATE" "$_END_DATE" > /tmp/_f_extractByDates_$$.out
        _file_path="/tmp/_f_extractByDates_$$.out"
    fi
    echo "# Running f_topErrors $_file_path ..." >&2
    f_topErrors "$_file_path" > /tmp/_f_topErrors_$$.out &
    echo "# Running f_topCausedByExceptions $_file_path ..." >&2
    f_topCausedByExceptions "$_file_path" > /tmp/_f_topCausedByExceptions_$$.out &
    if [ "$_LOG_TYPE" != "ya" ]; then
        echo "# Running f_hdfsAuditLogCountPerTime $_file_path ..." >&2
        f_hdfsAuditLogCountPerTime "$_file_path" > /tmp/_f_hdfsAuditLogCountPerTime_$$.out &
    fi
    wait

    echo "" >&2
    echo "============================================================================" >&2
    echo "# f_topErrors (top 40)"
    cat /tmp/_f_topErrors_$$.out | tail -n 40
    echo ""
    echo "# f_topCausedByExceptions (top 40)"
    cat /tmp/_f_topCausedByExceptions_$$.out | tail -n 40
    echo ""
    if [ "$_LOG_TYPE" != "ya" ]; then
        echo "# f_hdfsAuditLogCountPerTime (last 48 lines)"
        cat /tmp/_f_hdfsAuditLogCountPerTime_$$.out | tail -n 48
        echo ""
    fi

    # if app log, run f_appLogxxxxx
    if [ "$_LOG_TYPE" = "ya" ]; then
        echo "# f_appLogContainersAndHosts"
        f_appLogContainersAndHosts "$_file_path" "Y"
        echo ""
        echo "# f_appLogJobCounters"
        f_appLogJobCounters "$_file_path" > /tmp/f_appLogJobCounters_$$.out
        echo "# Saved in /tmp/f_appLogJobCounters_$$.out"
        _grep -i fail /tmp/f_appLogJobCounters_$$.out | _grep -v '=0'
        echo ""
    fi
fi