#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Generic python script to parse the log lines with the function (1st argument), to use the result for gantt chart.
# TODO: tooooooo messy and complicated. Should be refactored
#   curl -O https://raw.githubusercontent.com/hajimeo/samples/master/python/line_parser.py
#   line_parser.py func_name_without_lb_ [extra args] < some_file.txt
#
# Process the stdin with lp_thread_num, which accept an extra argument as 'start_line_num'.
#   echo 'YYYY-MM-DDThh:mm:ss,sss current_line_num' | line_parser.py thread_num ${_last_line_num} | bar_chart.py -A
# Process the stdin with lp_time_diff, which accept two extra arguments as 'starting_message' and 'split_num'.
#   echo 'YYYY-MM-DD hh:mm:ss,sss some_log_text' | line_parser.py time_diff
#
# NOTE: All *actual* function names need to start with "lp_" , and use the with/without 'lb_' function name as the 1st arg
# NOTE: Do not forget to insert column headers in the csv. Eg: start_datetime,end_datetime,elapsed,message,thread
#
# More complex Examples: measuring AWS (PUT) request (expecting some_task.log is Single thread):
#   rg '^(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d.\d\d\d).+com.amazonaws.request - (Sending Request: [^ ]+|Received)' ./log/tasks/some_task.log -o -r '$1 $2 $3' | line_parser.py time_diff "Sending" > time_diff.csv
#   rg '^(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d.\d\d\d)[^ ]+ [^ ]+ +\[([^\]]+)\].+ com.amazonaws.request - (Sending Request: [^ ]+|Received)' -o -r '$1 $2 $3 $4' --no-filename --sort=path -g nexus.log | line_parser.py time_diff "Sending" 3 > time_diff.csv
#   rg '^(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d.\d\d\d)[^ ]+ [^ ]+ +\[([^\]]+)\].+ org.apache.http.impl.conn.PoolingHttpClientConnectionManager - (Connection request:.+|Connection released:.+)' -o -r '$1 $2 $3 $4' ./log/nexus.log | line_parser.py time_diff "Connection request" 3 > time_diff.csv
#   rg '^(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d.\d\d\d)[^ ]+ [^ ]+ +\[([^\]]+)\].+ org.apache.http.impl.conn.PoolingHttpClientConnectionManager - (Connection leased:.+|Connection released:.+)' -o -r '$1 $2 $3 $4' ./log/nexus.log | line_parser.py time_diff "Connection leased" 3 > leased_released_diff.csv
#

import sys, re, dateutil.parser
from datetime import datetime

_PREV_VALUE = _PREV_LABEL = _PREV_MSG = None


def lp_thread_num(line):
    """
    Read thread dumps generated from Scala and print the line number of <label>
    Expected line format: YYYY-MM-DDThh:mm:ss,sss current_line_num
    NOTE: This method reads sys.argv[2] for the start_line_num
    :param line: String - currently reading line
    :return: void
    """
    global _PREV_VALUE
    global _PREV_LABEL

    if len(line) > 0:
        (label, start_line_num) = line.strip().split(" ", 2)
    else:
        label = ""
        start_line_num = sys.argv[2]  # this is the last line number (wc -l)

    if _PREV_VALUE > 0:
        print("\"%s\",%s" % (_PREV_LABEL, (int(start_line_num) - int(_PREV_VALUE))))
    _PREV_LABEL = label
    _PREV_VALUE = int(start_line_num)


def lp_time_diff(line):
    """
    Read log files and print the time difference between *previous* line in Milliseconds
    Expected line format: ^YYYY-MM-DD hh:mm:ss,sss some_text (space between date and time)
    NOTE: This method reads sys.argv[2] for specifying starting message string
    NOTE: This method reads sys.argv[3] for max split number = count of space character
    :param line: String - current reading line
    :return: void
    """
    global _PREV_VALUE
    global _PREV_LABEL
    global _PREV_MSG

    # initialising
    if bool(_PREV_VALUE) is False:
        _PREV_VALUE = {}
    if bool(_PREV_LABEL) is False:
        _PREV_LABEL = {}
    if bool(_PREV_MSG) is False:
        _PREV_MSG = {}

    if bool(line) is False:
        return
    # sys.stderr.write(line+"\n")
    # False works when *current* line's col[2] contains good message.
    starting_message = ""
    if (len(sys.argv) > 2) and bool(sys.argv[2]):
        starting_message = sys.argv[2]
    # False works when *current* line's col[2] contains good message.
    split_num = 2
    if (len(sys.argv) > 3) and bool(sys.argv[3]):
        split_num = int(sys.argv[3])
    # "date time value" or "date time thread value"
    cols = line.strip().split(" ", split_num)
    if len(cols) < 2:
        return

    # Ignoring timezone
    crt_date_time = cols[0] + " " + cols[1]
    crt_date_time = crt_date_time.split("+")[0].replace(',', '.')  # removing timezone "+\d\d\d\d" and replacing , to . for SQLite
    # sys.stderr.write(str(label)+"\n")
    dt_obj = datetime.strptime(crt_date_time, '%Y-%m-%d %H:%M:%S.%f')
    timestamp_in_ms = int(dt_obj.timestamp() * 1000)
    # sys.stderr.write(str(_PREV_VALUE)+"\n")
    # sys.stderr.write(str(current_timestamp_in_ms)+"\n")
    if len(cols) > 3:
        message = cols[3]
        thread = cols[2]
    else:
        message = cols[2]
        thread = "none"

    if thread in _PREV_VALUE and bool(_PREV_VALUE[thread]):
        _prev_value = _PREV_VALUE[thread]
        _prev_label = ""
        if thread in _PREV_LABEL and bool(_PREV_LABEL[thread]):
            _prev_label = _PREV_LABEL[thread]
        _final_message = None
        if thread in _PREV_LABEL and bool(_PREV_MSG[thread]) and bool(starting_message):
            if _PREV_MSG[thread].startswith(starting_message):
                _final_message = _PREV_MSG[thread].replace('"', '\\"')
        else:
            _final_message = message.replace('"', '\\"')

        if _final_message is not None:
            # TODO: should use split_num
            if len(cols) > 3:
                # should escape double-quotes on cols[2]
                print("\"%s\",\"%s\",%s,\"%s\",\"%s\"" % (
                _prev_label, crt_date_time, (timestamp_in_ms - _prev_value), _final_message, thread))
            elif len(cols) > 2:
                # should escape double-quotes on cols[2]
                print("\"%s\",\"%s\",%s,\"%s\"" % (
                _prev_label, crt_date_time, (timestamp_in_ms - _prev_value), _final_message))
            else:
                print("\"%s\",\"%s\",%s" % (_prev_label, crt_date_time, (timestamp_in_ms - _prev_value)))
    if (bool(starting_message) and thread not in _PREV_LABEL and message.startswith(starting_message)) or bool(starting_message) is False or thread in _PREV_LABEL:
        _PREV_LABEL[thread] = crt_date_time
        _PREV_VALUE[thread] = timestamp_in_ms
        _PREV_MSG[thread] = message

if __name__ == '__main__':
    func_name = sys.argv[1]
    if func_name.startswith('lp_') is False:
        func_name = 'lp_' + func_name

    for line in sys.stdin:
        globals()[func_name](line)

    # Some function needs to be called with empty line
    globals()[func_name]("")
