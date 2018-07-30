#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os, fnmatch
import pandas as pd

_LAST_FILE_LIST = []  # for debug


# As Python 2.7's glob does not have recursive option
def globr(ptn='*', src='./'):
    matches = []
    for root, dirnames, filenames in os.walk(src):
        # os walk doesn't sort and almost random
        for filename in fnmatch.filter(sorted(filenames), ptn):
            matches.append(os.path.join(root, filename))
    return matches


def load_jsons(src="./"):
    """
    Find json files from current path and load as pandas dataframes object
    :return: dict contains Pandas dataframes object
    """
    global _LAST_FILE_LIST
    names_dict = {}
    dfs = {}

    _LAST_FILE_LIST = globr('*.json', src)
    for f_path in _LAST_FILE_LIST:
        f_1st_c = os.path.splitext(os.path.basename(f_path))[0][0]
        new_name = f_1st_c
        for i in range(0, 9):
            if i > 0:
                new_name = f_1st_c + str(i)
            if new_name in names_dict and names_dict[new_name] == f_path:
                # print "Found "+new_name+" for "+f_path
                break
            if new_name not in names_dict:
                # print "New name "+new_name+" hasn't been used for "+f_path
                break
        names_dict[new_name] = f_path
        dfs[new_name] = pd.read_json(f_path)
    return (dfs, names_dict)
