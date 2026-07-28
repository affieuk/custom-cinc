#!/usr/bin/env bash
set -Eeuo pipefail

echo "==> Fixing EOL CentOS 7 repositories..."
sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo
sed -i 's|#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=http://vault.centos.org/7.9.2009|g' /etc/yum.repos.d/CentOS-*.repo

echo "==> Configuring SCL Software Collection Vault Repositories..."
cat << 'EOF' > /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo
[centos-sclo-rh]
name=CentOS-7 - SCLo rh Vault
baseurl=http://vault.centos.org/7.9.2009/sclo/x86_64/rh/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
EOF

cat << 'EOF' > /etc/yum.repos.d/CentOS-SCLo-scl.repo
[centos-sclo-sclo]
name=CentOS-7 - SCLo sclo Vault
baseurl=http://vault.centos.org/7.9.2009/sclo/x86_64/sclo/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
EOF

echo "==> Importing SCL Signature Keys..."
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo

echo "==> Resetting YUM Cache..."
yum clean all

echo "==> Installing Devtoolset-11 (GCC 11 & modern Make)..."
yum install -y devtoolset-11-gcc devtoolset-11-gcc-c++ devtoolset-11-make

echo "==> System successfully updated to use modern build tooling!"

echo "Run: scl enable devtoolset-11 path/to/script.sh"