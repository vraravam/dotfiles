# frozen_string_literal: true

require 'string_ext'

RSpec.describe String do
  describe '#comment_or_empty?' do
    it 'is true for an empty string' do
      expect(''.comment_or_empty?).to be true
    end

    it 'is true for a whitespace-only string' do
      expect('   '.comment_or_empty?).to be true
    end

    it 'is true for a comment line' do
      expect('# a comment'.comment_or_empty?).to be true
    end

    it 'is true for a comment line with leading whitespace' do
      expect('   # indented comment'.comment_or_empty?).to be true
    end

    it 'is false for a regular content line' do
      expect('some.domain.value'.comment_or_empty?).to be false
    end
  end

  describe 'color methods' do
    context 'when stdout is not a TTY' do
      before { allow($stdout).to receive(:tty?).and_return(false) }

      it 'returns the string unchanged (no ANSI codes)' do
        expect('hello'.cyan).to eq('hello')
      end

      it 'still substitutes HOME with ~' do
        with_env('HOME' => '/Users/example') do
          expect('/Users/example/dev/repo'.cyan).to eq('~/dev/repo')
        end
      end
    end

    context 'when stdout is a TTY' do
      before { allow($stdout).to receive(:tty?).and_return(true) }

      it 'wraps the string in the correct ANSI escape codes' do
        expect('hello'.cyan).to eq("\x1b[0;36mhello\x1b[0m")
      end

      it 'applies HOME substitution before wrapping in ANSI codes' do
        with_env('HOME' => '/Users/example') do
          expect('/Users/example/dev'.yellow).to eq("\x1b[1;33m~/dev\x1b[0m")
        end
      end
    end
  end

  describe '#replace_home_path_with_tilde' do
    it 'replaces the HOME prefix with ~' do
      with_env('HOME' => '/Users/example') do
        expect('/Users/example/dev/repo'.replace_home_path_with_tilde).to eq('~/dev/repo')
      end
    end

    it 'leaves the string unchanged when it does not contain HOME' do
      with_env('HOME' => '/Users/example') do
        expect('/opt/homebrew/bin/git'.replace_home_path_with_tilde).to eq('/opt/homebrew/bin/git')
      end
    end
  end
end
