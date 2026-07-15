name "patch_inspec_license"
default_version "0.1.0"
dependency "chef"
skip_transitive_dependency_licensing true

build do
  block "Patch inspec-core to bypass Chef license checks" do
    inspec_gems = Dir.glob("#{install_dir}/embedded/lib/ruby/gems/*/gems/inspec-core-*").sort
    if inspec_gems.empty?
      raise "Could not find inspec-core gem in #{install_dir}/embedded/lib/ruby/gems/*/gems/inspec-core-*"
    end

    inspec_gem_dir = inspec_gems.last
    base_cli = File.join(inspec_gem_dir, "lib", "inspec", "base_cli.rb")
    runner   = File.join(inspec_gem_dir, "lib", "inspec", "runner.rb")

    # --- Patch base_cli.rb ---
    if File.exist?(base_cli)
      lines = File.readlines(base_cli, encoding: "UTF-8")
      new_lines = []
      patches_applied = 0

      lines.each do |line|
        if line.strip == "def self.fetch_and_persist_license"
          new_lines << line
          new_lines << "      return true # CINC PATCH: bypass license check\n"
          patches_applied += 1
          next
        end
        if line.strip == "def self.check_license!"
          new_lines << line
          new_lines << "      return true # CINC PATCH: bypass license check\n"
          patches_applied += 1
          next
        end
        new_lines << line
      end

      if patches_applied != 2
        raise "CINC PATCH FAILED: Expected 2 patches in base_cli.rb, but applied #{patches_applied}. " \
              "The upstream code may have changed — update the patch targets."
      end

      File.write(base_cli, new_lines.join)
      puts "CINC PATCH: Patched #{base_cli} (#{patches_applied} locations)"
    else
      raise "CINC PATCH FAILED: #{base_cli} does not exist"
    end

    # --- Patch runner.rb ---
    if File.exist?(runner)
      lines = File.readlines(runner, encoding: "UTF-8")
      new_lines = []
      patches_applied = 0

      lines.each do |line|
        if line.strip == "ChefLicensing.fetch_and_persist if @conf[:chef_license_key]"
          new_lines << "      true # CINC PATCH: bypass\n"
          new_lines << "      # #{line.strip}\n"
          patches_applied += 1
          next
        end
        if line.strip == "ChefLicensing.check_software_entitlement!"
          new_lines << "      true # CINC PATCH: bypass\n"
          new_lines << "      # #{line.strip}\n"
          patches_applied += 1
          next
        end
        new_lines << line
      end

      if patches_applied != 2
        raise "CINC PATCH FAILED: Expected 2 patches in runner.rb, but applied #{patches_applied}. " \
              "The upstream code may have changed — update the patch targets."
      end

      File.write(runner, new_lines.join)
      puts "CINC PATCH: Patched #{runner} (#{patches_applied} locations)"
    else
      raise "CINC PATCH FAILED: #{runner} does not exist"
    end
  end
end
