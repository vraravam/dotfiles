# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../scripts/run-all'

# Exercises RunAll in module mode (as software-updates-cron.rb and ${PERSONAL_BIN_DIR} overrides
# use it), i.e. without the script-only 'include Logging' of the CLI block at the bottom of run-all.rb.
RSpec.describe RunAll do
  around do |example|
    Dir.mktmpdir('run-all-spec-') do |dir|
      @tmp = Pathname(dir).realpath
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:bin_dir) { tmp.join('bin').tap(&:mkpath) }

  def make_repo(*parts)
    tmp.join('work', *parts, '.git').mkpath
    tmp.join('work', *parts)
  end

  def quietly
    out = $stdout
    err = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = out
    $stderr = err
  end

  before do
    Logging.state.reset!
    stub_const('EnvVars::PERSONAL_BIN_DIR', bin_dir)
    adjust_path(bin_dir)
    stub_const('EnvVars::SHELL', '/bin/sh')
    GitProcessor.repo_cache = {}
  end

  describe '.run' do
    it 'raises for an empty command (rather than a NoMethodError from a missing Core helper)' do
      expect { quietly { described_class.run(command: []) } }.to raise_error(RuntimeError, /Missing required argument: command/)
    end

    it 'runs the command inside each repo directory without changing the working directory' do
      repo_a = make_repo('a')
      repo_b = make_repo('b')
      before_dir = Dir.pwd

      with_env(GitOverrides::SKIP_ENV_VAR => '') do
        ok = quietly { described_class.run(command: %w[touch marker], folder: tmp.join('work').to_s, mindepth: 1, maxdepth: 2) }

        expect(ok).to be true
      end

      expect(repo_a.join('marker')).to exist
      expect(repo_b.join('marker')).to exist
      expect(Dir.pwd).to eq(before_dir)
    end

    it 'returns false and records a warning when the command fails in a repo' do
      make_repo('a')
      expect(Logging).to receive(:record_warning).with(/Command failed in/)

      with_env(GitOverrides::SKIP_ENV_VAR => '') do
        ok = quietly { described_class.run(command: %w[false], folder: tmp.join('work').to_s, mindepth: 1, maxdepth: 2) }

        expect(ok).to be false
      end
    end
  end

  describe 'override lookup' do
    def make_override(name)
      bin_dir.join(name).tap do |path|
        path.write("#!/bin/sh\n")
        path.chmod(0o755)
      end
    end

    it 'looks up a git subcommand by its own name, and any other command by the command name' do
      expect(GitOverrides).to receive(:script_for).with('cc', '/x/repo').and_return(nil)
      expect(GitOverrides).to receive(:script_for).with('ls', '/x/repo').and_return(nil)

      described_class.send(:_override_script_for, command: %w[git cc], dir: '/x/repo')
      described_class.send(:_override_script_for, command: %w[ls -la], dir: '/x/repo')
    end

    it 'finds nothing for an empty command' do
      expect(described_class.send(:_override_script_for, command: [], dir: '/x/repo')).to be_nil
    end

    it 'runs the user shell when there is no override' do
      folder = 'repo1'
      with_env(GitOverrides::SKIP_ENV_VAR => '') do
        argv = described_class.send(:_resolve_exec_command, command: %w[git status -s], dir: tmp.join(folder).to_s)

        expect(argv).to eq(['/bin/sh', '-c', 'git status -s'])
      end
    end

    it 'runs the override (env hash first, only the extra args after it) when one exists' do
      folder = 'repo2'
      script = make_override("cc-#{folder}.sh")

      # Mock _override_script_for to return script, simulating skip mode where overrides are looked up & exist
      allow(described_class).to receive(:_override_script_for).and_return(script)
      allow(CommandUtils).to receive(:query).with('which', anything).and_return(nil)

      allow(Logging).to receive(:info)

      with_env(GitOverrides::SKIP_ENV_VAR => nil) do
        env, *rest = described_class.send(:_resolve_exec_command, command: %w[git cc --expire=now], dir: tmp.join(folder).to_s)

        expect(env).to include(GitOverrides::SKIP_ENV_VAR => '1')
        expect(rest).to eq([script.to_s, '--expire=now'])
      end
    end

    it 'does not look for an override when already inside one' do
      folder = 'repo3'
      make_override("cc-#{folder}.sh")

      with_env(GitOverrides::SKIP_ENV_VAR => '1') do
        argv = described_class.send(:_resolve_exec_command, command: %w[git cc], dir: tmp.join(folder).to_s)

        expect(argv).to eq(['/bin/sh', '-c', 'git cc'])
      end
    end
  end
end
