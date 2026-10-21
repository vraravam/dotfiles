# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# Exercises how clone_repo_into in files/--HOME--/.shellrc guards a clone (keybase:// readiness and
# inactivity, and the GIT_CLONE_* overrides for every other transport) through a real zsh with git,
# keybase and sleep replaced by stubs, so only the decisions are under test -- never a real keybase or
# network.
RSpec.describe '.shellrc clone guard helpers' do
  let(:shellrc) { File.expand_path('../files/--HOME--/.shellrc', __dir__) }

  # Runs +body+ after sourcing .shellrc and installing the stubs; returns [stdout lines, status].
  # +with_retry+ puts a git-with-retry executable on PATH, which is what the code probes for.
  def run_zsh(body, env: {}, with_retry: true)
    Dir.mktmpdir('keybase-clone-spec-') do |home|
      bin = File.join(home, 'bin')
      Dir.mkdir(bin)
      if with_retry
        File.write(File.join(bin, 'git-with-retry'), "#!/bin/sh\n")
        File.chmod(0o755, File.join(bin, 'git-with-retry'))
      end
      script = <<~ZSH
        source #{shellrc}
        # .shellrc puts the repo's scripts/ (with the real git-with-retry) back on PATH, so pin it again.
        PATH="${SPEC_PATH}"; hash -r
        # The code under test sends the stubs' stdout/stderr to /dev/null, so they report on fd 3.
        exec 3>&1
        sleep() { print -r -- "sleep ${1}" >&3; }
        keybase() { print -r -- "keybase ${*}" >&3; return 0; }
        #{body.gsub('<home>', home)}
      ZSH
      # The machine running the spec may have the real git-with-retry on PATH (scripts/ is on it), so
      # entries that contain one are dropped; the fake in +bin+ is the only one that can be found.
      inherited = ENV.fetch('PATH').split(File::PATH_SEPARATOR).reject { |dir| File.exist?(File.join(dir, 'git-with-retry')) }
      path = [bin, *inherited].join(File::PATH_SEPARATOR)
      full_env = { 'HOME' => home, 'PATH' => path, 'SPEC_PATH' => path, 'FIRST_INSTALL' => '' }.merge(env)
      out, err, status = Open3.capture3(full_env, 'zsh', '-c', script)
      raise "zsh failed: #{err}" unless status.success? || body.include?('exit_status')

      [out.lines.map(&:strip).reject(&:empty?), status]
    end
  end

  # A git stub that fails its first +failures+ ls-remote calls, records every call, and runs the
  # command after 'with-retry <t> <n> <file> <progress>' like the real alias would.
  def git_stub(failures:)
    <<~ZSH
      typeset -gi _ls_calls=0
      git() {
        if [[ "$1" == with-retry ]]; then
          print -r -- "with-retry timeout=${2} attempts=${3} progress=${5}" >&3
          shift 5
          case "$1" in
            git | keybase) "$@"; return $? ;; # the probes are real calls into the stubs
            *) return 0 ;;                    # the clone itself is not run
          esac
        fi
        if [[ "$1" == ls-remote ]]; then
          _ls_calls=$((_ls_calls + 1))
          print -r -- "ls-remote ${2}" >&3
          (( _ls_calls > #{failures} ))
          return $?
        fi
        print -r -- "git ${*}" >&3
      }
    ZSH
  end

  describe '_wait_for_keybase_git_backend' do
    it 'returns at once when the git backend already answers, without sleeping' do
      out, = run_zsh("#{git_stub(failures: 0)}\n_wait_for_keybase_git_backend keybase://private/u/r; print -r -- \"rc=$?\"")

      expect(out).to include('rc=0')
      expect(out.grep(/\Asleep/)).to be_empty
      expect(out.grep(/\Als-remote/).length).to eq(1)
    end

    it 'keeps probing every 5 seconds until the backend answers' do
      out, = run_zsh("#{git_stub(failures: 3)}\n_wait_for_keybase_git_backend keybase://private/u/r; print -r -- \"rc=$?\"")

      expect(out).to include('rc=0')
      expect(out.grep(/\Als-remote/).length).to eq(4)
      expect(out.grep(/\Asleep/)).to eq(['sleep 5'] * 3)
    end

    it 'gives up after KEYBASE_READY_ATTEMPTS probes with a non-zero status (the caller clones anyway)' do
      out, = run_zsh("#{git_stub(failures: 99)}\n_wait_for_keybase_git_backend keybase://private/u/r; print -r -- \"rc=$?\"",
                     env: { 'KEYBASE_READY_ATTEMPTS' => '3' })

      expect(out).to include('rc=1')
      expect(out.grep(/\Als-remote/).length).to eq(3)
      expect(out.grep(/\Asleep/).length).to eq(2) # no pointless sleep after the last probe
    end

    it 'probes the clone URL itself, through the hang protection when git-with-retry exists' do
      out, = run_zsh("#{git_stub(failures: 0)}\n_wait_for_keybase_git_backend keybase://private/u/r")

      expect(out).to include('with-retry timeout=30 attempts=1 progress=-', 'ls-remote keybase://private/u/r')
    end

    it 'still probes, unprotected, when git-with-retry is not on PATH yet' do
      out, = run_zsh("#{git_stub(failures: 0)}\n_wait_for_keybase_git_backend keybase://private/u/r; print -r -- \"rc=$?\"", with_retry: false)

      expect(out).to include('rc=0', 'ls-remote keybase://private/u/r')
      expect(out.grep(/with-retry/)).to be_empty
    end
  end

  describe '_keybase_clone_guard' do
    def guard(env: {}, with_retry: true)
      out, = run_zsh(<<~ZSH, env: env, with_retry: with_retry)
        local clone_timeout_secs=25 clone_max_attempts=5 clone_progress_path= clone_unwrapped=false
        _keybase_clone_guard /tmp/clone-folder
        print -r -- "timeout=${clone_timeout_secs} attempts=${clone_max_attempts} progress=${clone_progress_path} unwrapped=${clone_unwrapped}"
      ZSH
      out.last
    end

    it 'tracks growth in the clone folder with a 120s allowance, 5 attempts, on a pre-configured machine' do
      expect(guard).to eq('timeout=120 attempts=5 progress=/tmp/clone-folder unwrapped=false')
    end

    it 'allows 600s and 2 attempts on a FIRST_INSTALL instead of running unguarded' do
      expect(guard(env: { 'FIRST_INSTALL' => '1' })).to eq('timeout=600 attempts=2 progress=/tmp/clone-folder unwrapped=false')
    end

    it 'runs unguarded on a FIRST_INSTALL only while git-with-retry is not on PATH yet' do
      expect(guard(env: { 'FIRST_INSTALL' => '1' }, with_retry: false)).to eq('timeout=600 attempts=2 progress=/tmp/clone-folder unwrapped=true')
    end

    it 'takes the allowance from KEYBASE_CLONE_INACTIVITY_SECS in both modes' do
      expect(guard(env: { 'KEYBASE_CLONE_INACTIVITY_SECS' => '45' })).to start_with('timeout=45 ')
      expect(guard(env: { 'KEYBASE_CLONE_INACTIVITY_SECS' => '45', 'FIRST_INSTALL' => '1' })).to start_with('timeout=45 ')
    end

    it 'restores the old unguarded single attempt with KEYBASE_CLONE_UNWRAPPED=1' do
      expect(guard(env: { 'KEYBASE_CLONE_UNWRAPPED' => '1' })).to end_with('unwrapped=true')
    end
  end

  describe '_clone_via_network for a keybase:// URL' do
    def clone(env: {})
      run_zsh(<<~ZSH, env: env)
        #{git_stub(failures: 0)}
        _clone_via_network keybase://private/u/r /target '' <home>/tmp-clone <home>/err; print -r -- "rc=$?"
      ZSH
    end

    it 'waits for the git backend, then clones under growth-based inactivity tracking (no fixed wall clock)' do
      out, = clone

      expect(out).to include('rc=0')
      expect(out.index('ls-remote keybase://private/u/r')).to be < out.index { |line| line.start_with?('with-retry timeout=120') }
      clone_line = out.find { |line| line.start_with?('with-retry timeout=120 attempts=5') }
      expect(clone_line).to match(%r{progress=/\S+/tmp-clone\z})
      expect(out).not_to include(a_string_matching(/progress=-\z/).and(a_string_matching(/timeout=60/)))
    end

    it 'does not start the clone before the readiness probes ran' do
      out, = clone

      expect(out.index('keybase fs ls /keybase/private/u')).to be < out.index('ls-remote keybase://private/u/r')
    end

    it 'on a FIRST_INSTALL clones with the long allowance and 2 attempts, not unguarded' do
      out, = clone(env: { 'FIRST_INSTALL' => '1' })

      expect(out.grep(/\Awith-retry timeout=600 attempts=2 progress=\S+tmp-clone\z/)).not_to be_empty
    end
  end

  describe '_git_clone_guard and the non-keybase clone' do
    # Every line the run printed (warnings included).
    def guard_output(env: {})
      out, = run_zsh(<<~ZSH, env: env)
        local clone_timeout_secs=25 clone_max_attempts=5 clone_inline_attempts=3
        _git_clone_guard
        print -r -- "timeout=${clone_timeout_secs} attempts=${clone_max_attempts} inline=${clone_inline_attempts}"
      ZSH
      out
    end

    # Only the result line: sourcing .shellrc may print other lines that depend on the machine (CI).
    def guard(env: {})
      guard_output(env: env).grep(/\Atimeout=/)
    end

    it 'leaves 25s, 5 attempts and 3 inline attempts alone when nothing is set' do
      expect(guard).to eq(['timeout=25 attempts=5 inline=3'])
    end

    it 'takes the inactivity allowance from GIT_CLONE_INACTIVITY_SECS' do
      expect(guard(env: { 'GIT_CLONE_INACTIVITY_SECS' => '90' })).to eq(['timeout=90 attempts=5 inline=3'])
    end

    it 'takes the attempts from GIT_CLONE_ATTEMPTS for both the wrapped and the inline clone' do
      expect(guard(env: { 'GIT_CLONE_ATTEMPTS' => '8' })).to eq(['timeout=25 attempts=8 inline=8'])
    end

    it 'ignores a bad value with a warning instead of turning the guard off' do
      %w[0 -3 abc 07 1.5].each do |bad|
        out = guard_output(env: { 'GIT_CLONE_INACTIVITY_SECS' => bad, 'GIT_CLONE_ATTEMPTS' => bad })

        expect(out.grep(/\Atimeout=/)).to eq(['timeout=25 attempts=5 inline=3'])
        expect(out.join("\n")).to include("Ignoring GIT_CLONE_INACTIVITY_SECS='#{bad}'", "Ignoring GIT_CLONE_ATTEMPTS='#{bad}'")
      end
    end

    def clone(url, env: {})
      run_zsh(<<~ZSH, env: env)
        #{git_stub(failures: 0)}
        _clone_via_network #{url} /target '' <home>/tmp-clone <home>/err; print -r -- "rc=$?"
      ZSH
    end

    it 'uses the overrides for an https clone through git-with-retry, with growth tracking on the clone folder' do
      out, = clone('https://example.com/o/r.git', env: { 'GIT_CLONE_INACTIVITY_SECS' => '90', 'GIT_CLONE_ATTEMPTS' => '8' })

      expect(out.grep(/\Awith-retry timeout=90 attempts=8 progress=\S+tmp-clone\z/)).not_to be_empty
    end

    it 'keeps the defaults for an ssh clone when nothing is set' do
      out, = clone('git@github.com:o/r.git')

      expect(out.grep(/\Awith-retry timeout=25 attempts=5 progress=\S+tmp-clone\z/)).not_to be_empty
    end

    it 'does not apply them to a keybase clone, which has its own settings' do
      out, = clone('keybase://private/u/r', env: { 'GIT_CLONE_INACTIVITY_SECS' => '90', 'GIT_CLONE_ATTEMPTS' => '8' })

      expect(out.grep(/\Awith-retry timeout=120 attempts=5 progress=\S+tmp-clone\z/)).not_to be_empty
    end

    it 'retries the inline fallback (no git-with-retry yet) GIT_CLONE_ATTEMPTS times' do
      script = <<~ZSH
        typeset -gi _clones=0
        git() { _clones=$((_clones + 1)); print -r -- "clone ${_clones}" >&3; return 1; }
        _clone_via_network https://example.com/o/r.git /target '' <home>/tmp-clone <home>/err; print -r -- "rc=$?"
      ZSH
      out, = run_zsh(script, env: { 'GIT_CLONE_ATTEMPTS' => '4' }, with_retry: false)

      expect(out.grep(/\Aclone \d/)).to eq(['clone 1', 'clone 2', 'clone 3', 'clone 4'])
      expect(out).to include('rc=1')
      expect(out.grep(/\Asleep 5/).length).to eq(3)
    end
  end
end
