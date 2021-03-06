#!/bin/sh

set -ex

# Configure DNS
rm /etc/resolv.conf
echo nameserver 8.8.8.8 > /etc/resolv.conf

# Install packages
apk update
apk add curl jq openssh nmap nmap-nselibs nmap-scripts
rm -rf /var/cache/apk/*

adduser -D listener

# Cleanup DNS config
rm -f /etc/resolv.conf
