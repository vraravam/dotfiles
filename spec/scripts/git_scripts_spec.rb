# encoding: utf-8
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

# Exercises the external git subcommands in scripts/ (git-with-retry, git-fo, git-upreb, git-unshallow) as real
# processes against throwaway repositories under a temp directory. Each is a plain POSIX sh script
# that git runs as 'git <name>' when scripts/ is on PATH.
RSpec.describe 'external git subcommands' do
  scripts_dir = File.expand_path('../../scripts', __dir__)
  git_config = File.expand_path('../../files/--XDG_CONFIG_HOME--/git/config', __dir__)

  let(:env) do
    {
      'PATH' => "#{scripts_dir}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
      'GIT_CONFIG_NOSYSTEM' => '1',
      'GIT_CONFIG_GLOBAL' => git_config,
      'GIT_CONFIG_COUNT' => '5',
      'GIT_CONFIG_KEY_0' => 'core.hooksPath', 'GIT_CONFIG_VALUE_0' => File::NULL,
      'GIT_CONFIG_KEY_1' => 'user.name', 'GIT_CONFIG_VALUE_1' => 'Spec',
      'GIT_CONFIG_KEY_2' => 'user.email', 'GIT_CONFIG_VALUE_2' => 'spec@example.com',
      'GIT_CONFIG_KEY_3' => 'core.fsmonitor', 'GIT_CONFIG_VALUE_3' => 'false',
      'GIT_CONFIG_KEY_4' => 'protocol.file.allow', 'GIT_CONFIG_VALUE_4' => 'always',
      '_GIT_OVERRIDE_SKIP' => nil,
      'PERSONAL_BIN_DIR' => nil
    }
  end

  around do |example|
    Dir.mktmpdir('git-scripts-spec-') do |dir|
      @tmp = File.realpath(dir)
      example.run
    end
  end

  attr_reader :tmp

  # A leading Hash is merged into the environment of the command.
  # @return [Array<(String, String, Process::Status, Float)>] stdout, stderr, status, seconds taken
  def run_cmd(*args, chdir: tmp)
    extra_env = args.first.is_a?(Hash) ? args.shift : {}
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out, err, status = Open3.capture3(env.merge(extra_env), *args, chdir: chdir)
    [out, err, status, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
  end

  def git!(*args, chdir: tmp)
    out, err, status, = run_cmd('git', *args, chdir: chdir)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  describe 'git with-retry' do
    it 'returns immediately for a command that finishes instantly' do
      _out, _err, status, seconds = run_cmd('git', 'with-retry', '60', '1', File::NULL, '-', 'true')
      expect(status.exitstatus).to eq(0)
      expect(seconds).to be < 1.5
    end

    it 'retries the full number of attempts and exits 1 when the command keeps failing' do
      _out, err, status, = run_cmd('git', 'with-retry', '60', '3', File::NULL, '-', 'sh', '-c', 'exit 3')
      expect(status.exitstatus).to eq(1)
      expect(err.scan(%r{^Attempt \d/3}).length).to eq(3)
      expect(err).to include('Failed (exit 3) on attempt 3/3')
    end

    it 'stops retrying after the first success' do
      marker = File.join(tmp, 'marker')
      script = "[ -e '#{marker}' ] && exit 0; : > '#{marker}'; exit 1"
      _out, err, status, = run_cmd('git', 'with-retry', '60', '5', File::NULL, '-', 'sh', '-c', script)
      expect(status.exitstatus).to eq(0)
      expect(err.scan(%r{^Attempt \d/5}).length).to eq(2)
    end

    it 'captures the child stderr in the file and replays it' do
      stderr_file = File.join(tmp, 'err.txt')
      _out, err, status, = run_cmd('git', 'with-retry', '60', '2', stderr_file, '-', 'sh', '-c', 'echo boom >&2; exit 1')
      expect(status.exitstatus).to eq(1)
      expect(File.read(stderr_file)).to eq("boom\n")
      expect(err.scan(/^boom$/).length).to eq(2)
    end

    it 'kills a command that makes no progress after the inactivity timeout' do
      _out, err, status, seconds = run_cmd('git', 'with-retry', '2', '1', File::NULL, '-', 'sleep', '60')
      expect(status.exitstatus).to eq(1)
      expect(err).to include('No progress for 2s on attempt 1/1')
      expect(seconds).to be < 10
    end

    # A stalled 'git fetch --unshallow' holds .git/shallow.lock for the whole pack download. git
    # removes its lock files when it is terminated, but not when it is killed with SIGKILL, and a
    # leftover lock fails every later attempt at once.
    it 'lets a stalled command clean up after itself (SIGTERM) instead of killing it outright' do
      lock = File.join(tmp, 'held.lock')
      script = %(trap 'rm -f "$1"; exit 143' TERM; : > "$1"; sleep 60 & wait)

      _out, err, status, seconds = run_cmd('git', 'with-retry', '2', '1', File::NULL, '-', 'sh', '-c', script, 'sh', lock)

      expect(status.exitstatus).to eq(1)
      expect(err).to include('No progress for 2s on attempt 1/1')
      expect(File).not_to exist(lock)
      expect(seconds).to be < 8
    end

    it 'does not leave a lock behind between attempts, so every retry really runs' do
      lock = File.join(tmp, 'held.lock')
      script = %(if [ -e "$1" ]; then exit 128; fi; trap 'rm -f "$1"; exit 143' TERM; : > "$1"; sleep 60 & wait)

      _out, err, _status, = run_cmd('git', 'with-retry', '1', '3', File::NULL, '-', 'sh', '-c', script, 'sh', lock)

      expect(err).not_to include('Failed (exit 128)')
      expect(err.scan('No progress for 1s').length).to eq(3)
    end

    it 'still kills a command that ignores SIGTERM, after the grace period' do
      script = %(trap '' TERM; sleep 60)

      _out, err, status, seconds = run_cmd({ 'WITH_RETRY_KILL_GRACE_SECS' => '1' }, 'git', 'with-retry', '1', '1', File::NULL, '-', 'sh', '-c', script)

      expect(status.exitstatus).to eq(1)
      expect(err).to include('No progress for 1s on attempt 1/1')
      expect(seconds).to be < 8
    end

    it 'stops the helper processes of a stalled command too, not just the command itself' do
      marker = File.join(tmp, 'helper.pid')
      script = %(sleep 60 & echo $! > "$1"; wait)

      run_cmd('git', 'with-retry', '1', '1', File::NULL, '-', 'sh', '-c', script, 'sh', marker)

      helper = File.read(marker).to_i
      expect { Process.kill(0, helper) }.to raise_error(Errno::ESRCH)
    end
  end

  describe 'git fo' do
    def make_remote(name)
      path = File.join(tmp, "#{name}.git")
      git!('init', '-q', '--bare', '-b', 'master', path)
      path
    end

    def push_commit(work, remote_path, file)
      File.write(File.join(work, file), file)
      git!('add', file, chdir: work)
      git!('commit', '-q', '-m', file, chdir: work)
      git!('push', '-q', remote_path, 'HEAD:master', chdir: work)
    end

    let(:origin) { make_remote('origin') }
    let(:work) do
      File.join(tmp, 'work').tap do |path|
        git!('init', '-q', '-b', 'master', path)
        git!('remote', 'add', 'origin', origin, chdir: path)
        push_commit(path, origin, 'one')
        git!('fetch', '-q', 'origin', chdir: path)
        git!('branch', '-q', '--set-upstream-to=origin/master', 'master', chdir: path)
      end
    end

    it 'fetches new commits and exits 0' do
      other = File.join(tmp, 'other')
      git!('clone', '-q', work, other)
      git!('remote', 'set-url', 'origin', origin, chdir: other)
      push_commit(other, origin, 'two')

      _out, _err, status, = run_cmd('git', 'fo', work)
      expect(status.exitstatus).to eq(0)
      expect(git!('rev-parse', 'origin/master', chdir: work).strip).to eq(git!('rev-parse', 'HEAD', chdir: other).strip)
    end

    it 'fails, reports the last error and still fetches the other remotes when one remote cannot be fetched' do
      git!('remote', 'add', 'aaa-bad', File.join(tmp, 'does-not-exist.git'), chdir: work)
      other = File.join(tmp, 'other')
      git!('clone', '-q', origin, other)
      push_commit(other, origin, 'two')

      out, err, status, = run_cmd('git', 'fo', work)
      expect(status.exitstatus).not_to eq(0)
      expect(out).to include('Fetching aaa-bad').and include('Fetching origin')
      expect(err).to include('could not fetch from aaa-bad').and include('Last error:').and include('does-not-exist.git')
      expect(git!('rev-parse', 'origin/master', chdir: work).strip).to eq(git!('rev-parse', 'HEAD', chdir: other).strip)
    end

    it 'does not rebase with --rebase when a fetch failed' do
      git!('remote', 'add', 'bad', File.join(tmp, 'does-not-exist.git'), chdir: work)
      before = git!('rev-parse', 'HEAD', chdir: work)
      _out, err, status, = run_cmd('git', 'fo', work, '--rebase')
      expect(status.exitstatus).not_to eq(0)
      expect(err).to include('Not rebasing')
      expect(git!('rev-parse', 'HEAD', chdir: work)).to eq(before)
    end

    context 'when the rebase onto the upstream conflicts' do
      before do
        File.write(File.join(work, 'one'), 'local change')
        git!('commit', '-q', '-am', 'local', chdir: work)
        other = File.join(tmp, 'other')
        git!('clone', '-q', origin, other)
        File.write(File.join(other, 'one'), 'remote change')
        git!('commit', '-q', '-am', 'remote', chdir: other)
        git!('push', '-q', origin, 'HEAD:master', chdir: other)
      end

      it 'aborts it and leaves the repository exactly as it was, instead of stopping half-way through' do
        before_head = git!('rev-parse', 'HEAD', chdir: work)

        _out, err, status, = run_cmd('git', 'fo', work, '--rebase')

        expect(status.exitstatus).not_to eq(0)
        expect(err).to include('conflicted').and include('aborted, nothing was changed')
        expect(File).not_to exist(File.join(work, '.git', 'rebase-merge'))
        expect(File).not_to exist(File.join(work, '.git', 'rebase-apply'))
        expect(git!('rev-parse', 'HEAD', chdir: work)).to eq(before_head)
        expect(git!('status', '--porcelain', chdir: work)).to eq('')
        expect(File.read(File.join(work, 'one'))).to eq('local change')
      end

      it 'can be repeated, because nothing was left behind' do
        2.times do
          _out, _err, status, = run_cmd('git', 'fo', work, '--rebase')
          expect(status.exitstatus).not_to eq(0)
          expect(File).not_to exist(File.join(work, '.git', 'rebase-merge'))
        end
      end

      it 'does not touch a rebase that is already in progress' do
        git!('fetch', '-q', 'origin', chdir: work)
        run_cmd('git', 'rebase', 'origin/master', chdir: work)
        expect(File).to exist(File.join(work, '.git', 'rebase-merge'))

        _out, err, status, = run_cmd('git', 'fo', work, '--rebase')

        expect(status.exitstatus).not_to eq(0)
        expect(err).to include('already in progress')
        expect(File).to exist(File.join(work, '.git', 'rebase-merge'))
        expect(File.read(File.join(work, 'one'))).to include('<<<<<<<')
      end
    end

    it 'rejects an unknown argument instead of treating it as a directory' do
      _out, err, status, = run_cmd('git', 'fo', '--bogus', chdir: work)
      expect(status.exitstatus).to eq(2)
      expect(err).to include('unknown argument: --bogus')
    end

    it 'works in a linked worktree, where .git is a file' do
      linked = File.join(tmp, 'linked')
      git!('worktree', 'add', '-q', '-b', 'linked-branch', linked, chdir: work)
      _out, _err, status, = run_cmd('git', 'fo', chdir: linked)
      expect(status.exitstatus).to eq(0)
    end
  end

  describe 'git fo on a shallow clone' do
    let(:origin) { File.join(tmp, 'origin.git') }
    let(:seed) { File.join(tmp, 'seed') }
    let(:clone) { File.join(tmp, 'clone') }

    before do
      git!('init', '-q', '--bare', '-b', 'master', origin)
      git!('init', '-q', '-b', 'master', seed)
      %w[a b c].each do |name|
        File.write(File.join(seed, name), name)
        git!('add', name, chdir: seed)
        git!('commit', '-q', '-m', name, chdir: seed)
      end
      git!('tag', 'old-tag', 'HEAD~2', chdir: seed)
      git!('branch', 'side', 'HEAD~1', chdir: seed)
      git!('push', '-q', origin, 'master', 'side', '--tags', chdir: seed)
      git!('clone', '-q', '--depth=1', "file://#{origin}", clone)
    end

    def shallow?
      git!('rev-parse', '--is-shallow-repository', chdir: clone).strip == 'true'
    end

    it 'unshallows the current branch first, then fetches every other branch and tag' do
      expect(shallow?).to be true

      out, _err, status, = run_cmd('git', 'fo', clone)

      expect(status.exitstatus).to eq(0)
      expect(out).to include('Unshallowing origin/master first')
      expect(shallow?).to be false
      expect(git!('rev-list', '--count', 'HEAD', chdir: clone).strip).to eq('3')
      expect(git!('rev-parse', '--verify', 'origin/side', chdir: clone)).not_to be_empty
      expect(git!('tag', '--list', 'old-tag', chdir: clone).strip).to eq('old-tag')
    end

    it 'asks the server for that one branch only, without tags, and then does an ordinary fetch' do
      _out, err, status, = run_cmd('git', 'fo', clone)

      expect(status.exitstatus).to eq(0)
      expect(err).to include('fetch --unshallow --no-tags origin +refs/heads/master:refs/remotes/origin/master')
      expect(err).not_to match(/fetch --unshallow origin$/)
      expect(err).to match(/timeout 60s\): git -C \S+ fetch origin$/)
    end

    it 'gives the unshallow a long inactivity allowance (the server is silent while it works) and the ordinary fetch a short one' do
      _out, err, = run_cmd('git', 'fo', clone)

      expect(err).to match(/timeout 900s\): git -C \S+ -c fetch.pruneTags=false fetch --unshallow/)
      expect(err).to match(/timeout 60s\): git -C \S+ fetch origin/)
    end

    it 'takes the allowance from GIT_FO_UNSHALLOW_TIMEOUT_SECS' do
      _out, err, = run_cmd({ 'GIT_FO_UNSHALLOW_TIMEOUT_SECS' => '321' }, 'git', 'fo', clone)

      expect(err).to match(/timeout 321s\): git -C \S+ -c fetch.pruneTags=false fetch --unshallow/)
    end

    it 'falls back to the remote HEAD when HEAD is detached' do
      git!('checkout', '-q', '--detach', chdir: clone)

      out, _err, status, = run_cmd('git', 'fo', clone)

      expect(status.exitstatus).to eq(0)
      expect(out).to include('Unshallowing origin/master first')
      expect(shallow?).to be false
    end

    it 'falls back to unshallowing every ref when no single branch can be picked' do
      git!('checkout', '-q', '--detach', chdir: clone)
      git!('remote', 'set-head', 'origin', '-d', chdir: clone)

      out, _err, status, = run_cmd('git', 'fo', clone)

      expect(status.exitstatus).to eq(0)
      expect(out).to include('no single branch to pick')
      expect(shallow?).to be false
    end

    it 'fails, without retrying forever, when the remote cannot be reached' do
      git!('remote', 'set-url', 'origin', File.join(tmp, 'gone.git'), chdir: clone)

      _out, err, status, = run_cmd({ 'GIT_FO_UNSHALLOW_TIMEOUT_SECS' => '5' }, 'git', 'fo', clone)

      expect(status.exitstatus).not_to eq(0)
      expect(err).to include('could not fetch from origin')
      expect(shallow?).to be true
    end
  end

  describe 'git fo on a partial (blobless) clone with a second remote' do
    let(:origin) { File.join(tmp, 'origin.git') }
    let(:second) { File.join(tmp, 'second.git') }
    let(:seed) { File.join(tmp, 'seed') }
    let(:clone) { File.join(tmp, 'clone') }

    before do
      [origin, second].each do |bare|
        git!('init', '-q', '--bare', '-b', 'master', bare)
        git!('config', 'uploadpack.allowFilter', 'true', chdir: bare)
        git!('config', 'uploadpack.allowAnySHA1InWant', 'true', chdir: bare)
      end
      git!('init', '-q', '-b', 'master', seed)
      File.write(File.join(seed, 'a.txt'), "one\n")
      git!('add', 'a.txt', chdir: seed)
      git!('commit', '-q', '-m', 'one', chdir: seed)
      [origin, second].each { |bare| git!('push', '-q', bare, 'HEAD:master', chdir: seed) }
      git!('clone', '-q', '--filter=blob:none', "file://#{origin}", clone)
      git!('remote', 'add', 'second', "file://#{second}", chdir: clone)
    end

    def remote_setting(key)
      out, _err, = run_cmd('git', 'config', '--get', "remote.second.#{key}", chdir: clone)
      out.strip
    end

    it 'registers the other remote as a promisor with the same filter, so its thin packs cannot need blobs this clone lacks' do
      expect(remote_setting('promisor')).to eq('')

      _out, _err, status, = run_cmd('git', 'fo', clone)

      expect(status.exitstatus).to eq(0)
      expect(remote_setting('promisor')).to eq('true')
      expect(remote_setting('partialclonefilter')).to eq('blob:none')
    end

    it 'leaves the other remotes alone in a repository that is not a partial clone' do
      plain = File.join(tmp, 'plain')
      git!('clone', '-q', origin, plain)
      git!('remote', 'add', 'second', second, chdir: plain)

      run_cmd('git', 'fo', plain)

      out, _err, = run_cmd('git', 'config', '--get', 'remote.second.promisor', chdir: plain)
      expect(out.strip).to eq('')
    end
  end

  describe 'git upreb' do
    it 'refuses to run on stale refs when the initial fetch fails' do
      origin = File.join(tmp, 'origin.git')
      git!('init', '-q', '--bare', '-b', 'master', origin)
      work = File.join(tmp, 'work')
      git!('clone', '-q', origin, work)
      File.write(File.join(work, 'a'), 'a')
      git!('add', 'a', chdir: work)
      git!('commit', '-q', '-m', 'a', chdir: work)
      git!('push', '-q', 'origin', 'HEAD:master', chdir: work)
      git!('remote', 'add', 'bad', File.join(tmp, 'does-not-exist.git'), chdir: work)

      _out, err, status, = run_cmd('git', 'upreb', work)
      expect(status.exitstatus).to eq(1)
      expect(err).to include('not rebasing or pushing on stale refs')
    end

    it 'rejects an unknown flag' do
      _out, err, status, = run_cmd('git', 'upreb', '--foo')
      expect(status.exitstatus).to eq(2)
      expect(err).to include('unknown argument: --foo')
    end
  end

  describe 'git unshallow on a blobless (partial) clone' do
    let(:origin) { File.join(tmp, 'origin.git') }
    let(:clone) { File.join(tmp, 'clone') }
    let(:seed) { File.join(tmp, 'seed') }

    before do
      git!('init', '-q', '--bare', '-b', 'master', origin)
      git!('config', 'uploadpack.allowFilter', 'true', chdir: origin)
      git!('config', 'uploadpack.allowAnySHA1InWant', 'true', chdir: origin)
      git!('init', '-q', '-b', 'master', seed)
      # Two versions of the file: the clone's checkout only fetches the newest blob, so the older
      # one is a genuinely missing object that a backfill has to fetch.
      %w[one two].each { |content| commit_file('a.txt', content) }
      git!('push', '-q', origin, 'HEAD:master', chdir: seed)
      git!('clone', '-q', '--filter=blob:none', "file://#{origin}", clone)
    end

    def commit_file(name, content)
      File.write(File.join(seed, name), "#{content}\n")
      git!('add', name, chdir: seed)
      git!('commit', '-q', '-m', "#{name} #{content}", chdir: seed)
    end

    def missing_blobs
      git!('rev-list', '--objects', '--all', '--reflog', '--indexed-objects', '--missing=print', chdir: clone).lines.count { |line| line.start_with?('?') }
    end

    def promisor_config
      out, _err, = run_cmd('git', 'config', '--get-regexp', 'promisor|partialclone', chdir: clone)
      out.strip
    end

    it 'keeps its promisor settings after a plain backfill, which is why it needs converting' do
      git!('backfill', '--all', chdir: clone)

      expect(missing_blobs).to eq(0)
      expect(promisor_config).to include('remote.origin.promisor true')
    end

    it 'converts a repo whose blobs are all present into a normal clone, without any fetch' do
      git!('backfill', '--all', chdir: clone)

      out, err, status, = run_cmd('git', 'unshallow', clone)

      expect(status.exitstatus).to eq(0)
      expect(out).to include('Converted to a normal clone')
      expect(out + err).not_to include('Fetching')
      expect(promisor_config).to eq('')
      expect(git!('fsck', '--full', chdir: clone)).not_to include('missing')
    end

    it 'says it is already a full clone on every later run' do
      git!('backfill', '--all', chdir: clone)
      run_cmd('git', 'unshallow', clone)

      out, err, status, = run_cmd('git', 'unshallow', clone)

      expect(status.exitstatus).to eq(0)
      expect(out).to include('Already a full clone')
      expect(out + err).not_to include('Fetching')
    end

    it 'backfills while blobs are missing and then converts, so the next run is a no-op' do
      expect(missing_blobs).to be > 0

      out, _err, status, = run_cmd('git', 'unshallow', clone)

      expect(status.exitstatus).to eq(0)
      expect(out).to include('Fetching origin')
      expect(out).to include('Converted to a normal clone')
      expect(missing_blobs).to eq(0)
      expect(promisor_config).to eq('')
      expect(run_cmd('git', 'unshallow', clone).first).to include('Already a full clone')
    end

    it 'also backfills blobs that only another branch references before converting' do
      git!('checkout', '-q', '-b', 'side', 'HEAD~1', chdir: seed)
      commit_file('only-on-side.txt', 'side')
      git!('push', '-q', origin, 'side', chdir: seed)
      git!('fetch', '-q', 'origin', chdir: clone)
      expect(missing_blobs).to be > 0

      _out, _err, status, = run_cmd('git', 'unshallow', clone)

      expect(status.exitstatus).to eq(0)
      expect(missing_blobs).to eq(0)
      expect(promisor_config).to eq('')
    end

    it 'does not convert, and still runs git fo, while a remote does not yet fetch all branches' do
      git!('backfill', '--all', chdir: clone)
      git!('config', 'remote.origin.fetch', '+refs/heads/master:refs/remotes/origin/master', chdir: clone)

      out, _err, status, = run_cmd('git', 'unshallow', clone)

      expect(status.exitstatus).to eq(0)
      expect(out).to include('Fetching origin')
      expect(git!('config', '--get', 'remote.origin.fetch', chdir: clone).strip).to eq('+refs/heads/*:refs/remotes/origin/*')
    end

    it 'does not look at the remote, and after conversion a plain fetch brings blobs along' do
      git!('backfill', '--all', chdir: clone)
      commit_file('b.txt', 'three')
      git!('push', '-q', origin, 'HEAD:master', chdir: seed)

      out, _err, = run_cmd('git', 'unshallow', clone)
      expect(out).to include('Converted to a normal clone')

      git!('fo', clone)
      expect(missing_blobs).to eq(0)
    end

    it 'backfills in large batches: one request carries many blobs instead of 500' do
      _out, err, status, = run_cmd('git', 'unshallow', clone)

      expect(status.exitstatus).to eq(0)
      expect(err).to include('backfill --min-batch-size=10000')
    end

    it 'takes the batch size from GIT_UNSHALLOW_BATCH_SIZE' do
      _out, err, status, = run_cmd({ 'GIT_UNSHALLOW_BATCH_SIZE' => '7' }, 'git', 'unshallow', clone)

      expect(status.exitstatus).to eq(0)
      expect(err).to include('backfill --min-batch-size=7')
    end

    it 'treats a failing completeness check as "missing" and never converts' do
      common = File.expand_path('../../scripts/shared/git-common.sh', __dir__)
      _out, _err, status, = run_cmd('sh', '-c', '. "$1"; has_missing_objects "$2"', 'sh', common, File.join(tmp, 'not-a-repo'))

      expect(status.exitstatus).to eq(0)
    end
  end
end
