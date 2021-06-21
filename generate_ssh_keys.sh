#!/bin/bash

if [ $# -gt 0 ]; then
    ALGORITHMS=$@
else
    ALGORITHMS="rsa ed25519 ecdsa"
fi

mkdir -p ssh_keys
rm -rf ssh_keys/*

for algorithm in $ALGORITHMS; do
    ssh-keygen -f ssh_keys/ssh_host_${algorithm}_key -N '' -t ${algorithm}
done

kubectl create secret generic ssh-server-keys --from-file=ssh_keys

