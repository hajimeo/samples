#!/usr/bin/env bash
# PRECONDITION:
#   Using "default" namespace
#   Assuming no pods in "default"
#   The firstcrd object should be only one

# 制御ループ
while true
do
  # カスタムリソースの数を取得する
  fcrdnum=$(echo $(kubectl get fcrd --no-headers --ignore-not-found | wc -l))
  if [[ ${fcrdnum} -gt 1 ]] ; then
    echo "ERROR:One or more firstcrd resource exists."
    exit 1
  fi
  if [[ ${fcrdnum} -eq 1 ]] ; then
    # カスタムリソース名を取得する
    name=$(kubectl get fcrd -o jsonpath='{.items[0].metadata.name}')
    # カスタムリソースのmessage属性を取得する
    message=$(printf "%q" $(kubectl get fcrd ${name} -o jsonpath='{.spec.message}'))
  else
    name=""
    message=""
  fi
  # カスタムリソース名と同じ名前のPod数を取得する
  podnum=$(echo $(kubectl get pod ${name} --no-headers --ignore-not-found | wc -l))
  # firstcrdリソースが存在する場合
  if [[ ${name} != "" ]] ; then
    # podが存在しない場合
    if [[ ${podnum} -eq 0 ]] ; then
      # myfirstcrリソースが存在するのにPodが存在しないので是正する
      echo "creating ${name} pod"
      cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
spec:
  initContainers:
  - name: init
    image: busybox
    args:
    - /bin/sh
    - -c
    - echo ${message} > /test/index.html
    volumeMounts:
    - mountPath: /test
      name: shared-data
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - mountPath: /usr/share/nginx/html/
      name: shared-data
  volumes:
    - name: shared-data
      emptyDir: {}
YAML
    # podが存在する場合
    else
      # 現在のPodが表示するメッセージを取得する
      podmessage=$(printf "%q" $(kubectl exec ${name} -c nginx -- curl -s http://localhost))
          if [[ "${podmessage}" != "${message}" ]] ; then
      # メッセージがmyfirstcrリソースの定義と異なるのでPodを削除する
        echo "deleting ${name} pod"
        kubectl delete pod ${name}
      fi
    fi
  else
    # firstcrdリソースが存在しないのにPodが存在するので是正する
    if [[ ${podnum} -ne 0 ]] ; then
      kubectl delete pod --all
    fi
  fi
  sleep 15
done