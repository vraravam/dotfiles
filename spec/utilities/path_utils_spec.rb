# encoding: utf-8
# frozen_string_literal: true

require 'path_utils'
require 'tmpdir'

RSpec.describe PathUtils do
  around do |example|
    Dir.mktmpdir('path-utils-spec-') do |dir|
      @tmp = Pathname(dir)
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

    context 'with a controlled PATH' do
      let(:bin_dir) { tmp.join('bin').tap(&:mkpath) }

      def install_command(name, mode: 0o755)
        bin_dir.join(name).tap do |file|
          file.write("#!/bin/sh\n")
          file.chmod(mode)
        end
      end

      it 'finds an executable file and does not fork a subprocess' do
        install_command('spec-cmd-found')
        expect(CommandUtils).not_to receive(:run_silent)

        with_env('PATH' => "/nonexistent:#{bin_dir}") do
          expect(described_class.command_exists?('spec-cmd-found')).to be true
        end
      end

      it 'rejects a non-executable file and a directory of the same name' do
        install_command('spec-cmd-noexec', mode: 0o644)
        bin_dir.join('spec-cmd-dir').mkpath

        with_env('PATH' => bin_dir.to_s) do
          expect(described_class.command_exists?('spec-cmd-noexec')).to be false
          expect(described_class.command_exists?('spec-cmd-dir')).to be false
        end
      end

      it 'does not cache a miss, so a command installed later is found' do
        with_env('PATH' => bin_dir.to_s) do
          expect(described_class.command_exists?('spec-cmd-late')).to be false
          install_command('spec-cmd-late')
          expect(described_class.command_exists?('spec-cmd-late')).to be true
        end
      end

      it 'checks a command containing a slash as a path, ignoring PATH' do
        script = install_command('spec-cmd-path')

        with_env('PATH' => '/nonexistent') do
          expect(described_class.command_exists?(script.to_s)).to be true
          expect(described_class.command_exists?(tmp.join('missing').to_s)).to be false
        end
      end

      it 'is false for an empty command' do
        expect(described_class.command_exists?('')).to be false
      end
    end
  end

  describe '.append_to_path' do
    it 'appends an existing directory to the end of PATH' do
      with_env('PATH' => '/usr/bin:/bin') do
        described_class.append_to_path(tmp)

        expect(ENV['PATH']).to eq("/usr/bin:/bin:#{tmp}")
      end
    end

    it 'accepts the directory as a String as well as a Pathname' do
      with_env('PATH' => '/usr/bin') do
        described_class.append_to_path(tmp.to_s)

        expect(ENV['PATH']).to eq("/usr/bin:#{tmp}")
      end
    end

    it 'appends an existing empty directory (Pathname#empty? is about the directory contents)' do
      empty_dir = tmp.join('empty')
      empty_dir.mkpath

      with_env('PATH' => '/usr/bin') do
        described_class.append_to_path(empty_dir)

        expect(ENV['PATH']).to eq("/usr/bin:#{empty_dir}")
      end
    end

    it 'does nothing when the directory is already in PATH' do
      with_env('PATH' => "/usr/bin:#{tmp}") do
        described_class.append_to_path(tmp)

        expect(ENV['PATH']).to eq("/usr/bin:#{tmp}")
      end
    end

    it 'does nothing for a missing directory or a blank argument' do
      with_env('PATH' => '/usr/bin') do
        described_class.append_to_path(tmp.join('missing'))
        described_class.append_to_path('')
        described_class.append_to_path(nil)

        expect(ENV['PATH']).to eq('/usr/bin')
      end
    end
  end
end
