# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'git_overrides'

RSpec.describe GitOverrides do
  let(:bin_dir) { Pathname(Dir.mktmpdir) }

  before do
    stub_const('EnvVars::PERSONAL_BIN_DIR', bin_dir)
    adjust_path(bin_dir)
  end
  after { FileUtils.remove_entry(bin_dir) }

  def make_script(name, executable: true)
    path = bin_dir.join(name)
    path.write("#!/bin/sh\n")
    path.chmod(executable ? 0o755 : 0o644)
    path
  end

  describe '.script_for' do
    it 'finds an executable .sh override named after the repo directory when override is not skipped' do
      with_env(GitOverrides::SKIP_ENV_VAR => nil) do
        script = make_script('cc-my-repo.sh')

        allow(CommandUtils).to receive(:query).with('which', 'cc-my-repo.rb').and_return(nil)
        allow(CommandUtils).to receive(:query).with('which', script.basename.to_s).and_return(script.expand_path)

        expect(described_class.script_for('cc', '/some/where/my-repo')).to eq(script)
      end
    end

    it 'prefers a .rb override over a .sh override when override is not skipped' do
      with_env(GitOverrides::SKIP_ENV_VAR => 'true') do
        make_script('cc-my-repo.sh')
        ruby_script = make_script('cc-my-repo.rb')

        allow(CommandUtils).to receive(:query).with('which', ruby_script.basename.to_s).and_return(ruby_script.expand_path)

        expect(described_class.script_for('cc', '/x/my-repo')).to eq(ruby_script)
      end
    end

    it 'ignores a script that is not executable when override is not skipped' do
      with_env(GitOverrides::SKIP_ENV_VAR => nil) do
        ruby_script = make_script('cc-my-repo.rb', executable: false)

        allow(CommandUtils).to receive(:query).with('which', ruby_script.basename.to_s).and_return(ruby_script.expand_path)
        allow(CommandUtils).to receive(:query).with('which', 'cc-my-repo.sh').and_return(nil)

        expect(described_class.script_for('cc', '/x/my-repo')).to be_nil
      end
    end

    it 'is nil when no override exists for that command' do
      make_script('push-my-repo.rb')

      expect(described_class.script_for('cc', '/x/my-repo')).to be_nil
    end

    it 'matches on the directory basename, not the full path' do
      script = make_script('pull-repo.rb')

      allow(CommandUtils).to receive(:query).with('which', script.basename.to_s).and_return(script.expand_path)

      expect(described_class.script_for('pull', '/a/b/repo')).to eq(script)

      allow(CommandUtils).to receive(:query).with('which', 'pull-other.rb').and_return(nil)
      allow(CommandUtils).to receive(:query).with('which', 'pull-other.sh').and_return(nil)

      expect(described_class.script_for('pull', '/a/b/other')).to be_nil
    end
  end

  describe '.command_for' do
    it 'runs a .rb script with the current interpreter (without RubyGems) rather than its shebang' do
      expect(described_class.command_for('/bin/x.rb')).to eq([RbConfig.ruby, '--disable-gems', '/bin/x.rb'])
    end

    it 'runs any other script directly' do
      expect(described_class.command_for(Pathname('/bin/x.sh'))).to eq(['/bin/x.sh'])
    end
  end

  describe '.argv_for' do
    it 'leads with the env hash (skip flag and RUBYLIB), then the command, then the args' do
      with_env('RUBYLIB' => nil) do
        env, *rest = described_class.argv_for('/bin/x.sh', %w[--force a])

        expect(env).to eq(described_class::SKIP_ENV_VAR => '1', 'RUBYLIB' => described_class.rubylib)
        expect(rest).to eq(['/bin/x.sh', '--force', 'a'])
      end
    end

    it 'does not mutate the shared SKIP_ENV constant' do
      described_class.argv_for('/bin/x.sh', [])

      expect(described_class::SKIP_ENV).to eq(described_class::SKIP_ENV_VAR => '1')
      expect(described_class::SKIP_ENV).to be_frozen
    end
  end

  describe '.rubylib' do
    it 'puts the shared utilities directory first and keeps any existing RUBYLIB' do
      with_env('RUBYLIB' => '/existing') do
        parts = described_class.rubylib.split(File::PATH_SEPARATOR)

        expect(parts.first).to end_with(File.join('scripts', 'utilities'))
        expect(parts.last).to eq('/existing')
      end
    end

    it 'has just the utilities directory when RUBYLIB is unset' do
      with_env('RUBYLIB' => nil) do
        expect(described_class.rubylib.split(File::PATH_SEPARATOR).size).to eq(1)
      end
    end
  end

  describe '.skip?' do
    it 'is true when the skip variable is set to a non-empty value' do
      with_env(described_class::SKIP_ENV_VAR => '1') { expect(described_class.skip?).to be true }
    end

    it 'is false when the variable is unset or empty' do
      allow(CommandUtils).to receive(:query).with('which', anything).and_return(nil).times
      with_env(described_class::SKIP_ENV_VAR => nil) { expect(described_class.skip?).to be false }
      with_env(described_class::SKIP_ENV_VAR => '') { expect(described_class.skip?).to be false }
      with_env(described_class::SKIP_ENV_VAR => '  ') { expect(described_class.skip?).to be false }
    end
  end
end
