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

  describe '.force_color?' do
    it 'is false when FORCE_COLOR is unset' do
      with_env('FORCE_COLOR' => nil) do
        expect(described_class.force_color?).to be false
      end
    end

    it 'is false when FORCE_COLOR is set but whitespace-only' do
      with_env('FORCE_COLOR' => '   ') do
        expect(described_class.force_color?).to be false
      end
    end

    it 'is true when FORCE_COLOR is set to a non-empty value' do
      with_env('FORCE_COLOR' => '1') do
        expect(described_class.force_color?).to be true
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
        expect(described_class.folder).to eq(Pathname.new('.').expand_path)
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
        expect(described_class.ref_folder).to eq(Pathname.new('.').expand_path)
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
        expect(described_class.cron_backup_file).to eq(Pathname.new('/tmp/custom_backup'))
      end
    end
  end
end
