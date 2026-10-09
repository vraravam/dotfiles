# frozen_string_literal: true

require 'tmpdir'
require 'git_hooks'

RSpec.describe GitHooks do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def git(*args)
    system('git', *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(' ')} failed")
  end

  def init_repo
    git('init', '-q', '.')
    git('config', 'user.email', 'spec@example.com')
    git('config', 'user.name', 'spec')
  end

  def write_hook(path, body, mode: 0o755)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(mode, path)
  end

  describe '._staged_files' do
    it 'returns staged names intact, including spaces and non-ASCII characters' do
      init_repo
      File.write('with space.rb', "puts 1\n")
      File.write("caf\u00e9.rb", "puts 2\n")
      git('add', '.')

      expect(described_class.send(:_staged_files)).to contain_exactly('with space.rb', "caf\u00e9.rb")
    end

    it 'excludes deleted files' do
      init_repo
      File.write('gone.rb', "puts 1\n")
      git('add', '.')
      git('commit', '-q', '-m', 'x', '--no-verify')
      git('rm', '-q', 'gone.rb')

      expect(described_class.send(:_staged_files)).to be_empty
    end
  end

  describe '._syntax_check' do
    it 'passes valid Ruby files on for RuboCop and reports no failures' do
      File.write('ok.rb', "puts 1\n")

      ruby_files, failures = described_class.send(:_syntax_check, ['ok.rb'])

      expect(ruby_files).to eq(['ok.rb'])
      expect(failures).to be_empty
    end

    it 'reports a Ruby syntax error and does not pass that file to RuboCop' do
      File.write('bad file.rb', "def x(\n")

      ruby_files, failures = described_class.send(:_syntax_check, ['bad file.rb'])

      expect(ruby_files).to be_empty
      expect(failures).to eq(['Ruby syntax error in bad file.rb'])
    end

    it 'reports a shell syntax error' do
      File.write('bad.sh', "if then\n")

      _ruby_files, failures = described_class.send(:_syntax_check, ['bad.sh'])

      expect(failures).to eq(['Shell syntax error in bad.sh'])
    end

    it 'skips files that no longer exist in the working tree and files of other types' do
      File.write('notes.txt', "if then\n")

      ruby_files, failures = described_class.send(:_syntax_check, %w[missing.rb notes.txt])

      expect(ruby_files).to be_empty
      expect(failures).to be_empty
    end
  end

  describe '._run_local_hooks' do
    before { allow(GitOverrides).to receive(:script_for).and_return(nil) }

    it 'succeeds when there are no local hooks' do
      expect(described_class.send(:_run_local_hooks, 'pre-push', [])).to be true
    end

    it 'passes the arguments and replays stdin to the hook' do
      write_hook('.git/hooks.local/pre-push', 'echo "$@ $(cat)" > out.txt')

      described_class.send(:_run_local_hooks, 'pre-push', %w[origin url], stdin_data: "refs\n")

      expect(File.read('out.txt')).to eq("origin url refs\n")
    end

    it 'fails, and runs no further hooks, when a hook exits non-zero' do
      write_hook('.git/hooks.local/pre-push', 'exit 3')
      override = Pathname.new(File.expand_path('override.sh'))
      write_hook(override.to_s, 'touch ran-override')
      allow(GitOverrides).to receive(:script_for).and_return(override)

      expect(described_class.send(:_run_local_hooks, 'pre-push', [])).to be false
      expect(File).not_to exist('ran-override')
    end

    it 'ignores a hook that is not executable' do
      write_hook('.git/hooks.local/pre-push', 'exit 3', mode: 0o644)

      expect(described_class.send(:_run_local_hooks, 'pre-push', [])).to be true
    end
  end

  describe '.pre_commit' do
    before { allow(GitOverrides).to receive(:script_for).and_return(nil) }

    it 'allows a commit with nothing staged' do
      init_repo

      expect(described_class.pre_commit([])).to be true
    end

    it 'blocks a commit that stages a Ruby file with a syntax error' do
      init_repo
      File.write('bad.rb', "def x(\n")
      git('add', '.')

      expect { @result = described_class.pre_commit([]) }.to output(/Syntax validation failed/).to_stdout
      expect(@result).to be false
    end
  end
end
