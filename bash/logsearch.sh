#!/usr/bin/env bash
#
# Naming rules:
#   Environment variable = CAPITAL
#   Global variable = _CAPITAL
#   Local variable = _small
#   Function (except main) = f_someFunction

function f_usage {
    local _script_name="`basename $BASH_SOURCE`"

    echo "How To:
    $_script_name -i [integer: interval] -m [string: emails, comma separated]
    "
}


# NOTE: "^100$ is because mongo client outputs this when this script sets shellBatchSize
_EXCLUDE_REGEX='(^100$|Attempt has been made to access an admin only|APIException - type:)'
_SAVE_DIR="/tmp"

# main function uses $1 as emails (comma delimiter)
#_EMAILS="hajime.osako@ladbrokes.com.au,t.leventis@bookmaker.com.au"
_EMAILS=""
_INTERVAL="20"

_MONGO_BIN="/usr/local/bin/mongo"
_MONGO_USER="loguser"
_MONGO_CONSTR="10.37.1.155/logsearch"
_MONGO_LIMIT="100"

function f_echoErrorSearchQuery {
    local _mongo_interval="${1-5}"
    local _mongo_limit="${2-100}"

    local _mongo_filter='{service:"api",priority:{$lte: 2},date:{$gte: new Date(new Date().setMinutes(new Date().getMinutes()-'${_mongo_interval}'))}}'
    local _mongo_fields="{_id:1,date:1,preview:1}"

    echo 'DBQuery.shellBatchSize='$_mongo_limit';
    var results={};
    db.log_entries.find('$_mongo_filter','$_mongo_fields').limit('$_mongo_limit').forEach(
        function(d) {
            if(results[d.preview] == undefined) {
                results[d.preview] = {};
                results[d.preview]["count"]=1;
                results[d.preview]["preview"]=d.preview;
                results[d.preview]["date_from"]=d.date;
                results[d.preview]["date_to"]=null;
                results[d.preview]["id_from"]=d._id;
            }
            else {
                results[d.preview]["count"]++;
                results[d.preview]["date_to"]=d.date;
                results[d.preview]["id_to"]=d._id;
            }
        }
    );
    for (var k in results) {
        printjsononeline(results[k]);
    };'
#        print(results[k].count+"    "+results[k].preview+"    "+results[k].preview+"    "+results[k].date_from+" - "+results[k].date_to+"    "+results[k].id_from+" - "+results[k].id_to+";");
}

function f_echoDocQuery {
    local _doc_id="$1"

    local _mongo_filter='{_id:"'$_doc_id'"}'
    local _mongo_fields="{_id:1,date:1,preview:1,has_data:1,has_trace:1}"

    echo 'db.log_entries.find('$_mongo_filter','$_mongo_fields').limit(1).forEach(
    function (e) {
        print("=== "+ e._id+" =======");
        printjson(e);
        i = db.log_info.findOne({_id: e._id});
        printjson(i);
        o = db.log_outputs.findOne({_id: e._id});
        printjson(o);
        if(e.has_data) {
            d = db.log_data.findOne({_id: e._id});
            printjson(d);
        }
        if(e.has_trace) {
            t = db.log_trace.findOne({_id: e._id});
            printjson(t);
        }
    });'
}

function f_queryMongo {
    local _user="$1"
    local _pass="$2"
    local _query="$3"

    if [ -z "$_MONGO_BIN" ] || [ ! -x $_MONGO_BIN ]
    then
        _MONGO_BIN="`which mongo`"
    fi

    if [ -z "$_MONGO_BIN" ] || [ ! -x $_MONGO_BIN ]
    then
        return 1
    fi

    $_MONGO_BIN --quiet -u $_user -p $_pass $_MONGO_CONSTR --eval "$_query"
}

function f_formatErrors {
    local _errors="$1"
    #echo -e "$_errors" | grep -vE "$_EXCLUDE_REGEX" | grep -oE '"preview" : ".+?"' | sort | uniq -c | sort -nr | head -n5
    echo "$_errors" | grep -E '^\{' | grep -vE "$_EXCLUDE_REGEX" | sort -nr | head -n5
}

function f_email {
    local _send_to="$1"
    local _subject="$2"
    local _message="$3"
    #local _send_from="$4"
    #if [ -n "$_send_from" ]; then
    #    _send_from="-a \"From: ${_send_from}\""
    #fi

    # Mac doesn't work with HTML mail
    #echo -e "$_mail_body" | mail $_send_from -a "MIME-Version: 1.0" -a "Content-Type: text/html" -s "${_subject}" $_send_to
    echo -e "$_message" | mail -s "$_subject" $_send_to
    return $?
}

function f_split() {
    local _rtn_var_name="$1"
    local _string="$2"
    local _delimiter="${3-,}"
    local _original_IFS="$IFS"
    eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
    IFS="$_original_IFS"
}

function main {
    local _emails_str="$_EMAILS"
    local _interval="$_INTERVAL"
    local _password="$MGPASSWORD"
    local _suffix="`date +"%H%M"`"
    local _script_name=`basename $BASH_SOURCE`

    if [ -z "$_password" ]
    then
        read -p "MongoDB password: " -s "_password"; echo ""
        MGPASSWORD="$_password"
        export MGPASSWORD
    fi
    # If still empty, assume as an empty password...

    if [ -n "$_DOC_ID" ]
    then
        local _query="`f_echoDocQuery "$_DOC_ID"`"
        local _output="`f_queryMongo "$_MONGO_USER" "$_password" "$_query"`"
        echo -e "$_output"
        return 0
    fi

    local _query="`f_echoErrorSearchQuery "$_interval" "$_MONGO_LIMIT"`"
    local _output="`f_queryMongo "$_MONGO_USER" "$_password" "$_query"`"
    _output="`f_formatErrors "$_output" | tee ${_SAVE_DIR%/}/${_script_name}.${_suffix}.out`"
    
    if [ -n "$_output" ]
    then
        if [ -n "$_emails_str" ]
        then
            local _emails
            f_split "_emails" "$_emails_str"
            for _e in "${_emails[@]}"
            do
                echo "Sending e-mail to $_e ..."
                f_email "$_e" "Log Search Result" "${_output}"
            done
        fi
        echo -e "$_output"
    fi
}

if [ "$0" = "$BASH_SOURCE" ]; then
    while getopts "m:i:d:h" opts; do
        case $opts in
            m)
                _EMAILS="$OPTARG"
                ;;
            i)
                _INTERVAL="$OPTARG"
                ;;
            d)
                _DOC_ID="$OPTARG"
                ;;
            h)
                f_usage | less
                exit 0
        esac
    done

    main
fi

