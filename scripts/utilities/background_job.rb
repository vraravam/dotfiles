#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

# Helpers for long-running subprocesses that the fresh install starts in the background and
# joins (or reports on) later: the Homebrew installer started by the shell, the baseline
# `osx-defaults.sh -s` run, and the full Brewfile install. Loaded under `ruby --disable-gems`
# by call-utility.rb, so it requires nothing beyond 'pathname'.
module BackgroundJob
  extend self

  # A child this process started. +waiter+ is the Process.detach thread: it reaps the child and
  # its #value is the Process::Status once the child has finished.
  Job = Struct.new(:pid, :log, :waiter, keyword_init: true)

  # Starts +command+ with stdout and stderr appended to +log+ and stdin closed, so it can never
  # compete with the foreground steps for the terminal.
  #
  # @param env [Hash] Extra environment for the child
  # @param command [Array<String>] Command and arguments
  # @param log [Pathname, String] File the output is appended to
  # @return [Job, nil] nil when the process could not be started
  def start(env, *command, log:)
    log_path = Pathname(log)
    log_path.dirname.mkpath
    pid = Process.spawn(env, *command, in: File::NULL, out: [log_path.to_s, 'a'], err: [log_path.to_s, 'a'])
    Job.new(pid: pid, log: log_path, waiter: Process.detach(pid))
  rescue SystemCallError
    nil
  end

  # @param job [Job]
  # @return [Boolean] whether the child is still running
  def running?(job)
    job.waiter.alive?
  end

  # @param job [Job]
  # @return [Process::Status, nil] the exit status, or nil while the child is still running
  def status(job)
    running?(job) ? nil : job.waiter.value
  end

  # Whether +pid+ names a live process this user may signal. A process that is not ours (EPERM)
  # counts as gone: it can only be an unrelated process that reused the pid.
  #
  # @param pid [Integer]
  # @return [Boolean]
  def pid_alive?(pid)
    return false unless pid.to_i.positive?

    Process.kill(0, pid.to_i)
    true
  rescue SystemCallError
    false
  end

  # Polls until +pid+ has exited or +timeout+ seconds have passed. +pid+ need not be a child of
  # this process (the shell started it), so this checks liveness rather than calling waitpid.
  #
  # @param pid [Integer]
  # @param timeout [Numeric] Seconds to wait at most
  # @param poll [Numeric] Seconds between liveness checks
  # @param tick [Numeric] Seconds between calls to the block (progress reporting)
  # @yield [elapsed] Called about every +tick+ seconds while waiting
  # @yieldparam elapsed [Integer] Whole seconds waited so far
  # @return [Boolean] true when the process exited, false when the timeout was reached
  def wait_for_pid(pid, timeout:, poll: 1, tick: 30)
    started = _now
    last_tick = started
    while pid_alive?(pid)
      now = _now
      return false if now - started >= timeout

      if block_given? && now - last_tick >= tick
        last_tick = now
        yield((now - started).to_i)
      end
      sleep poll
    end
    true
  end

  # Polls a child started by #start until it has finished or +timeout+ seconds have passed.
  #
  # @param job [Job]
  # @param timeout [Numeric] Seconds to wait at most
  # @param poll [Numeric] Seconds between checks
  # @param tick [Numeric] Seconds between calls to the block
  # @yield [elapsed] See #wait_for_pid
  # @return [Process::Status, nil] the exit status, or nil on timeout (the child is left running)
  def wait(job, timeout:, poll: 1, tick: 30)
    return job.waiter.value if job.waiter.join(0)

    started = _now
    last_tick = started
    loop do
      return job.waiter.value if job.waiter.join(poll)

      now = _now
      return nil if now - started >= timeout

      next unless block_given? && now - last_tick >= tick

      last_tick = now
      yield((now - started).to_i)
    end
  end

  # Runs +command+ in the foreground with its stdout and stderr streamed live to $stdout, and
  # stops it when it runs longer than +timeout+ seconds in total or prints nothing for
  # +inactivity+ seconds (a hung download or a prompt nobody can answer). stdin stays attached.
  #
  # @param env [Hash] Extra environment for the child
  # @param command [Array<String>] Command and arguments
  # @param timeout [Numeric] Overall limit in seconds
  # @param inactivity [Numeric] Seconds without any output after which the child is stopped
  # @param poll [Numeric] Seconds between checks
  # @return [Symbol] :ok (exit 0), :failed (non-zero exit), :timeout, :stalled, or :not_started
  def run_guarded(env, *command, timeout:, inactivity:, poll: 1)
    reader, writer = IO.pipe
    begin
      pid = Process.spawn(env, *command, out: writer, err: writer)
    rescue SystemCallError
      reader.close
      writer.close
      return :not_started
    end
    writer.close
    last_output = _now
    pump = Thread.new do
      loop do
        $stdout.write(reader.readpartial(4096))
        last_output = _now
      end
    rescue IOError # includes EOFError
      nil
    end

    verdict = _supervise(pid, timeout: timeout, inactivity: inactivity, poll: poll) { last_output }
    pump.join(2)
    pump.kill
    reader.close
    verdict
  end

  # Runs +command+, capturing its stdout (stderr is discarded), and stops it after +timeout+
  # seconds. For quick status queries of tools that can hang when their background service is
  # wedged, where the plain Open3.capture3 would block the whole setup.
  #
  # @param command [Array<String>] Command and arguments
  # @param timeout [Numeric] Seconds to wait at most
  # @return [Array(String, Process::Status), Array(String, nil)] stdout and the exit status, which
  #   is nil when the command timed out (it was then stopped) or could not be started
  def capture(*command, timeout:)
    reader, writer = IO.pipe
    begin
      pid = Process.spawn(*command, in: File::NULL, out: writer, err: File::NULL)
    rescue SystemCallError
      reader.close
      writer.close
      return ['', nil]
    end
    writer.close
    output = +''
    pump = Thread.new do
      loop { output << reader.readpartial(4096) }
    rescue IOError # includes EOFError
      nil
    end

    waiter = Process.detach(pid)
    if waiter.join(timeout)
      pump.join(2)
      [output, waiter.value]
    else
      terminate(pid)
      pump.kill
      ['', nil]
    end
  ensure
    reader&.close
  end

  # Sends SIGTERM to +pid+ and, if it is still alive after +grace+ seconds, SIGKILL.
  #
  # @param pid [Integer]
  # @param grace [Numeric] Seconds to wait between the two signals
  # @return [void]
  def terminate(pid, grace: 3)
    return unless pid_alive?(pid)

    Process.kill('TERM', pid.to_i)
    return if wait_for_pid(pid, timeout: grace, poll: 0.1)

    Process.kill('KILL', pid.to_i)
  rescue SystemCallError
    nil
  end

  # The last +lines+ lines of +file+ (read as UTF-8, invalid bytes replaced), for progress
  # reports. Reads only the tail of the file, so a large log costs nothing.
  #
  # @param file [Pathname, String, nil]
  # @param lines [Integer]
  # @return [Array<String>] empty when the file is absent or unreadable
  def tail(file, lines: 5)
    path = file && Pathname(file)
    return [] unless path&.file?

    start = [path.size - 8192, 0].max
    text = path.binread(path.size - start, start)
    text.force_encoding('UTF-8').scrub.lines.map(&:chomp).reject { |line| line.strip.empty? }.last(lines)
  rescue SystemCallError
    []
  end

  # Waits for +pid+, a child of this process, applying the limits of #run_guarded.
  #
  # @yield Returns the monotonic time of the child's last output
  # @return [Symbol] See #run_guarded
  def _supervise(pid, timeout:, inactivity:, poll:, &last_output)
    started = _now
    loop do
      _pid, status = Process.wait2(pid, Process::WNOHANG)
      return(status.success? ? :ok : :failed) if status

      verdict = _limit_hit(started, timeout, inactivity, &last_output)
      if verdict
        _stop(pid)
        return verdict
      end
      sleep poll
    end
  end

  # @return [Symbol, nil] :timeout or :stalled when a limit of #run_guarded is exceeded, else nil
  def _limit_hit(started, timeout, inactivity, &last_output)
    now = _now
    return :timeout if now - started >= timeout

    :stalled if now - last_output.call >= inactivity
  end

  # SIGTERM, then SIGKILL when the child is still there after a short grace period; reaps it.
  def _stop(pid)
    Process.kill('TERM', pid)
    deadline = _now + 3
    while _now < deadline
      return if Process.wait2(pid, Process::WNOHANG)

      sleep 0.05
    end
    Process.kill('KILL', pid)
    Process.wait(pid)
  rescue SystemCallError
    nil
  end

  def _now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  private_class_method :_supervise, :_limit_hit, :_stop, :_now
end
