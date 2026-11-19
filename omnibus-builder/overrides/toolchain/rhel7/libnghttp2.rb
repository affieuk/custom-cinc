#
# EL7 compatibility override for Cinc omnibus-software libnghttp2.
#
# Validated with:
#   Cinc Omnibus Toolchain 26.0.3 and 26.0.4
#   nghttp2 1.70.0
#   RHEL 7.9
#   DTS11 GCC 11.2.1
#
# Changes from the contemporary upstream recipe:
#   1. Build library only.
#   2. Do not regenerate the release tarball's Autotools files using
#      EL7's old Automake/Autoconf stack.
#

name "libnghttp2"
default_version "1.70.0"

dependency "openssl"

license "MIT"
license_file "COPYING"
skip_transitive_dependency_licensing true

version("1.70.0") { source sha256: "aa317e2cf9dca6afa0aed68f8fad6ff303ec6982e25a78c75c0b65e2b9b3ded5" }
version("1.69.0") { source sha256: "c866b7477cbb7512ab6863a685027adbb1bb8da8fc3bab7429ed43d3281d5aa9" }
version("1.68.1") { source sha256: "ceb434c1f9dfe2a9d305b6b797786fb9227484dfa88508d14ca1c50263db55d3" }

source url: "https://github.com/nghttp2/nghttp2/releases/download/v#{version}/nghttp2-#{version}.tar.gz"

relative_path "nghttp2-#{version}"

build do
  env = with_standard_compiler_flags(with_embedded_path)

  configure_options = [
    "--prefix=#{install_dir}/embedded",
    "--with-openssl",
    "--enable-lib-only",
  ]

  configure(*configure_options, env: env)
  make "-j #{workers}", env: env
  make "install", env: env
end
