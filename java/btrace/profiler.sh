#!/usr/bin/env bash
usage() {
    cat <<EOF
Purpose:
    Monitor specific class and output the metrics (nanoseconds)

Usage example:
    export JAVA_HOME="\$(/usr/libexec/java_home -v 1.8)"
    $0 -p "PID" -c "CLASS_PTN" -i "INTERVAL" | tee profiler.out

    -p  PID of the profiling process
    -c  Monitoring Class pattern (default: '/org\.apache\.http\..*/')
    -i  Interval of the result output in Milliseconds (default: 10000)

Download the latest script:
    curl -OL https://github.com/hajimeo/samples/raw/master/java/btrace/profiler.sh
EOF
}

function genScript() {
    local _cls_ptn="${1:-"/org\\.apache\\.http\\..*/"}"
    local _timing_ptn="${2:-"10000"}"
    cat <<EOF >/tmp/profiler.java
import org.openjdk.btrace.core.Profiler;
import org.openjdk.btrace.core.BTraceUtils;
import org.openjdk.btrace.core.annotations.BTrace;
import org.openjdk.btrace.core.annotations.Duration;
import org.openjdk.btrace.core.annotations.Kind;
import org.openjdk.btrace.core.annotations.Location;
import org.openjdk.btrace.core.annotations.OnMethod;
import org.openjdk.btrace.core.annotations.OnTimer;
import org.openjdk.btrace.core.annotations.ProbeMethodName;
import org.openjdk.btrace.core.annotations.Property;
import static org.openjdk.btrace.core.BTraceUtils.*;
@BTrace
class Profiling {
    @Property
    Profiler p = BTraceUtils.Profiling.newProfiler();
    @OnMethod(clazz="$(echo "${_cls_ptn}" | sed 's/\\/\\\\/g')", method="/.*/")
    void entry(@ProbeMethodName(fqn = true) String probeMethod) {
        BTraceUtils.Profiling.recordEntry(p, probeMethod);
    }
    @OnMethod(clazz="$(echo "${_cls_ptn}" | sed 's/\\/\\\\/g')", method="/.*/", location=@Location(value=Kind.RETURN))
    void exit(@ProbeMethodName(fqn = true) String probeMethod, @Duration long duration) {
        BTraceUtils.Profiling.recordExit(p, probeMethod, duration);
    }
    @OnTimer(${_timing_ptn})
    void timer() {
        BTraceUtils.Profiling.printSnapshot("# [" + Time.timestamp("yyyy-MM-dd hh:mm:ss") + "] performance profile", p);
    }
}
EOF
}

main() {
    if [ ! -d "${JAVA_HOME%/}" ]; then
        echo "Please set|export JAVA_HOME before running this script"
        return 1
    fi
    if [ -z "$BTRACE_HOME" ]; then
        BTRACE_HOME="$(dirname "$0")"
    fi
    if [ ! -d "${BTRACE_HOME%/}/libs" ]; then
        mkdir -v -p "${BTRACE_HOME%/}/libs" || return $?
    fi
    [ -f "${BTRACE_HOME%/}/libs/btrace-client.jar" ] || curl -sfo ${BTRACE_HOME%/}/libs/btrace-client.jar -L https://raw.githubusercontent.com/hajimeo/samples/master/java/btrace/btrace-client.jar
    [ -f "${BTRACE_HOME%/}/libs/btrace-agent.jar" ] || curl -sfo ${BTRACE_HOME%/}/libs/btrace-agent.jar -L https://raw.githubusercontent.com/hajimeo/samples/master/java/btrace/btrace-agent.jar
    [ -f "${BTRACE_HOME%/}/libs/btrace-boot.jar" ] || curl -sfo ${BTRACE_HOME%/}/libs/btrace-boot.jar -L https://raw.githubusercontent.com/hajimeo/samples/master/java/btrace/btrace-boot.jar
    if [ ! -s "${BTRACE_HOME}/libs/btrace-client.jar" ]; then
        echo "Please make sure ${BTRACE_HOME}/libs/ is writable."
        return 1
    fi

    local _java_args="-XX:+IgnoreUnrecognizedVMOptions"
    if [ -d "${JAVA_HOME}/jmods" ]; then
        _java_args="$_java_args -XX:+AllowRedefinitionToAddDeleteMethods"
        _java_args="$_java_args --add-exports jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED"
    fi

    local _tools_jar="$JAVA_HOME/lib/tools.jar"
    if [ ! -f "$_tools_jar" ]; then
        _tools_jar="$JAVA_HOME/../lib/tools.jar"
    fi

    if [ ! -f "${_tools_jar}" ] && [ ! -d "${JAVA_HOME}/jmods" ]; then
        case "$(uname)" in
        Darwin*)
            _tools_jar="/System/Library/Frameworks/JavaVM.framework/Versions/${JAVA_VERSION:-"Current"}/Classes/classes.jar"
            if [ ! -f "${_tools_jar}" ]; then
                _tools_jar="${JAVA_HOME}/../Classes/classes.jar"
            fi
            if [ ! -f "${_tools_jar}" ]; then
                echo "Please set JAVA_VERSION to the target java version"
                return 1
            fi
            ;;
        esac
    fi
    if [ ! -f "${_tools_jar}" ] && [ ! -d "${JAVA_HOME}/jmods" ]; then
        # in non-jigsaw world _tools_jar must point to a valid file
        echo "Unable to locate tools.jar. Please, make sure JAVA_HOME points to a valid JDK installation"
        return 1
    fi

    genScript "$CLASS_PTN" "$INTERVAL" || return $?
    ${JAVA_HOME}/bin/java ${_java_args} -cp ${BTRACE_HOME}/libs/btrace-client.jar:${_tools_jar}:/usr/share/lib/java/dtrace.jar org.openjdk.btrace.client.Main $PID /tmp/profiler.java
}

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
    if [ "$#" -eq 0 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
        usage
        exit 0
    fi

    while getopts "p:c:i:" opts; do
        case $opts in
        p)
            [ -n "$OPTARG" ] && PID="$OPTARG"
            ;;
        c)
            [ -n "$OPTARG" ] && CLASS_PTN="$OPTARG"
            ;;
        i)
            [ -n "$OPTARG" ] && INTERVAL="$OPTARG"
            ;;
        *)
            echo "$opts $OPTARG is not supported. Ignored." >&2
            ;;
        esac
    done

    main #"$@"
fi