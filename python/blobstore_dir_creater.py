#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# To create dummy blob store directories from db_blobs.json file.
# Then use the OS's tree command to output the hierarchy.

import json
import sys
import os
import html

startDir = "./blobs_abs"
blobDir = "./blobs_rel"
data = []
# Check if the first command-line argument is the path to a JSON file.
if len(sys.argv) > 1 and sys.argv[1].endswith(".json"):
    # Read the JSON file and store the contents in a variable.
    with open(sys.argv[1], "r") as f:
        data = json.load(f)
if len(sys.argv) > 2:
    startDir = sys.argv[2]
if len(sys.argv) > 3:
    blobDir = sys.argv[3]

for bs in data:
    try:
        path = bs['attributes']['file']['path']
        name = html.escape(bs['name'])
        if path.startswith("/"):
            path = f"{startDir}{path} ({name})"
        else:
            path = f"{blobDir}/{path} ({name})"
        print(f"creating '{path}' ...")
        os.makedirs(path)
    except:
        print(f"{bs['name']} may not have 'path' or not 'file' type")
