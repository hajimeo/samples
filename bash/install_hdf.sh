#!/usr/bin/env bash
#
# For Demo purpose, installing Nifi (HDF) with blueprint into a single node
#
#   ./install_hdf.sh some_nifi_node_fqdn
#
# REQUIREMENT:
#   Ambari (sever and agent) should be already installed and registered
#   Run this script from Ambari Server node
#
# Blueprint installable versions:
#   http://public-repo-1.hortonworks.com/HDF/hdf_urlinfo.json
#

_NIFI_HOSTNAME="${1:-`hostname -f`}"
_CLUSTER_NAME="${2:-HDFDemo}"
_HDF_FULL_VERSION="${3:-3.1.1.0-35}"

_CONFIG_JSON="cluster_config.json"
_HOSTMAP_JSON="host_mapping.json"
_OS_TYPE="centos7"

# Populate other version variables
if [[ "${_HDF_FULL_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)- ]]; then
    _hdf_v="${BASH_REMATCH[1]}"
    _hdf_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.${BASH_REMATCH[4]}"
    _hdf_stack_ver="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
else
    echo "${_HDF_FULL_VERSION} is not a valid HDF full version"
    exit 1
fi

_HDF_TAR_GZ="http://public-repo-1.hortonworks.com/HDF/${_OS_TYPE}/${_hdf_v}.x/updates/${_hdf_version}/tars/hdf_ambari_mp/hdf-ambari-mpack-${_HDF_FULL_VERSION}.tar.gz"
_HDF_VDF="http://public-repo-1.hortonworks.com/HDF/${_OS_TYPE}/${_hdf_v}.x/updates/${_hdf_version}/HDF-${_HDF_FULL_VERSION}.xml"

# If configuration json file doesn't exist, create it
if [ ! -s "${_CONFIG_JSON}" ]; then
    tee "${_CONFIG_JSON}" > /dev/null << EOF
{
  "Blueprints": {
    "blueprint_name": "${_CLUSTER_NAME}-bp",
    "stack_name" : "HDF",
    "stack_version" : "${_hdf_stack_ver}"
  },
  "configurations": [],
  "host_groups": [
    {
      "components": [
        {
          "name": "ZOOKEEPER_SERVER"
        },
        {
          "name": "NIFI_CA"
        },
        {
          "name": "NIFI_MASTER"
        }
      ],
      "configurations": [],
      "name": "host_group_1"
    }
  ]
}
EOF
fi

# If host mappping json file doesn't exist, create it
if [ ! -s "${_HOSTMAP_JSON}" ]; then
    tee "${_HOSTMAP_JSON}" > /dev/null << EOF
{
  "blueprint": "${_CLUSTER_NAME}-bp",
  "default_password": "hadoop",
  "host_groups": [
    {
      "hosts": [
        {
          "fqdn": "${_NIFI_HOSTNAME}"
        }
      ],
      "name": "host_group_1"
    }
  ]
}
EOF
fi

# if mpack is already installed, wouldn't need to restart Ambari
ambari-server install-mpack --mpack="${_HDF_TAR_GZ}" && ambari-server restart --skip-database-check

echo "INFO: Registering version definition..."
curl -si -u admin:admin -H 'X-Requested-By:ambari' "http://`hostname -f`:8080/api/v1/version_definitions" -X POST -d '{"VersionDefinition":{"version_url":"'${_HDF_VDF}'"}}' | tee /tmp/curl_vdf.out | grep '^HTTP/1.1 2' || cat /tmp/curl_vdf.out
echo ""

echo "INFO: Registering cluster configuration..."
curl -si -u admin:admin -H 'X-Requested-By:ambari' "http://`hostname -f`:8080/api/v1/blueprints/${_CLUSTER_NAME}" -X POST -d @${_CONFIG_JSON} | tee /tmp/curl_bp1.out | grep '^HTTP/1.1 2' || cat /tmp/curl_bp1.out
echo ""

echo "INFO: Registering host mapping which starts the blueprint installation..."
curl -si -u admin:admin -H 'X-Requested-By:ambari' "http://`hostname -f`:8080/api/v1/clusters/${_CLUSTER_NAME}" -X POST -d @${_HOSTMAP_JSON} | tee /tmp/curl_bp2.out | grep '^HTTP/1.1 2' || cat /tmp/curl_bp2.out
echo ""
