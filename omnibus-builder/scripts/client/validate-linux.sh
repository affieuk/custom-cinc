#!/usr/bin/env bash
set -euo pipefail
TARGET="${TARGET:?TARGET is required}"
PACKAGE_BASENAME="${PACKAGE_BASENAME:?PACKAGE_BASENAME is required}"
EXPECTED_TARGET_VERSION="${EXPECTED_TARGET_VERSION:?EXPECTED_TARGET_VERSION is required}"
PACKAGE="/artifacts/${PACKAGE_BASENAME}"
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ -f "$PACKAGE" ]] || fail "package not found: $PACKAGE"
[[ ! -e /opt/omnibus-toolchain ]] || fail "clean runtime unexpectedly contains Omnibus Toolchain"

case "$TARGET" in
  rhel7|rhel8|rhel10)
    grep -Eq "release ${TARGET#rhel}([ .]|$)" /etc/redhat-release || fail "wrong RHEL runtime"
    [[ "$(rpm -qp --qf '%{NAME}' "$PACKAGE")" == cinc ]] || fail "expected cinc RPM"
    [[ "$(rpm -qp --qf '%{VERSION}' "$PACKAGE")" == "$EXPECTED_TARGET_VERSION" ]] || fail "RPM version mismatch"
    rpm -Uvh "$PACKAGE"
    ;;
  ubuntu2204)
    . /etc/os-release; [[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 ]] || fail "expected Ubuntu 22.04"
    [[ "$(dpkg-deb -f "$PACKAGE" Package)" == cinc ]] || fail "expected cinc DEB"
    pv="$(dpkg-deb -f "$PACKAGE" Version)"; [[ "$pv" == "$EXPECTED_TARGET_VERSION" || "$pv" == "$EXPECTED_TARGET_VERSION"-* ]] || fail "DEB version mismatch: $pv"
    dpkg -i "$PACKAGE"
    ;;
esac

for exe in cinc-client cinc-solo cinc-auditor; do [[ -x "/opt/cinc/bin/$exe" ]] || fail "$exe missing"; done
/opt/cinc/bin/cinc-client --version
/opt/cinc/bin/cinc-solo --version
/opt/cinc/bin/cinc-auditor version

ruby_bin=/opt/cinc/embedded/bin/ruby
"$ruby_bin" --version
"$ruby_bin" -ropenssl -e 'puts OpenSSL::OPENSSL_VERSION'

# Check any active Ruby/OpenSSL overrides declared in the project fragment.
read_override() {
  local component=$1
  sed -n -E "s/^[[:space:]]*override[[:space:]]+:${component},[[:space:]]+version:[[:space:]]*[\"']([^\"']+)[\"'].*/\\1/p" /handoff/overrides/cinc/omnibus.rb | tail -1
}
expected_ruby="$(read_override ruby)"
expected_openssl="$(read_override openssl)"
if [[ -n "$expected_ruby" ]]; then
  actual="$($ruby_bin -e 'print RUBY_VERSION')"; [[ "$actual" == "$expected_ruby" ]] || fail "Ruby override mismatch: expected $expected_ruby, got $actual"
fi
if [[ -n "$expected_openssl" ]]; then
  actual="$($ruby_bin -ropenssl -e 'print OpenSSL::OPENSSL_VERSION.split[1]')"; [[ "$actual" == "$expected_openssl" ]] || fail "OpenSSL override mismatch: expected $expected_openssl, got $actual"
fi

# Check every exact gem declaration in the override fragment against the installed runtime.
"$ruby_bin" - /handoff/overrides/cinc/Gemfile <<'RUBY'
require "rubygems"
File.readlines(ARGV.fetch(0)).each do |raw|
  line = raw.strip
  next if line.empty? || line.start_with?("#")
  m = line.match(/\Agem\s+["']([^"']+)["']\s*,\s*["']=\s*([^"']+)["']/)
  abort "ERROR: gem override must use an exact '= x.y.z' requirement for validation: #{raw}" unless m
  name, version = m.captures
  versions = Gem::Specification.find_all_by_name(name).map { |s| s.version.to_s }
  abort "ERROR: gem #{name} expected #{version}, installed #{versions.join(', ')}" unless versions.include?(version)
  puts "Gem override: #{name}=#{version}"
end
RUBY

rm -rf /tmp/cinc-validation
mkdir -p /tmp/cinc-validation/cookbooks/validation/recipes /tmp/cinc-validation/profile/controls
cat > /tmp/cinc-validation/client.rb <<'RUBY'
cookbook_path ['/tmp/cinc-validation/cookbooks']
file_cache_path '/tmp/cinc-validation/cache'
RUBY
cat > /tmp/cinc-validation/cookbooks/validation/metadata.rb <<'RUBY'
name 'validation'
version '0.1.0'
RUBY
cat > /tmp/cinc-validation/cookbooks/validation/recipes/default.rb <<'RUBY'
file '/tmp/cinc-validation/marker' do
  content "cinc validation passed\n"
end
RUBY
/opt/cinc/bin/cinc-solo -N "cinc-${TARGET}-validation" -c /tmp/cinc-validation/client.rb -o 'recipe[validation]'
grep -Fx 'cinc validation passed' /tmp/cinc-validation/marker >/dev/null || fail "cinc-solo recipe did not converge"
cat > /tmp/cinc-validation/profile/inspec.yml <<'YAML'
name: omnibus-builder-validation
title: Omnibus Builder Validation
version: 0.1.0
YAML
cat > /tmp/cinc-validation/profile/controls/marker.rb <<'RUBY'
control 'cinc-solo-marker' do
  describe file('/tmp/cinc-validation/marker') do
    it { should exist }
    its('content') { should eq "cinc validation passed\n" }
  end
end
RUBY
/opt/cinc/bin/cinc-auditor exec /tmp/cinc-validation/profile --no-color

echo "PASS: ${TARGET} Cinc Client ${EXPECTED_TARGET_VERSION} installs; client, solo and auditor work"
