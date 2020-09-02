#!/bin/bash

secretName=$1

if [ -z "$secretName" ]; then
    secretName="stunnel"
fi

if [ ! -f stunnel.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout stunnel.key -out stunnel.crt
fi

if [ ! -f stunnel.secrets ]; then
    for i in {1..10}; do
        echo "client${i}:$(openssl rand -base64 24)" >> stunnel.secrets
    done
fi

kubectl create secret generic $secretName --from-file=stunnel.crt --from-file=stunnel.key --from-file=stunnel.secrets
