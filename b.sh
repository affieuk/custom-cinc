#!/bin/bash -ex

source /home/omnibus/load-omnibus-toolchain.sh
source c.sh

#rpm -ivh perl-Time-Piece-1.20.1-297.el7.x86_64.rpm || true

#rm -rf client chef
#git clone https://gitlab.com/cinc-project/distribution/client.git
cd client

sed -i '/^cd \$TOP_DIR$/i\
mkdir -p omnibus/config/software\
cp ../../patch_inspec_license.rb omnibus/config/software/patch_inspec_license.rb\
sed -i '"'"'/\^dependency "chef"\$/a dependency "patch_inspec_license"'"'"' omnibus/config/projects/cinc.rb' patch.sh

./patch.sh

sed -i "s/\(override \"openssl\", version: \)\"[^\"]*\"/\1\"$OPENSSL_OVERRIDE\"/" chef/omnibus_overrides.rb

BUILD_SCRIPT="build.sh"

INJECT_BLOCK=$(cat << EOF
GEM_PATH=\$(bundle show omnibus-software)
OPENSSL_RB="\${GEM_PATH}/config/software/openssl.rb"
echo "openssl.rb file location"
echo \$OPENSSL_RB

if ! grep -q "version(\"${OPENSSL_OVERRIDE}\")" "\${OPENSSL_RB}"; then
    sed -i '/name "openssl"/a \\\\  version("${OPENSSL_OVERRIDE}") { source sha256: "${OPENSSL_SHA256}" }' "\${OPENSSL_RB}"
fi
EOF
)

export INJECT_BLOCK

awk '
1; 
$0 == "bundle install" { print ENVIRON["INJECT_BLOCK"] }
' "$BUILD_SCRIPT" > "$BUILD_SCRIPT.tmp" && mv "$BUILD_SCRIPT.tmp" "$BUILD_SCRIPT" && chmod +x $BUILD_SCRIPT

./build.sh

#mv chef/omnibus/pkg/cinc*.rpm ..
#rpm -e cinc || true
#rpm -ivh ../cinc-19.2.12*el8*

mv chef/omnibus/pkg/cinc*.deb ..
dpkg -i ../cinc_19*.deb

/opt/cinc/bin/cinc-client -v
/opt/cinc/embedded/bin/ruby -v
/opt/cinc/embedded/bin/openssl -v
/opt/cinc/embedded/bin/gem list rexml
/opt/cinc/bin/cinc-auditor exec




