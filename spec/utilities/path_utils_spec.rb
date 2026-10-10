# frozen_string_literal: true

require 'path_utils'
require 'tmpdir'

RSpec.describe PathUtils do
  around do |example|
    Dir.mktmpdir('path-utils-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }

  describe '.root_dir?' do
    it 'is true only for "/"' do
      expect(described_class.root_dir?('/')).to be true
      expect(described_class.root_dir?('/usr')).to be false
      expect(described_class.root_dir?(nil)).to be false
      expect(described_class.root_dir?('')).to be false
    end
  end

  describe '.valid_directory?' do
    it 'is true for an existing directory' do
      expect(described_class.valid_directory?(tmp)).to be true
      expect(described_class.valid_directory?(tmp.to_s)).to be true
    end

    it 'is false for nil, empty, root, a missing path and a file' do
      file = tmp.join('f')
      file.write('x')

      expect(described_class.valid_directory?(nil)).to be false
      expect(described_class.valid_directory?('')).to be false
      expect(described_class.valid_directory?('/')).to be false
      expect(described_class.valid_directory?(tmp.join('missing'))).to be false
      expect(described_class.valid_directory?(file)).to be false
    end
  end

  describe '.safe_for_write?' do
    it 'refuses paths directly under the root and nil/empty input' do
      expect(described_class.safe_for_write?('/top-level-file')).to be false
      expect(described_class.safe_for_write?(nil)).to be false
      expect(described_class.safe_for_write?('')).to be false
    end

    it 'allows deeper paths' do
      expect(described_class.safe_for_write?(tmp.join('a'))).to be true
    end
  end

  describe '.ensure_directories_exist' do
    it 'creates every directory (nested), accepting one path or many, skipping blanks' do
      one = tmp.join('a', 'b')
      many = [tmp.join('c'), nil, '', tmp.join('d', 'e')]

      described_class.ensure_directories_exist(one)
      described_class.ensure_directories_exist(many)

      expect([one, tmp.join('c'), tmp.join('d', 'e')]).to all(be_directory)
    end

    it 'is idempotent' do
      dir = tmp.join('x')
      2.times { described_class.ensure_directories_exist(dir) }

      expect(dir).to be_directory
    end
  end

  describe '.glob_pathnames' do
    it 'yields a Pathname per match and does nothing without a block' do
      tmp.join('one.txt').write('1')
      tmp.join('two.txt').write('2')

      yielded = []
      described_class.glob_pathnames(tmp.join('*.txt').to_s) { |pn| yielded << pn }

      expect(yielded).to all(be_a(Pathname))
      expect(yielded.map { |pn| pn.basename.to_s }).to contain_exactly('one.txt', 'two.txt')
      expect(described_class.glob_pathnames(tmp.join('*.txt').to_s)).to be_nil
    end
  end

  describe '.extract_path_segment_at' do
    it 'returns the segment of the parent path at the index (default: the last)' do
      expect(described_class.extract_path_segment_at('/a/b/c/file.rb')).to eq('c')
      expect(described_class.extract_path_segment_at('/a/b/c/file.rb', 1)).to eq('a')
    end
  end

  describe '.command_exists?' do
    it 'is true for a command on PATH and false otherwise' do
      expect(described_class.command_exists?('sh')).to be true
      expect(described_class.command_exists?('definitely-not-a-command-xyz')).to be false
    end
  end

  describe '.set_ssh_folder_permissions' do
    around do |example|
      Dir.mktmpdir('path-utils-ssh-') do |dir|
        @home = Pathname.new(dir)
        example.run
      end
    end

    before do
      Logging.state.reset!
      stub_const('EnvVars::HOME', @home)
      ssh = @home.join('.ssh')
      ssh.mkpath
      %w[id_ed25519 id_rsa].each { |name| ssh.join(name).write('key') }
    end

    after { Logging.state.reset! }

    it 'tries to add every key to the agent even when an earlier one fails' do
      attempted = []
      allow(CommandUtils).to receive(:run_silent) do |*args|
        attempted << args.last if args.first == 'ssh-add'
        args.first != 'ssh-add'
      end

      expect { described_class.set_ssh_folder_permissions }.to output.to_stdout.or output.to_stderr

      expect(attempted.map { |path| File.basename(path) }.uniq).to contain_exactly('id_ed25519', 'id_rsa')
    end
  end
end
