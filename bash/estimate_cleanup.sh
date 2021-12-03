#!/bin/sh
# NOT completed yet.
#
# NOTE: JAVA_OPTS to set -Xmx etc.
#       "date -d" does not work with Mac (replace with gdate).
# TODO: append https://github.com/hajimeo/samples/raw/master/misc/orient-console.jar
_WHERE=""
while getopts "r:u:d:" opts; do
    case $opts in
        r)
            [ -n "${_WHERE}" ] && _WHERE="${_WHERE} AND "
            _WHERE="${_WHERE:-"WHERE"} bucket.repository_name = '$OPTARG'"
            ;;
        u)
            [ -n "${_WHERE}" ] && _WHERE="${_WHERE} AND "
            _WHERE="${_WHERE:-"WHERE"} blob_updated <= '$(date +"%Y-%m-%d" -d "$OPTARG days ago")"
            ;;
        d)
            [ -n "${_WHERE}" ] && _WHERE="${_WHERE} AND "
            _WHERE="${_WHERE:-"WHERE"} last_downloaded <= '$(date +"%Y-%m-%d" -d "$OPTARG days ago")"
            ;;
    esac
done
_QUERY="SELECT bucket.repository_name as r, count(*) as asset_count, sum(size) as asset_size FROM asset ${_WHERE} GROUP BY bucket"
echo "${_QUERY}" | java ${JAVA_OPTS} -jar $0 "$@" 2>/tmp/estimate_cleanup.err