#!/usr/bin/env bash
# @see http://superuser.com/questions/109213/how-do-i-list-the-ssl-tls-cipher-suites-a-particular-website-offers

# OpenSSL requires the port number.
_HOST="$1"
_PORT="${2-443}"
SERVER=$_HOST:$_PORT
DELAY=1
ciphers=$(openssl ciphers 'ALL:eNULL' | sed -e 's/:/ /g')

echo Obtaining cipher list from $SERVER with $(openssl version).

for cipher in ${ciphers[@]}
do
result=$(echo -n | openssl s_client -cipher "$cipher" -connect $SERVER 2>&1)
if [[ "$result" =~ ":error:" ]] ; then
  error=$(echo -n $result | cut -d':' -f6)
  echo -e "$cipher\tNO ($error)" >&2
else
  if [[ "$result" =~ "Cipher is ${cipher}" || "$result" =~ "Cipher    :" ]] ; then
    echo -e "$cipher\tYES"
  else
    echo -e "$cipher\tUNKNOWN RESPONSE" >&2
    echo $result >&2
  fi
fi
sleep $DELAY
done