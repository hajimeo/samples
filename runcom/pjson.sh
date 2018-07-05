#!/usr/bin/env bash
# ln -s ~/IdeaProjects/samples/runcom/pjson.sh /usr/local/bin/pjson
#python -m json.tool <&0
_max_length="${1:-1000}"
python -c 'import sys,json,encodings.idna
for l in sys.stdin:
    l2=l.strip().lstrip("[").rstrip(",]")[:'${_max_length}']
    try:
        jo=json.loads(l2)
        print json.dumps(jo, indent=4)
    except ValueError:
        print l2'