#/bin/env bash
# "$1" is the port number to find a PID to profile
# "$2" is the duration seconds
#

function f_profile() {
    local _port="${1}"      # To find a PID
    local _secs="${2:-60}"  # Duration seconds
    local _dump_path="${3}"

    local _p=`lsof -ti:${_port} -s TCP:LISTEN`
    if [ -z "${_p}" ]; then
        echo "Nothing running on port ${_port}"
        return 11
    fi
    [ -z "${_dump_path}" ] && _dump_path="/tmp/profile_${_p}.jfr"

    local _user="`stat -c '%U' /proc/${_p}`"
    local _dir="$(dirname `readlink /proc/${_p}/exe` 2>/dev/null)"
    if [ "${_user}" != "$USER" ]; then
        sudo -u ${_user} $(dirname $_dir)/bin/jcmd ${_p} JFR.start settings=profile duration=${_secs}s filename="${_dump_path}"
    else
        $(dirname $_dir)/bin/jcmd ${_p} JFR.start settings=profile duration=${_secs}s filename="${_dump_path}"
    fi
}
f_profile $1 $2|| exit $?

# Type some commands to test below:
#curl -v -f "http://$(hostname -f)/"
