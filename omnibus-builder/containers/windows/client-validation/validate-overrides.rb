require "rubygems"
require "openssl"
omnibus_file, gemfile = ARGV
text = File.read(omnibus_file)
if (m = text.scan(/^\s*override\s+:ruby,\s+version:\s*["']([^"']+)["']/).last)
  expected = m.first
  abort "Ruby override mismatch: expected #{expected}, got #{RUBY_VERSION}" unless RUBY_VERSION == expected
  puts "Ruby override: #{expected}"
end
if (m = text.scan(/^\s*override\s+:openssl,\s+version:\s*["']([^"']+)["']/).last)
  expected = m.first
  actual = OpenSSL::OPENSSL_VERSION.split[1]
  abort "OpenSSL override mismatch: expected #{expected}, got #{actual}" unless actual == expected
  puts "OpenSSL override: #{expected}"
end
File.readlines(gemfile).each do |raw|
  line = raw.strip
  next if line.empty? || line.start_with?("#")
  m = line.match(/\Agem\s+["']([^"']+)["']\s*,\s*["']=\s*([^"']+)["']/)
  abort "Gem override must use an exact '= x.y.z' requirement: #{raw}" unless m
  name, version = m.captures
  versions = Gem::Specification.find_all_by_name(name).map { |s| s.version.to_s }
  abort "Gem #{name}: expected #{version}, installed #{versions.join(', ')}" unless versions.include?(version)
  puts "Gem override: #{name}=#{version}"
end
