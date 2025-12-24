#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys

source_file = sys.argv[1]
if len(sys.argv) > 2:
    output_dir = sys.argv[2]
else:
    output_dir = '.'
if len(sys.argv) > 3:
    prefix = sys.argv[3]
else:
    prefix = 'thread_'

# Open your source file, which is first command line argument
with open(source_file, 'r', encoding='utf-8') as f:
    # Read the content and split by the double newline
    # Use '\n\n\n' if there are literally two empty lines between text
    content = f.read()
    parts = content.split('\n\n\n')

# Create a folder for the chunks
os.makedirs(output_dir, exist_ok=True)

for i, part in enumerate(parts):
    with open(f'{output_dir}/{prefix}{i+1}.txt', 'w', encoding='utf-8') as out:
        out.write(part.strip())