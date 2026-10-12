require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'

# Run the real installers against isolated paths; never install an input method.
repo = File.expand_path('..', __dir__)
Dir.mktmpdir('seamtype-install-check-') do |fixture|
  system_app = File.join(fixture, 'system', 'Seamtype.app')
  user_home = File.join(fixture, 'user')
  user_app = File.join(user_home, 'Library', 'Input Methods', 'Seamtype.app')
  scripts = File.join(fixture, 'scripts')
  bin = File.join(fixture, 'bin')
  FileUtils.mkdir_p([system_app, scripts, bin])
  %w[get.sh install.sh].each do |name|
    source = File.read(File.join(repo, 'scripts', name))
      .gsub('/Library/Input Methods/Seamtype.app', system_app)
      .gsub('$HOME', user_home)
    path = File.join(scripts, name)
    File.write(path, source)
    _, error, status = Open3.capture3(name == 'get.sh' ? 'sh' : 'zsh', path)
    raise "#{name} did not reject the other installation: #{error}" unless status.exitstatus == 1 && error.include?('already installed')
  end

  File.write(File.join(bin, 'stat'), "#!/bin/sh\nprintf '%s\\n' fixtureuser\n")
  File.write(File.join(bin, 'dscl'), "#!/bin/sh\nprintf '%s\\n' #{Shellwords.escape("NFSHomeDirectory: #{user_home}")}\n")
  stopped = File.join(fixture, 'stopped')
  File.write(File.join(bin, 'pkill'), "#!/bin/sh\ntouch #{Shellwords.escape(stopped)}\n")
  FileUtils.chmod(0755, %w[stat dscl pkill].map { |name| File.join(bin, name) })
  env = { 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" }
  preinstall = File.join(repo, 'scripts', 'pkg', 'preinstall')
  _, error, status = Open3.capture3(env, 'sh', preinstall)
  raise "pkg rejected a clean installation: #{error}" unless status.success?
  raise 'pkg did not stop the old process before an update' unless File.exist?(stopped)
  File.delete(stopped)
  FileUtils.mkdir_p(user_app)
  _, error, status = Open3.capture3(env, 'sh', preinstall)
  raise "pkg did not reject the user's installation: #{error}" unless status.exitstatus == 1 && error.include?('already installed')
  raise 'pkg stopped the old process despite rejecting installation' if File.exist?(stopped)
  File.write(File.join(bin, 'dscl'), "#!/bin/sh\nexit 1\n")
  _, _, status = Open3.capture3(env, 'sh', preinstall)
  raise 'pkg ignored a failed home-directory lookup' unless status.exitstatus == 1
end
puts 'Installer conflict checks passed.'
