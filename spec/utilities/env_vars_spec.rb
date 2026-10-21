# encoding: utf-8
# frozen_string_literal: true

require 'env_vars'

# NOTE: Only the runtime-flag methods are tested here (evaluated fresh on each
# call via ENV.fetch). The path/string constants (EnvVars::HOME, DOTFILES_DIR,
# etc.) are computed once when this file is first required and frozen -- by
# the time any spec runs, they already reflect whatever ENV looked like at
# require time, so stubbing ENV afterward cannot change them. Testing those
# would just re-assert Ruby's own constant/require semantics, not this code.
RSpec.describe EnvVars do
  describe '.first_install?' do
    it 'is false when FIRST_INSTALL is unset' do
      with_env('FIRST_INSTALL' => nil) do
        expect(described_class.first_install?).to be false
      end
    end

    it 'is true when FIRST_INSTALL is set to any non-empty value' do
      with_env('FIRST_INSTALL' => 'true') do
        expect(described_class.first_install?).to be true
      end
    end
  end

  describe 'UPSTREAM_GH_USERNAME' do
    it 'defaults to the upstream owner' do
      expect(described_class::UPSTREAM_GH_USERNAME).to be_a(String).and(satisfy { |v| !v.empty? })
    end
  end

  describe '.debug?' do
    it 'is false when DEBUG is unset' do
      with_env('DEBUG' => nil) do
        expect(described_class.debug?).to be false
      end
    end

    it 'is true when DEBUG is set' do
      with_env('DEBUG' => '1') do
        expect(described_class.debug?).to be true
      end
    end
  end

  describe '.set?' do
    it 'is true only for a non-blank value' do
      with_env('ENV_VARS_SPEC' => 'x') { expect(described_class.set?('ENV_VARS_SPEC')).to be true }
      with_env('ENV_VARS_SPEC' => '  ') { expect(described_class.set?('ENV_VARS_SPEC')).to be false }
      with_env('ENV_VARS_SPEC' => nil) { expect(described_class.set?('ENV_VARS_SPEC')).to be false }
    end
  end

  describe 'flags built on whitespace-only values' do
    it 'treat a whitespace-only value as unset' do
      with_env('FIRST_INSTALL' => ' ', 'DEBUG' => ' ', 'DIRENV_IN_ENVRC' => ' ', 'CACHE_BUST_HEADERS' => ' ', 'CURL_RETRY_OPTS' => ' ') do
        expect([described_class.first_install?, described_class.debug?, described_class.suppress_log?,
                described_class.cache_bust_headers?, described_class.curl_retry_opts?]).to all(be false)
      end
    end
  end

  describe '.folder / .ref_folder' do
    it 'are nil when unset or blank and an expanded Pathname otherwise' do
      with_env('FOLDER' => nil, 'REF_FOLDER' => '  ') do
        expect(described_class.folder).to be_nil
        expect(described_class.ref_folder).to be_nil
      end
      with_env('FOLDER' => '~/x', 'REF_FOLDER' => '/tmp/../tmp/y') do
        expect(described_class.folder).to eq(Pathname('~/x').expand_path)
        expect(described_class.ref_folder).to eq(Pathname('/tmp/y'))
      end
    end
  end

  describe '.mindepth / .maxdepth / .columns' do
    it 'default to 1 / 4 / 80 and read integers from the environment' do
      with_env('MINDEPTH' => nil, 'MAXDEPTH' => nil, 'COLUMNS' => nil) do
        expect([described_class.mindepth, described_class.maxdepth, described_class.columns]).to eq([1, 4, 80])
      end
      with_env('MINDEPTH' => '2', 'MAXDEPTH' => '7', 'COLUMNS' => '120') do
        expect([described_class.mindepth, described_class.maxdepth, described_class.columns]).to eq([2, 7, 120])
      end
    end
  end

  describe '.script_depth' do
    it 'is 0 when _DOTFILES_SCRIPT_DEPTH is unset' do
      with_env('_DOTFILES_SCRIPT_DEPTH' => nil) do
        expect(described_class.script_depth).to eq(0)
      end
    end

    it 'returns the integer value when set' do
      with_env('_DOTFILES_SCRIPT_DEPTH' => '3') do
        expect(described_class.script_depth).to eq(3)
      end
    end
  end

  describe '.columns' do
    it 'defaults to 80 when COLUMNS is unset' do
      with_env('COLUMNS' => nil) do
        expect(described_class.columns).to eq(80)
      end
    end

    it 'returns the integer value when set' do
      with_env('COLUMNS' => '120') do
        expect(described_class.columns).to eq(120)
      end
    end
  end

  describe '.mindepth' do
    it 'defaults to 1 when MINDEPTH is unset' do
      with_env('MINDEPTH' => nil) do
        expect(described_class.mindepth).to eq(1)
      end
    end
  end

  describe '.maxdepth' do
    it 'defaults to 4 when MAXDEPTH is unset' do
      with_env('MAXDEPTH' => nil) do
        expect(described_class.maxdepth).to eq(4)
      end
    end
  end

  describe '.filter' do
    it 'is nil when FILTER is unset' do
      with_env('FILTER' => nil) do
        expect(described_class.filter).to be_nil
      end
    end

    it 'is nil when FILTER is whitespace-only' do
      with_env('FILTER' => '   ') do
        expect(described_class.filter).to be_nil
      end
    end

    it 'returns the stripped value when set' do
      with_env('FILTER' => '  my-repo  ') do
        expect(described_class.filter).to eq('my-repo')
      end
    end
  end

  describe '.folder' do
    it 'is nil when FOLDER is unset' do
      with_env('FOLDER' => nil) do
        expect(described_class.folder).to be_nil
      end
    end

    it 'returns an expanded Pathname when set' do
      with_env('FOLDER' => '.') do
        expect(described_class.folder).to eq(Pathname('.').expand_path)
      end
    end
  end

  describe '.ref_folder' do
    it 'is nil when REF_FOLDER is unset' do
      with_env('REF_FOLDER' => nil) do
        expect(described_class.ref_folder).to be_nil
      end
    end

    it 'returns an expanded Pathname when set' do
      with_env('REF_FOLDER' => '.') do
        expect(described_class.ref_folder).to eq(Pathname('.').expand_path)
      end
    end
  end

  describe '.suppress_log?' do
    it 'is false when DIRENV_IN_ENVRC is unset' do
      with_env('DIRENV_IN_ENVRC' => nil) do
        expect(described_class.suppress_log?).to be false
      end
    end

    it 'is true when DIRENV_IN_ENVRC is set' do
      with_env('DIRENV_IN_ENVRC' => '1') do
        expect(described_class.suppress_log?).to be true
      end
    end
  end

  describe '.cache_bust_headers?' do
    it 'is false when CACHE_BUST_HEADERS is unset' do
      with_env('CACHE_BUST_HEADERS' => nil) do
        expect(described_class.cache_bust_headers?).to be false
      end
    end

    it 'is true when CACHE_BUST_HEADERS is set' do
      with_env('CACHE_BUST_HEADERS' => 'true') do
        expect(described_class.cache_bust_headers?).to be true
      end
    end
  end

  describe '.path' do
    it 'returns the current PATH environment variable' do
      with_env('PATH' => '/usr/bin:/bin') do
        expect(described_class.path).to eq('/usr/bin:/bin')
      end
    end
  end

  describe '.cron_backup_file' do
    it 'returns a Pathname built from TMPDIR when unset' do
      with_env('_DOTFILES_CRON_BACKUP_FILE' => nil) do
        expect(described_class.cron_backup_file).to eq(described_class::TMPDIR.join('crontab_backup'))
      end
    end

    it 'returns a Pathname wrapping the env var when set' do
      with_env('_DOTFILES_CRON_BACKUP_FILE' => '/tmp/custom_backup') do
        expect(described_class.cron_backup_file).to eq(Pathname('/tmp/custom_backup'))
      end
    end
  end

  describe '.issues_file' do
    before { described_class.remove_instance_variable(:@_issues_file) if described_class.instance_variable_defined?(:@_issues_file) }
    after { described_class.remove_instance_variable(:@_issues_file) if described_class.instance_variable_defined?(:@_issues_file) }

    it 'is nil when _DOTFILES_ISSUES_FILE is unset or blank' do
      with_env('_DOTFILES_ISSUES_FILE' => nil) { expect(described_class.issues_file).to be_nil }
      described_class.remove_instance_variable(:@_issues_file)
      with_env('_DOTFILES_ISSUES_FILE' => '  ') { expect(described_class.issues_file).to be_nil }
    end

    it 'is a Pathname wrapping the env var when set' do
      with_env('_DOTFILES_ISSUES_FILE' => '/tmp/issues') do
        expect(described_class.issues_file).to eq(Pathname('/tmp/issues'))
      end
    end

    it 'memoizes the result, including the unset case' do
      with_env('_DOTFILES_ISSUES_FILE' => nil) { expect(described_class.issues_file).to be_nil }

      with_env('_DOTFILES_ISSUES_FILE' => '/tmp/later') { expect(described_class.issues_file).to be_nil }
    end
  end
end
