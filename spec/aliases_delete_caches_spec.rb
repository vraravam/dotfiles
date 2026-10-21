# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'pathname'

# Exercises the file-deletion half of delete_caches (files/--ZDOTDIR--/.aliases) against a
# throwaway tree. The tail of the function (re-sourcing .zlogin, zcompile) is cut off and the
# small helpers it uses are stubbed, so nothing outside the temp directory is touched.
RSpec.describe 'delete_caches' do
  let(:aliases) { File.expand_path('../files/--ZDOTDIR--/.aliases', __dir__) }

  def function_body
    lines = File.read(aliases).lines
    start = lines.index { |l| l.start_with?('delete_caches() {') }
    stop = lines.index { |l| l.include?('Re-source .zlogin') }
    "#{lines[start...stop].join}}\n"
  end

  # Builds the tree, runs delete_caches and returns the sorted list of surviving files (relative).
  def survivors(first_install: false)
    Dir.mktmpdir('delete-caches-spec-') do |dir|
      root = Pathname(dir)
      %w[
        home/.shellrc.zwc home/.zshenv.zwc home/.shellrc
        home/.config/zsh/lib/a.zsh.zwc home/.config/dotfiles/scripts/x.sh.zwc
        home/.cache/zcompdump.zwc home/.cache/foo.zsh home/.cache/bat/inner
        home/.cache/dev-environment-setup-stamp home/.cache/bat-cache-last-update
        home/.cache/mise/x/y home/.cache/mise/x/y-stamp
        home/dev/r/a.zwc home/dev/r/node_modules/keep.zwc home/dev/r/.git/keep.zwc
        brew/Cellar/f/1/share/f/c.zsh.zwc brew/bin/b.sh.zwc home/pbin/p.zwc home/anti/q.zwc
      ].each do |rel|
        path = root.join(rel)
        path.dirname.mkpath
        path.write('x')
      end
      script = <<~ZSH
        is_directory() { [[ -d $1 ]]; }
        is_non_zero_string() { [[ -n $1 ]]; }
        is_first_install() { [[ -n ${FIRST_INSTALL:-} ]]; }
        _is_direct_child_of_root() { return 1; }
        ensure_dir_exists() { mkdir -p "$1"; }
        warn() { print -u2 -r -- "WARN $*"; }
        info() { :; }
        cyan() { print -r -- "$*"; }
        error() { print -u2 -r -- "ERR $*"; }
        #{function_body}
        delete_caches
      ZSH
      env = {
        'HOME' => "#{dir}/home", 'XDG_CONFIG_HOME' => "#{dir}/home/.config", 'XDG_CACHE_HOME' => "#{dir}/home/.cache",
        'PERSONAL_BIN_DIR' => "#{dir}/home/pbin", 'PROJECTS_BASE_DIR' => "#{dir}/home/dev",
        'ANTIDOTE_HOME' => "#{dir}/home/anti", 'HOMEBREW_PREFIX' => "#{dir}/brew",
        'FIRST_INSTALL' => (first_install ? '1' : '')
      }
      _out, err, status = Open3.capture3(env, 'zsh', '-c', script)
      raise "zsh failed: #{err}" unless status.success?

      expect(err).to eq('')

      Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select { |p| File.file?(p) }.map { |p| p.sub("#{dir}/", '') }.sort
    end
  end

  it 'deletes every *.zwc file in the known roots but keeps .git/node_modules contents' do
    expect(survivors.grep(/\.zwc/)).to eq(%w[home/dev/r/.git/keep.zwc home/dev/r/node_modules/keep.zwc])
  end

  it 'wipes cache files but keeps *stamp* and *last-update* files (also in sub-directories)' do
    expect(survivors.grep(%r{\Ahome/\.cache/})).to eq(
      %w[home/.cache/bat-cache-last-update home/.cache/dev-environment-setup-stamp home/.cache/mise/x/y-stamp]
    )
  end

  it 'leaves unrelated files alone' do
    expect(survivors).to include('home/.shellrc')
  end

  it 'skips the cache wipe on FIRST_INSTALL but still deletes *.zwc files' do
    result = survivors(first_install: true)

    expect(result).to include('home/.cache/foo.zsh', 'home/.cache/bat/inner')
    expect(result.grep(/\.zwc/)).to eq(%w[home/dev/r/.git/keep.zwc home/dev/r/node_modules/keep.zwc])
  end
end
