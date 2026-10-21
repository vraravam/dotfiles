# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# States that are normal on a vanilla macOS (empty ~/.ssh, directories and plugin files that the
# clones create later) must not print a warning during a first install, while the same states on a
# configured machine still do. The code under test is cut out of the real files and run in zsh with
# small stubs, so nothing outside the temp directory is touched.
RSpec.describe 'warnings that are expected on a first install' do
  def repo_file(*parts)
    File.expand_path(File.join('..', *parts), __dir__)
  end

  # The text of the function +name+ (from its first line to the closing brace at column 0).
  def function_text(file, name)
    lines = File.read(file).lines
    start = lines.index { |line| line.start_with?("#{name}() {") }
    stop = (start...lines.length).find { |i| lines[i] == "}\n" }
    lines[start..stop].join
  end

  def run_zsh(script, first_install:)
    env = { 'FIRST_INSTALL' => first_install ? '1' : '' }
    out, err, status = Open3.capture3(env, 'zsh', '-c', script)
    raise "zsh failed: #{err}" unless status.success?

    out + err
  end

  let(:stubs) do
    <<~ZSH
      is_first_install() { [[ -n ${FIRST_INSTALL:-} ]]; }
      is_directory() { [[ -d $1 ]]; }
      is_file() { [[ -f $1 ]]; }
      warn() { print -r -- "WARN $*"; }
      info() { print -r -- "INFO $*"; }
      yellow() { print -r -- "$*"; }
      cyan() { print -r -- "$*"; }
    ZSH
  end

  describe 'find_in_folder_and_recompile (.zlogin) with a missing directory' do
    let(:function) { function_text(repo_file('files', '--ZDOTDIR--', '.zlogin'), 'find_in_folder_and_recompile') }

    it 'warns on a configured machine' do
      out = run_zsh("#{stubs}\n#{function}\nfind_in_folder_and_recompile /nonexistent/dir", first_install: false)

      expect(out).to match(%r{WARN Directory '/nonexistent/dir' not found for zsh script recompilation})
    end

    it 'is silent on a first install' do
      out = run_zsh("#{stubs}\n#{function}\nfind_in_folder_and_recompile /nonexistent/dir", first_install: true)

      expect(out).to eq('')
    end
  end

  describe '_secure_folder_permissions (.shellrc) with an empty folder' do
    let(:function) { function_text(repo_file('files', '--HOME--', '.shellrc'), '_secure_folder_permissions') }

    it 'reports it as information, never as a warning' do
      Dir.mktmpdir('secure-perms-spec-') do |dir|
        script = <<~ZSH
          #{stubs}
          ensure_dir_exists() { mkdir -p "$1"; }
          is_directory_empty() { [[ -z "$(ls -A "$1")" ]]; }
          success() { print -r -- "SUCCESS $*"; }
          #{function}
          _secure_folder_permissions #{dir}/.ssh
        ZSH

        out = run_zsh(script, first_install: true)

        expect(out).to include("INFO '#{dir}/.ssh' exists but is empty")
        expect(out).not_to include('WARN')
      end
    end
  end

  describe 'the antidote bundle check (.zshrc)' do
    let(:source) { File.read(repo_file('files', '--ZDOTDIR--', '.zshrc')) }

    it 'warns about missing bundle files only when this is not a first install' do
      expect(source).to match(/^elif ! is_first_install; then\n(?:.*\n){0,3}\s*warn "antidote: either/)
    end
  end
end
