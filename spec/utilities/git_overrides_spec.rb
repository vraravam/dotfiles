# frozen_string_literal: true

require 'tmpdir'
require 'git_overrides'

RSpec.describe GitOverrides do
  let(:bin_dir) { Pathname.new(Dir.mktmpdir) }

  before { stub_const('EnvVars::PERSONAL_BIN_DIR', bin_dir) }
  after { FileUtils.remove_entry(bin_dir) }

  def make_script(name, executable: true)
    path = bin_dir.join(name)
    path.write("#!/bin/sh\n")
    path.chmod(executable ? 0o755 : 0o644)
    path
  end

  describe '.script_for' do
    it 'finds an executable .sh override named after the repo directory' do
      script = make_script('cc-my-repo.sh')

      expect(described_class.script_for('cc', '/some/where/my-repo')).to eq(script)
    end

    it 'prefers a .rb override over a .sh override' do
      make_script('cc-my-repo.sh')
      ruby_script = make_script('cc-my-repo.rb')

      expect(described_class.script_for('cc', '/x/my-repo')).to eq(ruby_script)
    end

    it 'ignores a script that is not executable' do
      make_script('cc-my-repo.rb', executable: false)

      expect(described_class.script_for('cc', '/x/my-repo')).to be_nil
    end

    it 'is nil when no override exists for that command' do
      make_script('push-my-repo.rb')

      expect(described_class.script_for('cc', '/x/my-repo')).to be_nil
    end

    it 'matches on the directory basename, not the full path' do
      script = make_script('pull-repo.rb')

      expect(described_class.script_for('pull', '/a/b/repo')).to eq(script)
      expect(described_class.script_for('pull', '/a/b/other')).to be_nil
    end
  end

  describe '.command_for' do
    it 'runs a .rb script with the current interpreter rather than its shebang' do
      expect(described_class.command_for('/bin/x.rb')).to eq([RbConfig.ruby, '/bin/x.rb'])
    end

    it 'runs any other script directly' do
      expect(described_class.command_for(Pathname.new('/bin/x.sh'))).to eq(['/bin/x.sh'])
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
      with_env(described_class::SKIP_ENV_VAR => nil) { expect(described_class.skip?).to be false }
      with_env(described_class::SKIP_ENV_VAR => '') { expect(described_class.skip?).to be false }
    end
  end
end
