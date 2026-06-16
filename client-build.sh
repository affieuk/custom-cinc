#!/bin/bash -ex

source /home/omnibus/load-omnibus-toolchain.sh
source c-set-env.sh

rm -rf client
git clone https://gitlab.com/cinc-project/distribution/client.git
cd client

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

if command -v rpm &>/dev/null; then
    rpm -ivh chef-foundation/pkg/cinc-foundation-*.rpm

elif command -v dpkg &>/dev/null; then
    dpkg -i chef-foundation/pkg/cinc-foundation-*.deb

else
    echo "ERROR: Neither 'rpm' nor 'dpkg' package managers were found on this system." >&2
    exit 1
fi

#mv chef/omnibus/pkg/cinc*.rpm ..
#rpm -ivh ../cinc*el10*.rpm

# Add OS to filename
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_SUFFIX="_${ID}${VERSION_ID}"
else
    echo "Error: Cannot detect OS version." && exit 1
fi

FILE_PATH=$(ls chef/omnibus/pkg/cinc_*.deb 2>/dev/null)
if [ -n "$FILE_PATH" ]; then
    FILE_NAME=$(basename "$FILE_PATH")
    NEW_NAME=$(echo "$FILE_NAME" | sed "s/\(_[^_]*\.deb\)$/${OS_SUFFIX}\1/")
    mv "$FILE_PATH" "../$NEW_NAME"
else
    echo "Error: No .deb package found in chef/omnibus/pkg/" && exit 1
fi
dpkg -i ../$NEW_NAME

/opt/cinc/bin/cinc-client -v
/opt/cinc/embedded/bin/ruby -v
/opt/cinc/embedded/bin/openssl -v

