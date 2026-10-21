# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

# Runs the real _prompt_git_size hook of files/--ZDOTDIR--/.zshrc in zsh against a throwaway repository
# layout, with a fake 'git' on PATH that records every call, so only the caching decisions are under test:
# when git is forked, what is written to ${XDG_CACHE_HOME}/git-size, and what a new shell reads back.
RSpec.describe '_prompt_git_size (.zshrc)' do
  let(:zshrc) { File.expand_path('../files/--ZDOTDIR--/.zshrc', __dir__) }

  # The text of the function (from its first line to the closing brace at the same indentation).
  let(:function_text) do
    lines = File.read(zshrc).lines
    start = lines.index { |line| line.start_with?('  _prompt_git_size() {') }
    stop = (start...lines.length).find { |i| lines[i] == "  }\n" }
    lines[start..stop].join
  end

  around do |example|
    Dir.mktmpdir('git-size-spec-') do |dir|
      @root = Pathname(dir).realpath
      example.run
    end
  end

  let(:repo) { @root.join('repo') }
  let(:cache_dir) { @root.join('cache') }
  let(:bin) { @root.join('bin') }
  let(:git_log) { @root.join('git.log') }
  let(:cache_file) { cache_dir.join('git-size', repo.to_s.tr('/', '-')) }

  before do
    repo.join('.git', 'objects', 'pack').mkpath
    bin.mkpath
    bin.join('git').write("#!/bin/sh\necho \"git $*\" >> #{git_log}\nprintf '%s' \"$FAKE_GIT_OUTPUT\"\n")
    bin.join('git').chmod(0o755)
    touch_pack_dir('202401010000')
  end

  def touch_pack_dir(stamp)
    FileUtils.touch(repo.join('.git', 'objects', 'pack').to_s, mtime: Time.strptime(stamp, '%Y%m%d%H%M'))
  end

  # One new zsh process (= one new shell): runs the hook +calls+ times from +cwd+, prints the segment value.
  def shell(calls: 1, cwd: repo, output: "count: 3\nsize-pack: 2.63 MiB\n")
    script = <<~ZSH
      zmodload -F zsh/stat b:zstat
      typeset -g _prompt_git_size_key='' _prompt_git_size_val=''
      #{function_text}
      cd #{cwd}
      repeat #{calls}; do _prompt_git_size; done
      print -r -- "segment=${_STARSHIP_GIT_SIZE-UNSET}"
    ZSH
    env = { 'XDG_CACHE_HOME' => cache_dir.to_s, 'PATH' => "#{bin}:#{ENV.fetch('PATH')}", 'FAKE_GIT_OUTPUT' => output }
    out, err, status = Open3.capture3(env, 'zsh', '-fc', script)
    raise "zsh failed: #{err}" unless status.success?

    out.lines.map(&:chomp).grep(/\Asegment=/).first.delete_prefix('segment=')
  end

  def git_calls
    git_log.file? ? git_log.read.lines.length : 0
  end

  it 'asks git once in a new shell and remembers the answer in a file' do
    expect(shell).to eq('2.63 MiB')

    expect(git_calls).to eq(1)
    expect(cache_file.read).to eq("#{repo}:#{File.mtime(repo.join('.git', 'objects', 'pack')).to_i}\n2.63 MiB\n")
  end

  it 'does not ask git again within the same shell' do
    shell(calls: 3)

    expect(git_calls).to eq(1)
  end

  it 'does not fork git in a later shell while the pack directory is unchanged' do
    shell
    out = shell(output: 'WRONG')

    expect(out).to eq('2.63 MiB')
    expect(git_calls).to eq(1)
  end

  it 'asks git again, and rewrites the file, when the pack directory changed' do
    shell
    touch_pack_dir('202402020000')

    expect(shell(output: "size-pack: 9.00 MiB\n")).to eq('9.00 MiB')
    expect(git_calls).to eq(2)
    expect(cache_file.read).to end_with("\n9.00 MiB\n")
  end

  it 'treats a partial file (key without a size) as a miss' do
    cache_file.dirname.mkpath
    cache_file.write("#{repo}:#{File.mtime(repo.join('.git', 'objects', 'pack')).to_i}\n")

    expect(shell).to eq('2.63 MiB')
    expect(git_calls).to eq(1)
  end

  it 'never caches an empty size (a failed git must not poison later shells)' do
    expect(shell(output: '')).to eq('')
    expect(cache_file).not_to exist

    shell
    expect(git_calls).to eq(2)
  end

  it 'works when the cache directory cannot be written' do
    FileUtils.touch(cache_dir.to_s) # a file where the directory should be

    expect(shell).to eq('2.63 MiB')
    expect(shell).to eq('2.63 MiB')
    expect(git_calls).to eq(2)
  end

  it 'hides the segment outside a repository' do
    outside = @root.join('plain')
    outside.mkpath

    expect(shell(cwd: outside)).to eq('UNSET')
    expect(git_calls).to eq(0)
  end

  it 'keeps one file per repository' do
    other = @root.join('other')
    other.join('.git', 'objects', 'pack').mkpath
    shell
    shell(cwd: other, output: "size-pack: 1.00 MiB\n")

    expect(cache_dir.join('git-size').children.length).to eq(2)
  end
end
