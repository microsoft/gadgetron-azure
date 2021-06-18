#!/bin/bash

if [[ -f /opt/ssh-server-secrets/ssh_host_rsa_key ]]; then
    # Keys have been mounted, copy them
    cp /opt/ssh-server-secrets/* /etc/ssh/
    chmod 644 /etc/ssh/*.pub
    chmod 600 /etc/ssh/ssh_host_ecdsa_key
    chmod 600 /etc/ssh/ssh_host_ed25519_key
    chmod 600 /etc/ssh/ssh_host_rsa_key
else
    # Genenerate
    rm -rf /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
fi

#Switch off DNS checking
sed -i.bak "s/#UseDNS no/UseDNS no/g" /etc/ssh/sshd_config

#Import public key
mkdir -p /root/.ssh
touch /root/.ssh/authorized_keys
echo ${PUBLIC_KEY} > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

#Run SSH server
mkdir -p /run/sshd
/usr/sbin/sshd -D