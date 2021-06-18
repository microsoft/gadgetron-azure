#!/bin/bash

mkdir -p ssh_keys
rm -rf ssh_keys/*
ssh-keygen -f ssh_keys/ssh_host_rsa_key -N '' -t rsa
ssh-keygen -f ssh_keys/ssh_host_ed25519_key -N '' -t ed25519
ssh-keygen -f ssh_keys/ssh_host_ecdsa_key -N '' -t ecdsa

kubectl create secret generic ssh-server-keys \
    --from-file=ssh_host_rsa_key=ssh_keys/ssh_host_rsa_key \
    --from-file=ssh_host_rsa_key.pub=ssh_keys/ssh_host_rsa_key.pub \
    --from-file=ssh_host_ed25519_key=ssh_keys/ssh_host_ed25519_key \
    --from-file=ssh_host_ed25519_key.pub=ssh_keys/ssh_host_ed25519_key.pub \
    --from-file=ssh_host_ecdsa_key=ssh_keys/ssh_host_ecdsa_key \
    --from-file=ssh_host_ecdsa_key.pub=ssh_keys/ssh_host_ecdsa_key.pub

