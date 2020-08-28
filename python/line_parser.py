#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# line_parser.py func_name_without_lb_ [args] < some_file.txt
# echo 'YYYY-MM-DDThh:mm:ss,sss current_line_num' | line_parser.py thread_num ${_last_line_num} | bar_chart.py -A
# echo 'YYYY-MM-DD hh:mm:ss,sss some_log_text' | line_parser.py time_diff
# rg '^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d.\d\d\d).+ (some log msg.+)' -o -r '$1 $2' some_file.log | line_parser.py time_diff > time_diff.csv
#
# All functions need to use "lp_" prefix
# TODO: should be a class
#

import sys,dateutil.parser
from datetime import datetime

_PREV_VALUE = ""
_PREV_LABEL = ""

def lp_thread_num(line):
    """
    Read thread dumps generated from Scala and print the line number of <label>
    Expected line format: YYYY-MM-DDThh:mm:ss,sss current_line_num
    :param line: String - currently reading line
    :return: void
    """
    global _PREV_VALUE
    global _PREV_LABEL

    if len(line) > 0:
        (label, start_line_num) = line.strip().split(" ", 2)
    else:
        label = ""
        start_line_num = sys.argv[2]    # this is the last line number (wc -l)

    if _PREV_VALUE > 0:
        print("\"%s\",%s" % (_PREV_LABEL, (int(start_line_num) - int(_PREV_VALUE))))
    _PREV_LABEL = label
    _PREV_VALUE = int(start_line_num)

def lp_time_diff(line):
    """
    Read log files and print the time difference between previous line in Milliseconds
    Expected line format: ^YYYY-MM-DD hh:mm:ss,sss some_text (space between date and time)
    :param line: String - current reading line
    :return: void
    """
    global _PREV_VALUE
    global _PREV_LABEL

    if bool(line) is False:
        return
    #sys.stderr.write(line+"\n")
    cols = line.strip().split(" ", 2)   # maxsplit 2 means cols length is 3...
    if len(cols) < 2:
        return
    # Ignoring timezone
    label = cols[0]+" "+cols[1]
    label = label.split("+")[0] # removing "+\d\d\d\d"
    #sys.stderr.write(str(label)+"\n")
    dt_obj = datetime.strptime(label, '%Y-%m-%d %H:%M:%S,%f')
    current_timestamp_in_ms = int(dt_obj.timestamp() * 1000)
    #sys.stderr.write(str(_PREV_VALUE)+"\n")
    #sys.stderr.write(str(current_timestamp_in_ms)+"\n")

    if bool(_PREV_VALUE):
        if len(cols) > 2:
            # TODO: cols[2] should escape doublequotes
            print("\"%s\",%s,\"%s\"" % (label, (current_timestamp_in_ms - int(_PREV_VALUE)), cols[2].replace('"', '\\"')))
        else:
            print("\"%s\",%s" % (label, (current_timestamp_in_ms - int(_PREV_VALUE))))
    _PREV_LABEL = label
    _PREV_VALUE = current_timestamp_in_ms

if __name__ == '__main__':
    func_name = sys.argv[1]

    for line in sys.stdin:
        globals()['lp_'+func_name](line)

    # Some function needs to be called with empty line
    globals()['lp_'+func_name]("")

