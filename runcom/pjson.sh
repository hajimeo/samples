#!/usr/bin/env bash
# ln -s ~/IdeaProjects/samples/runcom/pjson.sh /usr/local/bin/pjson
#python -m json.tool <&0
_max_length="${1:-1000}"
_sort_keys="False"
[[ "$2" =~ (y|Y) ]] && _sort_keys="True"
python -c 'import sys,json,encodings.idna
for l in sys.stdin:
    l2=l.strip().lstrip("[").rstrip(",]")[:'${_max_length}']
    try:
        jo=json.loads(l2)
        print json.dumps(jo, indent=4, sort_keys='${_sort_keys}')
    except ValueError:
        print l2'