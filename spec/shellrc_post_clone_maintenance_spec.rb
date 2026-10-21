# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# Exercises _post_clone_maintenance from files/--HOME--/.shellrc through a real zsh, with git and
# the reftable migration replaced by logging stubs, so that only the decision logic is under test.
RSpec.describe '.shellrc _post_clone_maintenance' do
  let(:shellrc) { File.expand_path('../files/--HOME--/.shellrc', __dir__) }

  # Runs _post_clone_maintenance for +folder+ and returns the log of stubbed calls (one per line).
  def run_maintenance(folder:, first_install:)
    Dir.mktmpdir('post-clone-maint-spec-') do |home|
      bin = File.join(home, 'bin')
      Dir.mkdir(bin)
      File.write(File.join(bin, 'git-maintain'), "#!/bin/sh\n") # only has to exist on PATH
      File.chmod(0o755, File.join(bin, 'git-maintain'))
      log = File.join(home, 'calls.log')
      dotfiles = File.join(home, 'dotfiles')
      script = <<~ZSH
        source #{shellrc}
        # .shellrc (re)defines DOTFILES_DIR itself, so pin it and the stubs after sourcing.
        DOTFILES_DIR=#{dotfiles}
        git() {
          if [[ "$1" == config && "$2" == --get ]]; then return 0; fi
          print -r -- "git ${*}" >>#{log}
        }
        migrate_git_repo_to_reftable() { print -r -- "migrate ${1}" >>#{log}; }
        _post_clone_maintenance #{folder == :dotfiles ? dotfiles : File.join(home, 'other-repo')}
      ZSH
      env = {
        'HOME' => home,
        'PATH' => "#{bin}:#{ENV.fetch('PATH')}",
        'FIRST_INSTALL' => (first_install ? '1' : '')
      }
      _out, err, status = Open3.capture3(env, 'zsh', '-c', script)
      raise "zsh failed: #{err}" unless status.success?

      File.exist?(log) ? File.read(log).lines.map { |l| l.strip.sub(home, '<home>') } : []
    end
  end

  it 'skips unshallow/maintain/siu (but still migrates reftable) for a non-dotfiles repo on FIRST_INSTALL' do
    calls = run_maintenance(folder: :other, first_install: true)

    expect(calls).to eq(['migrate <home>/other-repo'])
  end

  it 'runs the full chain for DOTFILES_DIR on FIRST_INSTALL' do
    calls = run_maintenance(folder: :dotfiles, first_install: true)

    expect(calls).to eq(
      [
        'migrate <home>/dotfiles',
        'git -C <home>/dotfiles unshallow',
        'git -C <home>/dotfiles maintain',
        'git -C <home>/dotfiles siu',
      ]
    )
  end

  it 'runs the full chain for any repo when it is not a first install' do
    calls = run_maintenance(folder: :other, first_install: false)

    expect(calls).to eq(
      [
        'migrate <home>/other-repo',
        'git -C <home>/other-repo unshallow',
        'git -C <home>/other-repo maintain',
        'git -C <home>/other-repo siu',
      ]
    )
  end
end
