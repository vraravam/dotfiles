# encoding: utf-8
# frozen_string_literal: true

require 'command_utils'
require 'tempfile'
require 'tmpdir'

RSpec.describe CommandUtils do
  let(:ok_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failed_status) { instance_double(Process::Status, success?: false, exitstatus: 3) }

  before { Logging.state.reset! }
  after { Logging.state.reset! }

  describe '.query' do
    it 'returns the stripped stdout' do
      expect(described_class.query('echo', '  hi  ')).to eq('hi')
    end

    it 'accepts a leading environment hash' do
      expect(described_class.query({ 'CU_SPEC_VAR' => 'v' }, 'sh', '-c', 'printf %s "$CU_SPEC_VAR"')).to eq('v')
    end
  end

  describe '.check_status' do
    it 'is true and does not yield on success' do
      expect { |blk| described_class.check_status('o', 'e', ok_status, &blk) }.not_to yield_control
      expect(described_class.check_status('o', 'e', ok_status)).to be true
    end

    it 'is false for a nil status' do
      expect(described_class.check_status('', '', nil)).to be false
    end

    it 'yields the status and a message with stdout/stderr on failure' do
      message = nil
      result = described_class.check_status("out\n", "err\n", failed_status) { |_st, msg| message = msg }

      expect(result).to be false
      expect(message).to include('STDOUT: out').and include('STDERR: ').and include('err')
    end

    it 'drops stderr lines matching the noise patterns' do
      message = nil
      described_class.check_status('', "Permission denied: a\nreal problem\n", failed_status, noise_patterns: ['Permission denied']) { |_st, msg| message = msg }

      expect(message).to include('real problem')
      expect(message).not_to include('Permission denied')
    end
  end

  describe '.check_status_or_record' do
    it 'records nothing when the command succeeded' do
      expect(described_class.check_status_or_record('', '', ok_status, 'Failed to x')).to be true
      expect(Logging.step_warnings).to be_empty
    end

    it 'records a warning by default, including the status' do
      expect(Logging).to receive(:record_warning).with(/\AFailed to x \(status: 3\)/)

      expect(described_class.check_status_or_record('', 'boom', failed_status, 'Failed to x')).to be false
    end

    it 'records an error when severity: :error' do
      expect(Logging).to receive(:record_error).with(/\AFailed to y \(status: 3\)/)

      described_class.check_status_or_record('', '', failed_status, 'Failed to y', severity: :error)
    end

    it 'rejects an unknown severity' do
      expect { described_class.check_status_or_record('', '', failed_status, 'm', severity: :fatal) }.to raise_error(ArgumentError, /severity must be/)
    end
  end

  describe '.run_silent' do
    it 'returns success/failure and keeps output off the terminal' do
      expect { expect(described_class.run_silent('sh', '-c', 'echo noisy; echo noisy >&2')).to be true }.not_to output.to_stdout_from_any_process
      expect(described_class.run_silent('sh', '-c', 'exit 1')).to be false
    end
  end

  describe '.capture_output' do
    it 'is true for a successful command' do
      expect(described_class.capture_output('true')).to be true
    end

    it 'yields the status and output for a failing command' do
      seen = nil
      expect(described_class.capture_output('sh', '-c', 'echo bad >&2; exit 2') { |st, msg| seen = [st.exitstatus, msg] }).to be false
      expect(seen.first).to eq(2)
      expect(seen.last).to include('bad')
    end

    it 'yields a nil status when the command does not exist' do
      seen = :unset
      expect(described_class.capture_output('definitely-not-a-command-xyz') { |st, _msg| seen = st }).to be false
      expect(seen).to be_nil
    end
  end

  describe '.run_interactive' do
    it 'runs the block only on failure' do
      expect { |blk| described_class.run_interactive('true', &blk) }.not_to yield_control
      expect { |blk| described_class.run_interactive('false', &blk) }.to yield_control
    end
  end

  describe '.curl_opts' do
    around do |example|
      Dir.mktmpdir('command-utils-curl-spec-') do |dir|
        @home = Pathname(dir)
        example.run
      end
    end

    before do
      stub_const('EnvVars::HOME', @home)
      allow(EnvVars).to receive(:cache_bust_headers?).and_return(false)
      allow(EnvVars).to receive(:curl_retry_opts?).and_return(false)
    end

    it 'is the short retry set unless this is a bootstrap download' do
      expect(described_class.curl_opts).to eq(CommandUtils::CURL_LIGHT_RETRY_OPTS)
    end

    context 'for a bootstrap download' do
      it 'adds the long retry flags while ~/.curlrc is not linked' do
        expect(described_class.curl_opts(bootstrap: true)).to eq(CommandUtils::CURL_BOOTSTRAP_RETRY_OPTS)
      end

      it 'adds nothing when ~/.curlrc exists and nothing is requested' do
        @home.join('.curlrc').write('')

        expect(described_class.curl_opts(bootstrap: true)).to eq([])
      end

      it 'adds the long retry flags when CURL_RETRY_OPTS is set even with ~/.curlrc' do
        @home.join('.curlrc').write('')
        allow(EnvVars).to receive(:curl_retry_opts?).and_return(true)

        expect(described_class.curl_opts(bootstrap: true)).to eq(CommandUtils::CURL_BOOTSTRAP_RETRY_OPTS)
      end

      it 'puts the cache-busting headers first when CACHE_BUST_HEADERS is set' do
        allow(EnvVars).to receive(:cache_bust_headers?).and_return(true)
        @home.join('.curlrc').write('')

        expect(described_class.curl_opts(bootstrap: true)).to eq(CommandUtils::CURL_CACHE_BUST_OPTS)
      end
    end
  end

  describe '.curl_download' do
    it 'runs curl silently with the short retry flags by default' do
      expect(described_class).to receive(:run_silent).with('curl', '--retry', '3', '--retry-delay', '5', '-fsSL', 'https://x/y', '-o', '/tmp/out').and_return(true)

      expect(described_class.curl_download('https://x/y', Pathname('/tmp/out'))).to be true
    end

    it 'streams curl and uses the bootstrap flags when asked' do
      allow(described_class).to receive(:curl_opts).with(bootstrap: true).and_return(['--retry', '9'])
      expect(described_class).to receive(:run_interactive).with('curl', '--retry', '9', '-fsSL', 'https://x/y', '-o', '/tmp/out').and_return(false)

      expect(described_class.curl_download('https://x/y', '/tmp/out', bootstrap: true, interactive: true)).to be false
    end
  end
end
