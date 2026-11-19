#!/usr/bin/env bash
set -euo pipefail
BUNDLE_ROOT="${1:?bundle vendor root is required}"
fail() { echo "ERROR: $*" >&2; exit 1; }
mapfile -t candidates < <(find "$BUNDLE_ROOT" -type f -path '*/bundler/gems/omnibus-*/lib/omnibus/git_cache.rb' -print)
((${#candidates[@]} == 1)) || fail "expected exactly one vendored Omnibus git_cache.rb; found ${#candidates[@]}"
file="${candidates[0]}"
ruby - "$file" <<'RUBY'
path = ARGV.fetch(0)
text = File.binread(path)
old = '        "--work-tree=\\"#{install_dir}\\"",'
new = '        "--work-tree=\\"#{software.project.install_dir}\\"",'
if text.include?(new)
  # already patched
elsif text.scan(old).length == 1
  File.binwrite(path, text.sub(old, new))
else
  abort "ERROR: Omnibus GitCache work-tree shape changed in #{path}"
end
RUBY
grep -Fq '"--work-tree=\"#{software.project.install_dir}\"",' "$file" || fail "GitCache patch verification failed"
echo "compat: corrected Omnibus GitCache --work-tree for native Windows Git"
