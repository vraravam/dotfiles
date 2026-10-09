# frozen_string_literal: true

require 'command_utils'
require 'tempfile'

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
      expect { described_class.check_status_or_record('', '', failed_status, 'm', severity: :fatal) }
        .to raise_error(ArgumentError, /severity must be/)
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
end
