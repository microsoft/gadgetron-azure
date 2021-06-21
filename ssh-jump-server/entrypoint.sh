#!/bin/bash

if [[ -d /opt/ssh-server-secrets ]]; then
    # Keys have been mounted, copy them
    cp /opt/ssh-server-secrets/* /etc/ssh/
    chmod 644 /etc/ssh/*.pub
    for f in $(ls /etc/ssh/ssh_host_*_key); do
        chmod 600 $f
    done
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