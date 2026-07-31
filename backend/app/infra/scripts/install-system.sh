#!/bin/bash
# Installation des packages système

# Sur Debian/Raspberry Pi OS
sudo apt update
sudo apt install -y \
    netdata \
    fail2ban \
    nftables \
    openssl \
    sqlcipher \
    htop

# Sur Yocto (si opkg configuré)
# opkg install netdata fail2ban nftables openssl