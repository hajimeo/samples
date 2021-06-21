#!/bin/bash
# To monitor OS, DB, PHP logs for Ubuntu (would not work with FreeBSD's grep)
#
# @author Hajime
# $Id: log_mon.sh 15095 2014-02-07 00:16:15Z hajimeosako $
#

export TZ="Australia/Sydney"
CURRENT_DIR="$(dirname $BASH_SOURCE)"
SCRIPT_NAME="$(basename $BASH_SOURCE)"
LOCK_FILE="/tmp/${SCRIPT_NAME%/}.tmp"


### Functions
function _usage() {
	echo "This script is to monitor various Ubuntu log files. Would not work with FreeBSD.
	
	# To check logs for last 3 hours
	$SCRIPT_NAME -t 3
	
	# To check logs since last check
	$SCRIPT_NAME
"
}

function _getAfterFirstMatch() {
	local _regex="$1"
	local _file_path="$2"
	
	ls $_file_path 2>/dev/null | while read l; do
		local _line_num=`grep -m1 -nP "$_regex" "$l" | cut -d ":" -f 1`
		if [ -n "$_line_num" ]; then
			sed -n "${_line_num},\$p" "${l}"
		fi
	done
	return $?
}

function _grep_with_date() {
	local _date_format="$1"
	local _log_file_path="$2"
	local _grep_option="$3"
	local _is_utc="$4"
	local _interval_hour="${5-$r_interval_time}"
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
	
	if [ "$_is_utc" = "Y" ]; then
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
		eval "grep $_grep_option $_log_file_path"
	else
		eval "_getAfterFirstMatch \"$_date_regex\" \"$_log_file_path\" | grep $_grep_option"
	fi
	
	return $?
}

function _email() {
	local _send_to="$1"
	local _subject="$2"
	local _html_body="$3"
	local _send_from="$4"
	local _mail_body="<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">
<html>
<head><title>${_subject}</title>
</head>
<body>
${_html_body}
</body>
</html>"
	
	if [ -n "$_send_from" ]; then
		_send_from="-a \"From: ${_send_from}\""
	fi
	
	echo -e "$_mail_body" | mail $_send_from -a "MIME-Version: 1.0" -a "Content-Type: text/html" -s "${_subject}" $_send_to
	return $?
}

function _syslog_top5() {
	# Date format: Oct 29 02:40:01
	_grep_with_date "%b %e %H:" "/var/log/syslog" "-wiP '(error|fatal)'" | cut -c 17- | sort | uniq -c | sort -nr | head -n5
	return $?
}

function _maillog_top5() {
	# Date format: Oct 29 02:40:01
	_grep_with_date "%b %e %H:" "/var/log/mail.log" "-wiP '(error|fatal)'" | cut -c 17- | sort | uniq -c | sort -nr | head -n5
	return $?
}

function _phperror_top5() {
	# Date format: 28-Oct-2013 20:05:02 UTC
	# php -i | grep ^error_log
	local _file_path="/tmp/php_error.log /var/www/bookmaker/*/logs/error.log"
	_grep_with_date "%d-%b-%Y %H:" "$_file_path" "-oE 'PHP (Fatal|Warning|Parse).+$'" "Y" | sort | uniq -c | sort -nr | head -n5
	return $?
}

function _apperror_top5() {
	# Date format: 2014-05-12 11:07:33
	local _file_path="/var/www/bookmaker/*/logs/log-$(date +%Y-%m-%d).log"
	_grep_with_date "%Y-%m-%d %H:" "$_file_path" "-oE '(^ERROR|WARNING) - .+$'" "" | sed "s/ 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] -->//g" | grep -v 'WARNING - Cache:' | sed "s/[0-9][0-9][0-9][0-9][0-9][0-9]*/\*\*\*\*\*\*/g" | sort | uniq -c | sort -nr | head -n5
	return $?
}

if [ "$0" = "$BASH_SOURCE" ]; then
	cd $CURRENT_DIR

	#_tmp_func_path="./functions.sh"
	#if [ ! -s "$_tmp_func_path" ]; then
	#	echo "ERROR: This script requires functions.sh" 1>&2
	#	exit 1
	#fi

	if [ -e "$LOCK_FILE" ]; then
		_tmp_current_ts="`date '+%s'`"
		_tmp_last_check_ts="`stat -c "%Y" $LOCK_FILE`"
		
		if [ $_tmp_last_check_ts -gt $_tmp_current_ts ]; then
			r_interval_time=0
		else
			r_interval_time="$(( ($_tmp_current_ts - $_tmp_last_check_ts) / (60*60) ))"
			
			if [ $r_interval_time -lt 1 ]; then
				r_interval_time=0
			fi
		fi
	else
		r_interval_time=0
	fi
	
	while getopts "t:m:h" opts; do
		case $opts in
			"t")
				r_interval_time="$OPTARG"
				;;
			"m")
				r_mail_to="$OPTARG"
				;;
			"h")
				_usage
				exit 0
				;;
			"?")
				echo "Unknown option $OPTARG"
				_usage
				exit 1
				;;
			":")
				echo "No argument value for option $OPTARG"
				_usage
				exit 1
				;;
			*)
				# Should not occur
				echo "Unknown error while processing options"
				exit 1
				;;
		esac
	done
	
	#source $_tmp_func_path
	_over_all_rc=0
	cat /dev/null > $LOCK_FILE
	
	#echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] Checking Syslog"
	_tmp_out="`_syslog_top5`"
	if [ -n "$_tmp_out" ]; then
		echo "" >> $LOCK_FILE
		echo "# Top 5 errors in Syslog for past $r_interval_time hour(s)" >> $LOCK_FILE
		echo -e "$_tmp_out" >> $LOCK_FILE
		_over_all_rc=1
	fi

	#echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] Checking PHP Error Log"
	_tmp_out="`_phperror_top5`"
	if [ -n "$_tmp_out" ]; then
		echo "" >> $LOCK_FILE
		echo "# Top 5 fatal/parse in php error log for past $r_interval_time hour(s)" >> $LOCK_FILE
		echo -e "$_tmp_out" >> $LOCK_FILE
		_over_all_rc=1
	fi

	#echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] Checking App Error Log"
	_tmp_out="`_apperror_top5`"
	if [ -n "$_tmp_out" ]; then
		echo "" >> $LOCK_FILE
		echo "# Top 5 error/warning in API/Frontend log for past $r_interval_time hour(s)" >> $LOCK_FILE
		echo -e "$_tmp_out" >> $LOCK_FILE
		_over_all_rc=1
	fi

	#TODO: should send a HTML email?
	if [ $_over_all_rc -ne 0 ]; then
		_start_time="`date +"%H:00:00" -d "${r_interval_time} hours ago"`" >> $LOCK_FILE
		_end_time="`date +"%H:00:00"`" >> $LOCK_FILE
		echo "" >> $LOCK_FILE
		#top -bd1 | head -n12
		echo "( Time from $_start_time ; uptime:`uptime` )" >> $LOCK_FILE
	fi
	
	touch -d "`date +%H`:00:00" $LOCK_FILE

	_msg_body="`cat $LOCK_FILE`"

	if [ -z "$_msg_body" ]; then
		exit $_over_all_rc
	fi

	if [ -n "$r_mail_to" ]; then
		echo "Sending an e-mail to $r_mail_to ..."
		_email "$r_mail_to" "`hostname`: Erros for $r_interval_time hour" "<pre>$_msg_body</pre>"
	fi

	echo -e "$_msg_body"
	exit $_over_all_rc
fi

