#!/usr/bin/env bash
#
# Bunch of grep functions to search log files
# Don't use complex so that easily copy and paste
#
# TODO: tested on Mac only (eg: sed -E)
#

usage() {
    echo "HELP/USAGE:"
    echo "This script contains useful functions to search log files.

How to use (just source)
    . ${BASH_SOURCE}

"
    echo "Available functions:"
    list
}
### Public functions ###################################################################################################

function f_topCausedByExceptions() {
    local __doc__="List Caused By xxxxException"
    local _path="$1"
    local _is_shorter="$2"
    local _regex="Caused by.+Exception"

    if [[ "$_is_shorter" =~ (^y|^Y) ]]; then
        _regex="Caused by.+?Exception"
    fi
    egrep -wo "$_regex" "$_path" | sort | uniq -c | sort
}

function f_topErrors() {
    local __doc__="List ERRORs"
    local _path="$1"
    local _is_including_warn="$2"
    local _regex="(ERROR|SEVERE|FATAL).+"
    local _num_regex="s/[1-9][0-9][0-9][0-9]+/_____/g"

    if [[ "$_is_including_warn" =~ (^y|^Y) ]]; then
        _regex="(ERROR|SEVERE|FATAL|WARN).+"
        _num_regex="s/[0-9]/_/g"
    fi

    egrep -wo "$_regex" "$_path" | sed -E "$_num_regex" | sort | uniq -c | sort
}

function f_errorsAt() {
    local __doc__="List ERROR times"
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

function f_appLogContainers() {
    local __doc__="List containers ID and host (from YARN app log)"
    local _path="$1"
    local _is_including_Loginfo="$2"

    if [[ "$_is_including_warn" =~ (^y|^Y) ]]; then
        egrep "(^Container: container_|^LogType:|^Log Upload Time:^LogLength:)" "$_path"
    else
        grep "^Container: container_" "$_path" | sort
    fi
}

function f_appLogCounters() {
    local __doc__="List counters (Tez only?) (from YARN app log)"
    local _path="$1"
    local _line=""
    local _list=""
    local _final_containers=""

    egrep -o "Final Counters for .+$" "$_path" | while read -r _line ; do
        echo $_line | egrep -o "Final Counters for .+?:"
        _list="`echo $_line | egrep -o "\[.+$"`"

        echo $_list | python -c "import sys,pprint;pprint.pprint(sys.stdin.read());"
    done
}

function f_appLogExports() {
    local __doc__="List exports (from YARN app log)"
    local _path="$1"
    local _regex="^export "

    egrep "$_regex" "$_path" | sort | uniq -c
}

function f_longGC() {
    local __doc__="List long GC (real >= 1)"
    local _path="$1"
    local _regex=", real=[1-9]"

    egrep "$_regex" "$_path"
}

function f_xmlDiff() {
    local __doc__="Convert Hadoop xxxx-site.xml to (close to) Json. xmllint is required"
    local _path1="$1"
    local _path2="$2"

    #echo "cat /configuration/property/name/text()|/configuration/property/value/text()" | xmllint --shell $_path
    diff -w <(paste <(ggrep -Pzo '<name>.+?<\/name>' $_path1) <(ggrep -Pzo '<value>.+?<\/value>' $_path1) | sort) <(paste <(ggrep -Pzo '<name>.+?<\/name>' $_path2) <(ggrep -Pzo '<value>.+?<\/value>' $_path2) | sort)
}

# TODO: find hostname and container, splits, actual query (mr?) etc from app log

function f_grepWithDate() {
    local __doc__="Grep large file with date string"
	local _date_format="$1"
	local _log_file_path="$2"
	local _grep_option="$3"
	local _is_utc="$4"
	local _interval_hour="$5"
	local _date_regex=""
	local _date="date"

	if [ -z "$_interval_hour" ]; then
		_interval_hour=0
	fi

	# in case file path includes wildcard
	ls $_log_file_path &>/dev/null
	#if [ $? -ne 0 ]; then
		#return 3
	#fi

    if [[ "$_is_utc" =~ (^y|^Y) ]]; then
		_date="date -u"
	fi

	if [ ${_interval_hour} -gt 0 ]; then
		local _start_hour="`$_date +"%H" -d "${_interval_hour} hours ago"`"
		local _end_hour="`$_date +"%H"`"

		local _tmp_date_regex=""
		for _n in `seq 1 ${_interval_hour}`; do
			_tmp_date_regex="`$_date +"$_date_format" -d "${_n} hours ago"`"

			if [ -n "$_tmp_date_regex" ]; then
				if [ -z "$_date_regex" ]; then
					_date_regex="$_tmp_date_regex"
				else
					_date_regex="${_date_regex}|${_tmp_date_regex}"
				fi
			fi
		done
	else
		_date_regex="`$_date +"$_date_format"`"
	fi

	if [ -z "$_date_regex" ]; then
		return 2
	fi

	# If empty interval hour, do normal grep
	if [ -z "${_interval_hour}" ]; then
		eval "ggrep $_grep_option $_log_file_path"
	else
		eval "_getAfterFirstMatch \"$_date_regex\" \"$_log_file_path\" | ggrep $_grep_option"
	fi

	return $?
}

### Private functions ##################################################################################################

function _split() {
    local _rtn_var_name="$1"
    local _string="$2"
    local _delimiter="${3-,}"
    local _original_IFS="$IFS"
    eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
    IFS="$_original_IFS"
}

function _getAfterFirstMatch() {
	local _regex="$1"
	local _file_path="$2"

	ls $_file_path 2>/dev/null | while read l; do
		local _line_num=`ggrep -m1 -nP "$_regex" "$l" | cut -d ":" -f 1`
		if [ -n "$_line_num" ]; then
			sed -n "${_line_num},\$p" "${l}"
		fi
	done
	return $?
}

### Help ###############################################################################################################

list() {
    local _name="$1"
    #local _width=$(( $(tput cols) - 2 ))
    local _tmp_txt=""
    # TODO: restore to original posix value
    set -o posix

    if [[ -z "$_name" ]]; then
        (for _f in `typeset -F | ggrep -E '^declare -f [fp]_' | cut -d' ' -f3`; do
            #eval "echo \"--[ $_f ]\" | sed -e :a -e 's/^.\{1,${_width}\}$/&-/;ta'"
            _tmp_txt="`help "$_f" "Y"`"
            printf "%-28s%s\n" "$_f" "$_tmp_txt"
        done)
    elif [[ "$_name" =~ ^func ]]; then
        typeset -F | ggrep '^declare -f [fp]_' | cut -d' ' -f3
    elif [[ "$_name" =~ ^glob ]]; then
        set | ggrep ^[g]_
    elif [[ "$_name" =~ ^resp ]]; then
        set | ggrep ^[r]_
    fi
}
help() {
    local _function_name="$1"
    local _doc_only="$2"

    if [ -z "$_function_name" ]; then
        echo "help <function name>"
        echo ""
        list "func"
        echo ""
        return
    fi

    if [[ "$_function_name" =~ ^[fp]_ ]]; then
        local _code="$(type $_function_name 2>/dev/null | ggrep -v "^${_function_name} is a function")"
        if [ -z "$_code" ]; then
            _echo "Function name '$_function_name' does not exist."
            return 1
        fi

        local _eval="$(echo -e "${_code}" | awk '/__doc__=/,/;/')"
        eval "$_eval"

        if [ -z "$__doc__" ]; then
            echo "No help information in function name '$_function_name'."
        else
            echo -e "$__doc__"
        fi

        if [[ "$_doc_only" =~ (^y|^Y) ]]; then
            local _params="$(type $_function_name 2>/dev/null | ggrep -iP '^\s*local _[^_].*?=.*?\$\{?[1-9]' | ggrep -v awk)"
            if [ -n "$_params" ]; then
                echo "Parameters:"
                echo -e "$_params
                "
                echo ""
            fi
        fi
    else
        _echo "Unsupported Function name '$_function_name'."
        return 1
    fi
}

### Global variables ###################################################################################################
# TODO: Not using at this moment
_IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
_IP_RANGE_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(/[0-3]?[0-9])?$'
_HOSTNAME_REGEX='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
_URL_REGEX='(https?|ftp|file|svn)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
_TEST_REGEX='^\[.+\]$'

### Main ###############################################################################################################

if [ "$0" = "$BASH_SOURCE" ]; then
    usage
fi