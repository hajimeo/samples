#!/usr/bin/env bash
# DEMO: building simple NXRM3 resiliency
#
# TODO: Not commpleted and needs Usage example:


_CONT1_NAME="${1:-"nxrm3-res1"}"  # First NXRM3 container name
_CONT2_NAME="${2:-"nxrm3-res2"}"  # Second NXRM3 container name
_SHARE_DIR="${3:-"$HOME/share/dockers"}"    # Path for saving container data under this directory

# Please feel free to overwrite below by using "export <ENV NAME>=xxxxxxxxx"
: ${_NXRM3_IMAGENAME:="sonatype/nexus3:3.34.1"}
: ${_DB_USER:="nxrm3resiliency"}
: ${_DB_PWD:="${_DB_USER}123"}
: ${_DB_NAME:="${_DB_USER}"}
: ${_DB_HOST:="172.17.0.1"}

: ${_PG_IMAGENAME:="postgres:12.8"}
: ${_PG_CONT_NAME:="postgres-resiliency"}
: ${_PG_PWD:="admin123"}
: ${_PG_EXPOSE_PORT:="5432"}


# Create a PostgreSQL container if not exist, and create DB user and database.
function f_create_pg() {
    local _name="${1:-"${_PG_CONT_NAME}"}"
    local _image="${2:-"${_PG_IMAGENAME}"}"
    local _port="${3:-"${_PG_EXPOSE_PORT}"}"
    local _is_running="$(docker inspect -f '{{.State.Running}}' ${_name} 2>/dev/null)"
    if [ -n "${_is_running}" ]; then
        if [ "${_is_running}" == "false" ]; then
            echo "${_name} already exist but not running. exiting..."
            return 1
        fi
    else
        local _cmd="docker run -d --name ${_name} -p ${_port}:5432 -e POSTGRES_PASSWORD=\"${_PG_PWD}\""
        if [ -n "${_SHARE_DIR%/}" ]; then
            if [ ! -d "${_SHARE_DIR%/}/${_name%/}" ]; then
                mkdir -v -p -m 777 "${_SHARE_DIR%/}/${_name%/}" || return $?
            else
                chmod a+w "${_SHARE_DIR%/}" && chmod a+w "${_SHARE_DIR%/}/${_name%/}"
            fi
            _cmd="${_cmd} -e PGDATA=\"/var/lib/postgresql/${_name%/}/data\" -v \"${_SHARE_DIR%/}/${_name%/}\":\"/var/lib/postgresql/${_name%/}\""
        fi
        _cmd="${_cmd} ${_image}"
        echo "${_cmd}" | sed -E 's/POSTGRES_PASSWORD="[^"]+/POSTGRES_PASSWORD="*******/'
        eval "${_cmd}" || return $?
    fi
    docker exec -ti ${_name} bash -c 'until pg_isready -U postgres; do sleep 3; done' || return $?

    # Role and DB might already exist.
    docker exec -ti ${_name} psql -U postgres -c "CREATE ROLE ${_DB_USER} WITH LOGIN PASSWORD '${_DB_PWD}';"
    docker exec -ti ${_name} psql -U postgres -c "CREATE DATABASE ${_DB_NAME} WITH OWNER ${_DB_USER} ENCODING 'UTF8';"
    docker exec -ti ${_name} psql -U postgres -c "GRANT ALL ON DATABASE ${_DB_NAME} TO ${_DB_USER};" || return $?
}

function f_create_nxrm3() {
    local _name="${1:-"nxrm3"}"
    local _image="${2:-"sonatype/nexus3:latest"}"
    local _port="${3:-"8081"}"  # No https port exposed as reverse proxy should terminate
    local _jvm_params="${4}"    # such as -Xms2703m -Xmx2703m -XX:MaxDirectMemorySize=2703m -Dnexus.licenseFile= -Djava.util.prefs.userRoot=/some-other-dir
    local _docker_opts="${5}"
    local _share_dir="${6:-"${_SHARE_DIR}"}"
    
    if [ -z "${_share_dir%/}" ]; then
        echo "The parent directory of share / mount directory is not specified."
        return 1
    fi 
    local _nexus_data="${_share_dir%/}/sonatype/${_name}-data"
    if [ ! -d "${_nexus_data%/}" ]; then
        mkdir -v -p -m 777 "${_nexus_data%/}" || return $?
    fi
    local _opts=""
    [ -n "${_name}" ] && _opts="--name=${_name}"
    [ -n "${_jvm_params}" ] && _opts="${_opts} -e INSTALL4J_ADD_VM_PARAMS=\"${_jvm_params}\""
    [ -d "${_nexus_data%/}" ] && _opts="${_opts} -v ${_nexus_data%/}:/nexus-data"
    [ -n "${_docker_opts}" ] && _opts="${_opts} ${_docker_opts}"  # Should be last to overwrite
    local _cmd="docker run --init -d -p ${_port}:8081 ${_opts} ${_image}"
    echo "${_cmd}"
    eval "${_cmd}"
}

main() {
    if [ -z "${_CONT1_NAME}" ]; then
        echo "Please specify your IQ container name as the 1st argument of this script."
        retun 1
    fi

    if [ -z "${_DB_HOST}" ] || [ "${_DB_HOST}" == "172.17.0.1" ]; then
        if [ -n "${DOCKER_HOST}" ] && [[ "${DOCKER_HOST}" =~ ^.+//([^:]+).*$ ]]; then
            _DB_HOST="${BASH_REMATCH[1]}"
        else
            local _gw="$(docker inspect -f '{{.NetworkSettings.Gateway}}' ${_PG_CONT_NAME})"
            [ -n "${_gw}" ] && _DB_HOST="${_gw}"
            if [ -z "${_DB_HOST}" ]; then
                echo "Please set the environment variable _DB_HOST."
                return 1
            fi
        fi
    fi

    f_create_pg || return $?
    _JVM_PARAMS="-Xms2g -Xmx2g -XX:MaxDirectMemorySize=2g \
                                 -Djava.util.prefs.userRoot=/nexus-data/javaprefs \
                                 -Dnexus.licenseFile=/etc/sonatype/sonatype-license.lic \
                                 -Dnexus.datastore.enabled=true \
                                 -Dnexus.datastore.nexus.name=nexus \
                                 -Dnexus.datastore.nexus.type=jdbc \
                                 -Dnexus.datastore.nexus.jdbcUrl=jdbc:postgresql://${_DB_HOST}:${_PG_EXPOSE_PORT}/${_DB_NAME} \
                                 -Dnexus.datastore.nexus.username=${_DB_USER} \
                                 -Dnexus.datastore.nexus.password=${_DB_PWD} \
                                 -Dnexus.datastore.nexus.maximumPoolSize=10"
    f_create_nxrm3 "${_CONT2_NAME}" "${_NXRM3_IMAGENAME}" "8182" "${_JVM_PARAMS}" || return $?
    # TODO: Update above to read-only
    f_create_nxrm3 "${_CONT1_NAME}" "${_NXRM3_IMAGENAME}" "8181" "${_JVM_PARAMS}" || return $?
    # TODO: need a revese proxy or load balancer which understands the read-only status
}

if [ "$0" = "$BASH_SOURCE" ]; then
    main
fi