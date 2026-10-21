# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'pathname'

# Runs implode (files/--ZDOTDIR--/.aliases) against a throwaway HOME. Every system command it
# uses (crontab, security, ssh-add, the system Ruby) is a stub that only records its call, and
# sudo just runs the command it is given, so nothing outside the temp directory can be touched.
RSpec.describe 'implode' do
  let(:aliases) { File.expand_path('../files/--ZDOTDIR--/.aliases', __dir__) }

  def function_body
    lines = File.read(aliases).lines
    start = lines.index { |l| l.start_with?('implode() {') }
    stop = lines.index { |l| l.start_with?('# 3m. Project-specific helpers') }
    # Everything up to (not including) the divider comment that follows the closing brace.
    "#{lines[start...stop].join.sub(/\n# -+\n\z/, "\n")}\n"
  end

  # Builds a tree, runs implode and returns [surviving files (relative), calls log lines, stderr].
  def run_implode(login_item_script: true)
    Dir.mktmpdir('implode-spec-') do |dir|
      root = Pathname(dir)
      files = %w[
        home/.zshenv home/.ssh/id_ed25519 home/.config/dotfiles/Brewfile home/.config/zsh/.aliases
        home/personal/dev/bin/x home/dev/repo/a home/Brewfile home/anti/p home/old.log
        home/Downloads/unshallow-batch.log home/Downloads/brew-bundle-full-install.log home/Documents/keep.txt
        home/.Trash/keep.txt tmp/crontab_backup tmp/crontab_backup.new tmp/other-file
      ]
      files << 'home/.config/dotfiles/scripts/setup-login-item.rb' if login_item_script
      files.each do |rel|
        path = root.join(rel)
        path.dirname.mkpath
        path.write('x')
      end
      log = root.join('calls.log')
      script = <<~ZSH
        calls() { print -r -- "$*" >> #{log}; }
        crontab() { calls "crontab $*"; }
        security() { calls "security $*"; }
        ssh-add() { calls "ssh-add $*"; }
        sudo() { "$@"; }
        function /usr/bin/ruby { calls "ruby $* [dotfiles present: $([[ -d ${DOTFILES_DIR} ]] && print yes || print no)]"; }
        is_zero_string() { [[ -z $1 ]]; }
        is_root_dir() { [[ $1 == / ]]; }
        is_file() { [[ -f $1 ]]; }
        is_non_empty_array() { eval "(( ${#${1}[@]} > 0 ))"; }
        warn() { print -u2 -r -- "WARN $*"; }
        error() { print -u2 -r -- "ERR $*"; }
        cyan() { print -r -- "$*"; }
        #{function_body}
        implode
      ZSH
      env = {
        'HOME' => "#{dir}/home", 'USER' => 'nobody', 'TMPDIR' => "#{dir}/tmp/",
        'DOTFILES_DIR' => "#{dir}/home/.config/dotfiles", 'PERSONAL_CONFIGS_DIR' => "#{dir}/home/personal/dev/configs",
        'PERSONAL_PROFILES_DIR' => "#{dir}/home/personal/profiles", 'ANTIDOTE_HOME' => "#{dir}/home/anti",
        'ANTIDOTE_PLUGIN_ZSH' => "#{dir}/home/anti/p.zsh", 'HOMEBREW_BUNDLE_FILE' => "#{dir}/home/Brewfile",
        'PROJECTS_BASE_DIR' => "#{dir}/home/dev", '_DOTFILES_CRON_BACKUP_FILE' => nil, 'SSH_AUTH_SOCK' => nil
      }
      _out, err, status = Open3.capture3(env, 'zsh', '-c', script)
      raise "zsh failed (#{status.exitstatus}): #{err}" unless status.success?

      calls = log.file? ? log.read.lines.map(&:chomp) : []
      survivors = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select { |p| File.file?(p) }.map { |p| p.sub("#{dir}/", '') }.sort
      [survivors - ['calls.log'], calls, err]
    end
  end

  it 'clears the crontab before anything else' do
    _survivors, calls, = run_implode

    expect(calls.first).to eq('crontab -r')
  end

  it 'removes the managed login items while the dotfiles still exist' do
    _survivors, calls, = run_implode

    expect(calls.grep(/\Aruby /)).to match([%r{\Aruby .*/\.config/dotfiles/scripts/setup-login-item\.rb --remove-managed \[dotfiles present: yes\]\z}])
  end

  it 'warns, and carries on, when the login item script is already gone' do
    survivors, calls, err = run_implode(login_item_script: false)

    expect(calls.grep(/\Aruby /)).to be_empty
    expect(err).to match(/Not removing login items/)
    expect(survivors.grep(/\.zshenv|personal|dev/)).to be_empty
  end

  it 'deletes the stale crontab backup (and its .new sibling) but nothing else in TMPDIR' do
    survivors, = run_implode

    expect(survivors.grep(%r{\Atmp/})).to eq(%w[tmp/other-file])
  end

  it 'keeps the log files under Downloads that the scripts refer to, and personal files outside the wipe' do
    survivors, = run_implode

    expect(survivors).to include('home/Downloads/unshallow-batch.log', 'home/Downloads/brew-bundle-full-install.log', 'home/Documents/keep.txt', 'home/.Trash/keep.txt')
    expect(survivors).not_to include('home/old.log')
  end

  it 'still wipes the dot files, the personal folders and the project folders' do
    survivors, = run_implode

    expect(survivors.grep(%r{\Ahome/(\.[a-z]|personal|dev|anti|Brewfile)})).to be_empty
  end
end
