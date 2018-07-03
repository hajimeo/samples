alias cdl='cd "`ls -dtr ./*/ | tail -n 1`"'
alias urldecode='python -c "import sys, urllib as ul; print ul.unquote_plus(sys.argv[1])"'
alias urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1])"'
#alias int2utc='date -u -r'
# brew install coreutils
function int2utc() {
    gdate -u -d "1970/01/01 UTC $1 sec"
}
function utc2int() {
    if which php &>/dev/null; then
        php -r "echo strtotime($1).\"\n\";"
    else
        gdate -u '+%s' -d"$1"
    fi
}
