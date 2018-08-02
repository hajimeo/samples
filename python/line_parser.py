#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# line_parser.py func_name [args] < some_file.txt
#

import sys, re

_PREV_COUNTER = 0
_PREV_LABEL = ""

# All functions need to use "lp_" prefix
def lp_thread_num(line):
    global _PREV_COUNTER
    global _PREV_LABEL

    if len(line) > 0:
        (label, start_line_num) = line.strip().split(" ", 2)
    else:
        label = ""
        start_line_num = sys.argv[2]

    if _PREV_COUNTER > 0:
        print "%s %s" % (_PREV_LABEL, (int(start_line_num) - _PREV_COUNTER))
    _PREV_LABEL = label
    _PREV_COUNTER = int(start_line_num)


if __name__ == '__main__':
    func_name = sys.argv[1]

    for line in sys.stdin:
        globals()['lp_'+func_name](line)

    # Some function needs to be called with empty line
    globals()['lp_'+func_name]("")

