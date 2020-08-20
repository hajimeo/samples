#!/usr/bin/env bash
# https://success.docker.com/article/how-do-i-authenticate-with-the-v2-api

# https://docs.docker.com/registry/spec/auth/token/
#curl -u admin:admin123  https://dh1.standalone.localdomain:18082/v2/token
#{"token":"DockerToken.eeb18364-f2a5-31f3-9006-5daf80ceebfd"}           << doesn't look like a bearer token


# TODO: still not working!!!!

set -e

# set username and password
UNAME="${1:-"admin"}"
UPASS="${2:-"admin123"}"
DOCKER_HOST="dh1.standalone.localdomain:18082"
BASE_URL="https://${DOCKER_HOST}/" # https://hub.docker.com/

# get token to be able to talk to Docker Hub
#TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${UNAME}'", "password": "'${UPASS}'"}' ${BASE_URL%/}/v2/users/login/ | jq -r .token)
TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username":"'${UNAME}'","password":"'${UPASS}'","serveraddress":"'${DOCKER_HOST}'"}' ${BASE_URL%/}/v1.40/auth | jq -r .token)

# get list of namespaces accessible by user (not in use right now)
#NAMESPACES=$(curl -s -H "Authorization: JWT ${TOKEN}" ${BASE_URL%/}/v2/repositories/namespaces/ | jq -r '.namespaces|.[]')

# get list of repos for that user account
REPO_LIST=$(curl -s -H "Authorization: JWT ${TOKEN}" ${BASE_URL%/}/v2/repositories/${UNAME}/?page_size=10000 | jq -r '.results|.[]|.name')

# build a list of all images & tags
for i in ${REPO_LIST}
do
  # get tags for repo
  IMAGE_TAGS=$(curl -s -H "Authorization: JWT ${TOKEN}" ${BASE_URL%/}/v2/repositories/${UNAME}/${i}/tags/?page_size=10000 | jq -r '.results|.[]|.name')

  # build a list of images from tags
  for j in ${IMAGE_TAGS}
  do
    # add each tag to list
    FULL_IMAGE_LIST="${FULL_IMAGE_LIST} ${UNAME}/${i}:${j}"
  done
done

# output list of all docker images
for i in ${FULL_IMAGE_LIST}
do
  echo ${i}
done

curl -I -H 'Host: registry.redhat.io' -H 'User-Agent: docker/19.03.5 go/go1.12.12 git-commit/633a0ea kernel/4.19.76-linuxkit os/linux arch/amd64 UpstreamClien19.03.5 \(darwin\))' -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -H 'Accept: application/vnd.docker.distribution.manifest.v1+prettyjws' -H 'Accept: application/vnd.docker.distribution.manifest.v1+json​' -H 'Authorization: Bearer XXXXXXXXXXXXXX' --compressed 'https://registry.redhat.io/v2/openshift4/ose-cluster-logging-operator/manifests/sha256:e1168e1a1c6e4f248cae9810bd10b06ed3a3c0be06aca8231a933bd63340553c'