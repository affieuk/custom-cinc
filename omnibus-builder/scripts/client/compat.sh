#!/usr/bin/env bash
# Small compatibility helpers used by both Linux and Windows Cinc builds.

client_transform_patch_sh() {
  local input=$1 output=$2
  awk '
    /^[[:space:]]*scripts\/cinc-merge-upstream\.sh "\$\{UPSTREAM_MERGE_REF\}"[[:space:]]*$/ {
      print "# OMNIBUS-BUILDER compatibility: old Cinc branches may not contain the merge helper."
      print "if [[ -x scripts/cinc-merge-upstream.sh ]]; then"
      print "  # RHEL7 Git 1.8 may not resolve remote-qualified branches after a generic fetch."
      print "  case \"${UPSTREAM_MERGE_REF}\" in"
      print "    */*)"
      print "      compat_remote=\"${UPSTREAM_MERGE_REF%%/*}\""
      print "      compat_branch=\"${UPSTREAM_MERGE_REF#*/}\""
      print "      if git config --get \"remote.${compat_remote}.url\" >/dev/null 2>&1 && ! git rev-parse --verify \"${UPSTREAM_MERGE_REF}^{commit}\" >/dev/null 2>&1; then"
      print "        git fetch -q \"${compat_remote}\" \"+refs/heads/${compat_branch}:refs/remotes/${compat_remote}/${compat_branch}\""
      print "      fi"
      print "      ;;"
      print "  esac"
      print "  scripts/cinc-merge-upstream.sh \"${UPSTREAM_MERGE_REF}\""
      print "else"
      print "  echo \"Legacy Cinc branch has no cinc-merge-upstream.sh; using the selected Cinc branch as-is\""
      print "fi"
      next
    }
    /^[[:space:]]*echo "Updating Gemfile.lock"[[:space:]]*$/ && !openssl_injected {
      print "# OMNIBUS-BUILDER compatibility: 19.3.14 carries an exact openssl 3.3.1 gem pin"
      print "# that conflicts with the modern Ruby/toolchain path. Remove only that known pin."
      print "if [[ -f chef/Gemfile ]] && grep -Eq '\''^[[:space:]]*gem \"openssl\",[[:space:]]*\"= 3\\.3\\.1\"[[:space:]]*$'\'' chef/Gemfile; then"
      print "  sed -i '\''s/^[[:space:]]*gem \"openssl\"/# &/'\'' chef/Gemfile"
      print "fi"
      openssl_injected=1
    }
    { print }
  ' "$input" > "$output"
}

client_disable_windows_runtime_devkit() {
  local project_file=$1
  local marker='# OMNIBUS-BUILDER: omit ruby-msys2-devkit from installed runtime'
  [[ -f "$project_file" ]] || { echo "ERROR: Cinc project file not found: $project_file" >&2; return 1; }

  if grep -Eq '^[[:space:]]*dependency[[:space:]]+"ruby-msys2-devkit"[[:space:]]+if[[:space:]]+windows\?[[:space:]]*$' "$project_file"; then
    awk -v marker="$marker" '
      /^[[:space:]]*dependency[[:space:]]+"ruby-msys2-devkit"[[:space:]]+if[[:space:]]+windows\?[[:space:]]*$/ {
        print marker
        print "# " $0
        next
      }
      { print }
    ' "$project_file" > "${project_file}.tmp"
    mv "${project_file}.tmp" "$project_file"
  fi

  if grep -Eq '^[[:space:]]*[^#[:space:]].*ruby-msys2-devkit' "$project_file"; then
    echo "ERROR: active ruby-msys2-devkit reference remains in $project_file" >&2
    grep -n 'ruby-msys2-devkit' "$project_file" >&2 || true
    return 1
  fi
}

client_append_timestamp_needed() {
  local build_sh=$1 omnibus_gemfile=$2
  grep -Fq -- '--override append_timestamp:false' "$build_sh" &&
    grep -Eq '^[[:space:]]*gem[[:space:]]+"omnibus",[[:space:]]+github:' "$omnibus_gemfile"
}

client_apply_append_timestamp() {
  local build_sh=$1 omnibus_rb=$2
  if grep -Eq '^[[:space:]]*append_timestamp[[:space:]]+' "$omnibus_rb"; then
    sed -i -E 's/^[[:space:]]*append_timestamp[[:space:]]+.*/append_timestamp false/' "$omnibus_rb"
  else
    printf '\n# Ruby 3.4 / older Omnibus CLI compatibility\nappend_timestamp false\n' >> "$omnibus_rb"
  fi
  sed -i 's/[[:space:]]*--override[[:space:]]\+append_timestamp:false//g' "$build_sh"
}

client_apply_omnibus_overrides() {
  local fragment=$1 target=$2
  [[ -f "$fragment" ]] || { echo "ERROR: Omnibus override file missing: $fragment" >&2; return 1; }
  if grep -Eq '^[[:space:]]*[^#[:space:]]' "$fragment"; then
    {
      echo
      echo '# OMNIBUS-BUILDER overrides BEGIN'
      cat "$fragment"
      echo '# OMNIBUS-BUILDER overrides END'
    } >> "$target"
  fi
}

client_apply_gem_overrides() {
  local fragment=$1 gemfile=$2
  [[ -f "$fragment" ]] || { echo "ERROR: Gemfile override file missing: $fragment" >&2; return 1; }
  ruby - "$fragment" "$gemfile" <<'RUBY'
fragment, gemfile = ARGV
lines = File.readlines(gemfile, chomp: true)
overrides = File.readlines(fragment, chomp: true).filter_map do |raw|
  line = raw.strip
  next if line.empty? || line.start_with?("#")
  m = line.match(/\Agem\s+["']([^"']+)["'](?:\s*,|\s*\z)/)
  abort "ERROR: unsupported Gemfile override syntax: #{raw}" unless m
  [m[1], raw]
end

overrides.each do |name, declaration|
  re = /^\s*gem\s+["']#{Regexp.escape(name)}["'](?:\s*,|\s*$)/
  matches = lines.each_index.select { |i| lines[i] !~ /^\s*#/ && lines[i] =~ re }
  abort "ERROR: multiple active Gemfile declarations for #{name}; update manually" if matches.length > 1
  if matches.one?
    lines[matches.first] = declaration
  else
    lines << declaration
  end
end
File.write(gemfile, lines.join("\n") + "\n")
RUBY
}
