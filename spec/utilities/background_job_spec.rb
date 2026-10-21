# encoding: utf-8
# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'background_job'

RSpec.describe BackgroundJob do
  around do |example|
    Dir.mktmpdir('background-job-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:tmp) { @tmp }
  let(:spawned) { [] }

  after { spawned.each { |pid| kill_quietly(pid) } }

  def kill_quietly(pid)
    Process.kill('KILL', pid)
  rescue SystemCallError
    nil
  end

  def spawn_reaped(script)
    pid = Process.spawn('sh', '-c', script)
    Process.detach(pid)
    spawned << pid
    pid
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe '.start, .running?, .status and .wait' do
    it 'appends the output to the log, creating its folder, and reports the exit status' do
      log = tmp.join('logs', 'job.log')
      job = described_class.start({ 'JOB_VAR' => 'x' }, 'sh', '-c', 'echo "out $JOB_VAR"; echo err >&2; exit 4', log: log)

      status = described_class.wait(job, timeout: 5, poll: 0.02)

      expect(status.exitstatus).to eq(4)
      expect(described_class.running?(job)).to be false
      expect(described_class.status(job).exitstatus).to eq(4)
      expect(log.read).to include('out x', 'err')
    end

    it 'has no status while the child runs, and wait gives up at the timeout leaving it running' do
      job = described_class.start({}, 'sleep', '30', log: tmp.join('job.log'))
      spawned << job.pid

      expect(described_class.running?(job)).to be true
      expect(described_class.status(job)).to be_nil
      expect(described_class.wait(job, timeout: 0.15, poll: 0.02)).to be_nil
      expect(described_class.running?(job)).to be true
    end

    it 'calls the progress block about every tick while waiting' do
      job = described_class.start({}, 'sleep', '30', log: tmp.join('job.log'))
      spawned << job.pid
      ticks = []

      described_class.wait(job, timeout: 0.35, poll: 0.02, tick: 0.1) { |elapsed| ticks << elapsed }

      expect(ticks.length).to be >= 2
    end

    it 'is nil when the command cannot be started' do
      expect(described_class.start({}, tmp.join('missing').to_s, log: tmp.join('job.log'))).to be_nil
    end
  end

  describe '.pid_alive? and .wait_for_pid' do
    it 'is false for a pid that is not positive' do
      expect(described_class.pid_alive?(0)).to be false
      expect(described_class.pid_alive?(-1)).to be false
    end

    it 'sees a live process and then its exit' do
      pid = spawn_reaped('sleep 0.2')

      expect(described_class.pid_alive?(pid)).to be true
      expect(described_class.wait_for_pid(pid, timeout: 5, poll: 0.02)).to be true
      expect(described_class.pid_alive?(pid)).to be false
    end

    it 'returns false at the timeout while the process is still running' do
      pid = spawn_reaped('sleep 30')

      expect(described_class.wait_for_pid(pid, timeout: 0.15, poll: 0.02)).to be false
    end

    it 'reports progress every tick' do
      pid = spawn_reaped('sleep 0.35')
      ticks = []

      described_class.wait_for_pid(pid, timeout: 5, poll: 0.02, tick: 0.1) { |elapsed| ticks << elapsed }

      expect(ticks).not_to be_empty
    end

    it 'treats a process owned by someone else as gone' do
      allow(Process).to receive(:kill).with(0, 4242).and_raise(Errno::EPERM)

      expect(described_class.pid_alive?(4242)).to be false
    end
  end

  describe '.terminate' do
    it 'stops a process' do
      pid = spawn_reaped('sleep 30')

      described_class.terminate(pid)

      expect(described_class.pid_alive?(pid)).to be false
    end

    it 'kills a process that ignores SIGTERM' do
      pid = spawn_reaped("trap '' TERM; while true; do sleep 0.1; done")
      sleep 0.2

      described_class.terminate(pid, grace: 0.3)

      expect(described_class.wait_for_pid(pid, timeout: 3, poll: 0.05)).to be true
    end

    it 'does nothing for a pid that is gone' do
      expect { described_class.terminate(0) }.not_to raise_error
    end
  end

  describe '.run_guarded' do
    def guarded(script, **limits)
      verdict = nil
      output = capture_stdout { verdict = described_class.run_guarded({ 'GUARD_VAR' => 'v' }, 'sh', '-c', script, poll: 0.02, **limits) }
      [verdict, output]
    end

    it 'streams the output and is :ok for a command that exits 0' do
      verdict, output = guarded('echo "hello $GUARD_VAR"; echo oops >&2', timeout: 5, inactivity: 5)

      expect(verdict).to eq(:ok)
      expect(output).to include('hello v', 'oops')
    end

    it 'is :failed for a non-zero exit' do
      expect(guarded('exit 2', timeout: 5, inactivity: 5).first).to eq(:failed)
    end

    it 'stops a command that runs longer than the timeout, even if it keeps printing' do
      verdict, = guarded('while true; do echo tick; sleep 0.02; done', timeout: 0.3, inactivity: 5)

      expect(verdict).to eq(:timeout)
    end

    it 'stops a command that prints nothing for the inactivity limit' do
      verdict, output = guarded('echo started; sleep 30', timeout: 10, inactivity: 0.3)

      expect(verdict).to eq(:stalled)
      expect(output).to include('started')
    end

    it 'leaves no process behind after stopping one' do
      guarded("echo $$ > #{tmp.join('pid')}; sleep 30", timeout: 0.3, inactivity: 5)

      expect(described_class.pid_alive?(tmp.join('pid').read.to_i)).to be false
    end

    it 'is :not_started when the command does not exist' do
      verdict = nil
      capture_stdout { verdict = described_class.run_guarded({}, tmp.join('missing').to_s, timeout: 1, inactivity: 1) }

      expect(verdict).to eq(:not_started)
    end
  end

  describe '.capture' do
    it 'returns the stdout and the status' do
      stdout, status = described_class.capture('sh', '-c', 'echo hi; echo err >&2', timeout: 5)

      expect(stdout).to eq("hi\n")
      expect(status).to be_success
    end

    it 'returns no status when the command timed out, and stops it' do
      stdout, status = described_class.capture('sh', '-c', "echo $$ > #{tmp.join('pid')}; sleep 30", timeout: 0.3)

      expect([stdout, status]).to eq(['', nil])
      expect(described_class.pid_alive?(tmp.join('pid').read.to_i)).to be false
    end

    it 'returns no status when the command does not exist' do
      expect(described_class.capture(tmp.join('missing').to_s, timeout: 1)).to eq(['', nil])
    end
  end

  describe '.tail' do
    it 'returns the last non-blank lines' do
      log = tmp.join('log')
      log.write("one\n\ntwo\nthree\n\n")

      expect(described_class.tail(log, lines: 2)).to eq(%w[two three])
    end

    it 'reads only the end of a large file' do
      log = tmp.join('log')
      log.write("#{'x' * 100_000}\nlast line\n")

      expect(described_class.tail(log, lines: 1)).to eq(['last line'])
    end

    it 'replaces invalid UTF-8 instead of raising' do
      log = tmp.join('log')
      log.binwrite("bad \xFF byte\n")

      expect(described_class.tail(log).first).to include('bad')
    end

    it 'is empty for a missing file or nil' do
      expect(described_class.tail(tmp.join('nope'))).to eq([])
      expect(described_class.tail(nil)).to eq([])
    end
  end
end
