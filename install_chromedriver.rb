#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'fileutils'
require 'uri'
require 'open-uri'
require 'tmpdir'

# https://github.com/GoogleChromeLabs/chrome-for-testing
KNOWN_GOOD_VERSIONS_URL = 'https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json'
PLATFORM = 'mac-arm64'
CHROME_PATH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
OPT_DIR = File.expand_path('opt', __dir__)
BIN_DIR = File.expand_path('bin', __dir__)
SYMLINK_PATH = File.join(BIN_DIR, 'chromedriver')

def get_installed_chrome_version
  output = `"#{CHROME_PATH}" --version 2>/dev/null`.strip
  raise "Chrome not found at #{CHROME_PATH}" if output.empty?

  match = output.match(/Google Chrome (\d+\.\d+\.\d+\.\d+)/)
  raise "Could not parse Chrome version from: #{output}" unless match

  match[1]
end

def fetch_json(url)
  uri = URI.parse(url)
  response = Net::HTTP.get_response(uri)

  unless response.is_a?(Net::HTTPSuccess)
    raise "Failed to fetch JSON: #{response.code} #{response.message}"
  end

  JSON.parse(response.body)
end

def find_chromedriver_for_version(data, chrome_version, platform)
  versions = data['versions']
  raise "No versions found in data" unless versions

  chrome_major = chrome_version.split('.').first.to_i

  candidates = versions.select do |v|
    v['version'].split('.').first.to_i == chrome_major &&
      v.dig('downloads', 'chromedriver')
  end

  raise "No chromedriver found for Chrome major version #{chrome_major}" if candidates.empty?

  best = candidates.max_by { |v| Gem::Version.new(v['version']) }
  chromedriver_downloads = best.dig('downloads', 'chromedriver')
  entry = chromedriver_downloads.find { |d| d['platform'] == platform }
  raise "Platform #{platform} not found" unless entry

  [best['version'], entry['url']]
end

def download_file(url, dest_path)
  puts "Downloading from #{url}..."

  URI.open(url) do |remote|
    File.open(dest_path, 'wb') do |file|
      file.write(remote.read)
    end
  end

  puts "Downloaded to #{dest_path}"
end

def unzip_file(zip_path, dest_dir)
  puts "Unzipping to #{dest_dir}..."
  FileUtils.rm_rf(dest_dir) if Dir.exist?(dest_dir)
  FileUtils.mkdir_p(dest_dir)

  system('unzip', '-q', '-o', zip_path, '-d', dest_dir) or raise "Failed to unzip"
  puts "Unzipped successfully"
end

def create_symlink(source, dest)
  FileUtils.mkdir_p(File.dirname(dest))
  FileUtils.rm_f(dest)
  FileUtils.ln_s(source, dest)
  puts "Created symlink: #{dest} -> #{source}"
end

def main
  chrome_version = get_installed_chrome_version
  puts "Installed Chrome: #{chrome_version}"

  puts "Fetching version info..."
  data = fetch_json(KNOWN_GOOD_VERSIONS_URL)

  version, url = find_chromedriver_for_version(data, chrome_version, PLATFORM)
  puts "Found chromedriver #{version} for Chrome #{chrome_version.split('.').first}.x"

  versioned_dir = File.join(OPT_DIR, "chromedriver-#{version}")

  zip_filename = File.basename(URI.parse(url).path)
  zip_path = File.join(Dir.tmpdir, zip_filename)

  download_file(url, zip_path)
  unzip_file(zip_path, versioned_dir)

  # The zip extracts to a subdirectory like chromedriver-mac-arm64/chromedriver
  extracted_subdir = Dir.glob(File.join(versioned_dir, 'chromedriver-*')).first
  chromedriver_binary = File.join(extracted_subdir, 'chromedriver')

  unless File.exist?(chromedriver_binary)
    raise "Chromedriver binary not found at #{chromedriver_binary}"
  end

  FileUtils.chmod(0755, chromedriver_binary)
  create_symlink(chromedriver_binary, SYMLINK_PATH)

  # Cleanup
  FileUtils.rm_f(zip_path)

  puts "\nInstallation complete!"
  puts "Chromedriver #{version} installed to: #{chromedriver_binary}"
  puts "Symlinked to: #{SYMLINK_PATH}"

  # Verify
  puts "\nVerifying installation..."
  system(SYMLINK_PATH, '--version')
end

main

