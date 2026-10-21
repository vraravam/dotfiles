# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

# Pure-shell tests for the helpers in scripts/osx-defaults.sh. The helper
# functions are extracted from the script (running the script itself would
# change the machine) and exercised in `zsh -c` with a PATH shim that shadows
# `defaults`/`scutil`/`sudo`, so no real preference domain is ever touched. The
# only real `defaults` calls go to plist FILES under a temp dir.
RSpec.describe 'scripts/osx-defaults.sh' do
  let(:script) { File.expand_path('../scripts/osx-defaults.sh', __dir__) }
  let(:tmp) { Dir.mktmpdir('osx-defaults-spec') }
  let(:shim_dir) { File.join(tmp, 'shims') }
  let(:calls_log) { File.join(tmp, 'calls.log') }

  after { FileUtils.remove_entry(tmp) }

  # Source of every top-level function between the batched-write helpers and the
  # dry-run section (batched writes, stamps, computer naming).
  def helper_source
    lines = File.readlines(script, encoding: 'UTF-8')
    start = lines.index { |l| l.start_with?('typeset -ga _dw_doms') }
    stop = lines.index { |l| l.start_with?('# Dry run (OSX_DEFAULTS_DRY_RUN=1)') }
    lines[start...stop].join
  end

  def write_shim(name, body)
    FileUtils.mkdir_p(shim_dir)
    path = File.join(shim_dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    FileUtils.chmod(0o755, path)
  end

  # Runs zsh code with the helpers loaded and shims first on PATH.
  def zsh(code, env = {})
    prelude = "source #{File.join(tmp, 'helpers.zsh')}\n"
    File.write(File.join(tmp, 'helpers.zsh'), helper_source)
    full_env = { 'PATH' => "#{shim_dir}:#{ENV.fetch('PATH')}", 'CALLS' => calls_log,
                 'XDG_CACHE_HOME' => File.join(tmp, 'cache'), 'USER' => 'tester' }.merge(env)
    out, err, status = Open3.capture3(full_env, 'zsh', '-c', prelude + code)
    [out, err, status]
  end

  def calls
    File.exist?(calls_log) ? File.readlines(calls_log, chomp: true) : []
  end

  def export_xml(domain_path)
    out, = Open3.capture2('defaults', 'export', domain_path, '-')
    out2, = Open3.capture2('plutil', '-convert', 'xml1', '-o', '-', '-', stdin_data: out)
    out2
  end

  it 'has a valid zsh syntax' do
    _out, err, status = Open3.capture3('zsh', '-n', script)
    expect([status.success?, err]).to eq([true, ''])
  end

  describe 'batched scalar writes (_dw / _dw_flush)' do
    # Mirrors the call shapes found in the script, including fallbacks, equal-value
    # type quirks of `defaults write`, and keys/strings needing escaping.
    let(:sequence) do
      <<~'ZSH'
        # UTF-8 bytes for e-acute and a check mark (spec source stays ASCII-only).
        nonascii=$'\xc3\xa9 \xe2\x9c\x93'
        run() {
          local f=$1 d=$2
          $f $d b1 -bool true; $f $d b2 -bool no; $f $d i1 -int -12; $f $d i2 -int 0; $f $d i3 -int 123456789012345
          $f $d f1 -float 15; $f $d f2 -float 0.5; $f $d f3 -float -0.25; $f $d f4 -float 0.375
          $f $d s1 -string 12; $f $d s2 -string "q\"u'o & <t> ${nonascii} x"; $f $d s3 -string ""; $f $d 'key with space' -string v
          $f $d u1 172; $f $d u2 0; $f $d 'u 3' 14
          $f $d chg -string now-string; $f $d dupe -int 2; $f $d dupe -int 3
          $f $d Clicking -int 1; $f $d Clicking -bool true; $f $d Fl -bool false; $f $d Fl -int 0; $f $d Fl -float 0
          $f $d N5 -float 15; $f $d N5 -int 15; $f $d N5 -int 16; $f $d N5 -float 16
          $f $d S1 -string 1; $f $d S1 -int 1; $f $d S1 -bool true; $f $d X -int 1; $f $d X -string 1
          $f $d f5 -float 0.1; $f $d f6 -float 2.576526409646739; $f $d i4 -int 007; $f $d u4 foo; $f $d u5 0.5
          $f $d 'k[x]' -bool true; $f $d b6 -integer 4; $f $d s4 -string "tab	here"; $f $d after -int 1
        }
        old() { defaults write "$@" 2>/dev/null }
        for d in $A $B; do defaults write $d keep -string old; defaults write $d chg -bool false; defaults write $d dupe -int 1; done
        run old $A
        run _dw $B
        _dw_flush
      ZSH
    end

    it 'stores exactly the same keys, types and values as individual defaults writes' do
      a = File.join(tmp, 'domain_a')
      b = File.join(tmp, 'domain_b')
      _out, err, status = zsh(sequence, 'A' => a, 'B' => b)
      expect(status.success?).to be(true), err
      expect(export_xml(a)).to eq(export_xml(b))
      expect(export_xml(b)).to include('<key>keep</key>', '<real>0.10000000149011612</real>')
    end

    it 'issues one import per domain for a run of scalar writes' do
      write_shim('defaults', 'echo "defaults $*" >>"$CALLS"; cat >/dev/null; exit 0')
      _out, err, status = zsh(<<~ZSH)
        _dw com.example.one a -bool true
        _dw com.example.one b -int 5
        _dw com.example.one c -string x
        _dw com.example.two d -float 15
        _dw_flush
        _dw_flush
      ZSH
      expect(status.success?).to be(true), err
      expect(calls).to eq(['defaults import com.example.one -', 'defaults import com.example.two -'])
    end

    it 'flushes pending writes before an unbatchable write, preserving order' do
      write_shim('defaults', 'echo "defaults $*" >>"$CALLS"; cat >/dev/null; exit 0')
      _out, _err, status = zsh(<<~ZSH)
        _dw com.example.one a -bool true
        _dw com.example.one b -float 0.1
        _dw com.example.one c -array x y
        _dw_flush
      ZSH
      expect(status.success?).to be(true)
      expect(calls).to eq(['defaults import com.example.one -',
                           'defaults write com.example.one b -float 0.1',
                           'defaults write com.example.one c -array x y'])
    end

    it 'replays the writes one by one when the import fails' do
      write_shim('defaults', 'echo "defaults $*" >>"$CALLS"; cat >/dev/null; [ "$1" = import ] && exit 1; exit 0')
      _out, _err, status = zsh(<<~ZSH)
        _dw com.example.one a -bool true
        _dw com.example.one b -int 5
        _dw com.example.one a -bool false
        _dw_flush
      ZSH
      expect(status.success?).to be(true)
      expect(calls).to eq(['defaults import com.example.one -',
                           'defaults write com.example.one a -bool true',
                           'defaults write com.example.one b -int 5',
                           'defaults write com.example.one a -bool false'])
    end

    it 'never batches NSGlobalDomain, path domains or unsafe values' do
      write_shim('defaults', 'echo "defaults $*" >>"$CALLS"; cat >/dev/null; exit 0')
      _out, _err, status = zsh(<<~ZSH)
        _dw NSGlobalDomain a -bool true
        _dw /Library/Preferences/x a -bool true
        _dw com.example.one a -bool 1
        _dw com.example.one a -int 007
        _dw com.example.one a -string "ctl$(printf '\\001')"
        _dw_flush
      ZSH
      expect(status.success?).to be(true)
      expect(calls.size).to eq(5)
      expect(calls).to all(start_with('defaults write '))
    end

    it 'turns into plain defaults writes with OSX_DEFAULTS_NO_BATCH' do
      write_shim('defaults', 'echo "defaults $*" >>"$CALLS"; exit 0')
      _out, _err, status = zsh("_dw com.example.one a -bool true\n_dw_flush", 'OSX_DEFAULTS_NO_BATCH' => '1')
      expect(status.success?).to be(true)
      expect(calls).to eq(['defaults write com.example.one a -bool true'])
    end
  end

  describe 'once-per-macOS-version stamps' do
    it 'is not current until recorded, then current for the same version only' do
      out, err, status = zsh(<<~'ZSH', 'OSX_DEFAULTS_FORCE' => '')
        _OSX_VERSION=15.5
        if _osx_stamp_is_current t; then echo before=current; else echo before=stale; fi
        _osx_stamp_record t
        if _osx_stamp_is_current t; then echo after=current; else echo after=stale; fi
        _OSX_VERSION=15.6
        if _osx_stamp_is_current t; then echo upgraded=current; else echo upgraded=stale; fi
      ZSH
      expect(status.success?).to be(true), err
      expect(out.split).to eq(%w[before=stale after=current upgraded=stale])
    end

    it 'ignores the stamp when OSX_DEFAULTS_FORCE is set' do
      out, = zsh(<<~'ZSH', 'OSX_DEFAULTS_FORCE' => '1')
        _OSX_VERSION=15.5
        _osx_stamp_record t
        if _osx_stamp_is_current t; then echo current; else echo stale; fi
      ZSH
      expect(out.strip).to eq('stale')
    end

    it 'never reports current when the macOS version is unknown' do
      out, = zsh(<<~'ZSH', 'OSX_DEFAULTS_FORCE' => '')
        _OSX_VERSION=''
        _osx_stamp_record t
        if _osx_stamp_is_current t; then echo current; else echo stale; fi
      ZSH
      expect(out.strip).to eq('stale')
      expect(Dir.glob(File.join(tmp, 'cache', '*'))).to be_empty
    end
  end

  describe '_set_computer_names' do
    before do
      write_shim('sudo', 'echo "sudo $*" >>"$CALLS"; exit 0')
      write_shim('defaults', 'echo "defaults $*" >>"$CALLS"; echo "${NETBIOS:-}"; [ -n "${NETBIOS:-}" ]')
      write_shim('scutil', <<~'SH'.chomp)
        case "$2" in
          ComputerName) v="$SC_COMPUTER" ;;
          HostName) v="$SC_HOST" ;;
          LocalHostName) v="$SC_LOCAL" ;;
        esac
        [ -n "$v" ] && echo "$v"
      SH
    end

    let(:fn_env) { { 'SC_COMPUTER' => '', 'SC_HOST' => '', 'SC_LOCAL' => '', 'NETBIOS' => '' } }
    # Stand-ins for the .shellrc helpers the function relies on.
    let(:setup) do
      <<~'ZSH'
        current_timestamp_for_filename() { eval "${1}=2030-01-02-03-04"; }
        is_zero_string() { [[ -z "${1:-}" ]]; }
        info() { :; }
      ZSH
    end

    it 'sets all four names with one timestamp on a machine that was never named' do
      _out, err, status = zsh("#{setup}\n_set_computer_names", fn_env)
      expect(status.success?).to be(true), err
      sets = calls.grep(/^sudo/)
      expect(sets).to include("sudo scutil --set ComputerName IND-CHN-Tester's MBP-2030-01-02-03-04",
                              'sudo scutil --set HostName Tester-2030-01-02-03-04',
                              'sudo scutil --set LocalHostName Tester-2030-01-02-03-04')
      expect(sets.join).to include('NetBIOSName -string Tester-2030-01-02-03-04')
    end

    it 'leaves already-named machines alone (no rename on rerun)' do
      env = fn_env.merge('SC_COMPUTER' => "IND-CHN-Tester's MBP-2024-05-06-07-08", 'SC_HOST' => 'Tester-2024-05-06-07-08',
                         'SC_LOCAL' => 'Tester-2024-05-06-07-08', 'NETBIOS' => 'Tester-2024-05-06-07-08')
      _out, err, status = zsh("#{setup}\n_set_computer_names", env)
      expect(status.success?).to be(true), err
      expect(calls.grep(/^sudo/)).to be_empty
    end

    it 'fills in only the missing names, reusing the existing timestamp' do
      env = fn_env.merge('SC_COMPUTER' => "IND-CHN-Tester's MBP-2024-05-06-07-08")
      _out, _err, status = zsh("#{setup}\n_set_computer_names", env)
      expect(status.success?).to be(true)
      sets = calls.grep(/^sudo/).join("\n")
      expect(sets).not_to include('ComputerName')
      expect(sets).to include('HostName Tester-2024-05-06-07-08', 'LocalHostName Tester-2024-05-06-07-08')
    end
  end

  describe 'ask (silent mode)' do
    let(:ask_source) do
      lines = File.readlines(script, encoding: 'UTF-8')
      start = lines.index { |l| l.start_with?('ask() {') }
      stop = lines.index { |l| l.start_with?('# Writes a trackpad gesture') }
      lines[start...stop].join
    end
    let(:prelude) do
      <<~'ZSH'
        is_zero_string() { [[ -z "${1:-}" ]]; }
        green() { print -r -- "$*"; }
      ZSH
    end

    def ask_zsh(code)
      Open3.capture3('zsh', '-c', "#{prelude}\n#{ask_source}\n#{code}", stdin_data: '')
    end

    it 'answers from the default without reading the terminal, and never loops without a default' do
      out, err, status = ask_zsh(<<~'ZSH')
        auto=Y
        ask 'a' 'Y'; echo "yes-default=$?"
        ask 'b' 'N'; echo "no-default=$?"
        ask 'c'; echo "no-answer=$?"
      ZSH
      expect(status.success?).to be(true), err
      expect(out.scan(/(?:yes-default|no-default|no-answer)=\d/)).to eq(%w[yes-default=0 no-default=1 no-answer=1])
    end

    it 'gives up on EOF in interactive mode instead of spinning' do
      out, = ask_zsh("auto=N\nask 'x' 'Y'; echo rc=$?")
      expect(out).to include('rc=1')
    end
  end

  # Runs the whole script in dry-run mode: every `defaults` call is redirected onto plist FILES in a
  # scratch directory, sudo/killall/scutil/... are recorded instead of run, HOME is a scratch HOME.
  # As a second safety net the process runs under a sandbox profile that denies file writes outside
  # the temp directories (macOS only; the examples are skipped where sandbox-exec is missing).
  describe 'dry run' do
    let(:zdotdir) { ENV['ZDOTDIR'].to_s }
    let(:profile) { File.join(tmp, 'dry-run.sb') }

    before do
      skip 'ZDOTDIR/.aliases not available' unless File.exist?(File.join(zdotdir, '.aliases'))
      skip 'sandbox-exec not available' unless File.executable?('/usr/bin/sandbox-exec')
      real_tmp = File.realpath(tmp)
      File.write(profile, <<~SB)
        (version 1)
        (allow default)
        (deny file-write* (require-not (require-any (subpath "#{real_tmp}") (subpath "/private/tmp") (subpath "/private/var/folders") (subpath "/dev"))))
      SB
    end

    def run_dry_run(out, extra_env = {})
      env = { 'OSX_DEFAULTS_DRY_RUN' => '1', 'OSX_DEFAULTS_DRY_RUN_OUT' => out, 'TMPDIR' => File.realpath(tmp) }.merge(extra_env)
      Open3.capture3(env, '/usr/bin/sandbox-exec', '-f', profile, 'zsh', script, '-s', stdin_data: '')
    end

    def helper_calls(report)
      File.readlines(report, chomp: true).grep(/\A(kill_login_item_apps|restart_login_item_apps|suspend_softwareupdate_schedule|resume_softwareupdate_schedule|reload_macos_prefs)\z/)
    end

    it 'produces the same final state for the batched and the one-by-one code paths', :aggregate_failures do
      old_out = File.join(tmp, 'old.txt')
      new_out = File.join(tmp, 'new.txt')
      _o, old_err, old_status = run_dry_run(old_out, 'OSX_DEFAULTS_NO_BATCH' => '1')
      _o, new_err, new_status = run_dry_run(new_out)
      expect(old_status.success?).to be(true), old_err
      expect(new_status.success?).to be(true), new_err
      expect(File.read(old_out)).to include('##### domain com.apple.dock', '##### domain eu.exelban.Stats')
      expect(File.read(new_out)).to eq(File.read(old_out))
    end

    it 'runs the app/schedule/reload helpers when DOTFILES_APPS_BRACKETED is unset' do
      out = File.join(tmp, 'unset.txt')
      _o, err, status = run_dry_run(out, 'DOTFILES_APPS_BRACKETED' => nil)
      expect(status.success?).to be(true), err
      expect(helper_calls(out)).to eq(%w[kill_login_item_apps suspend_softwareupdate_schedule reload_macos_prefs])
    end

    it 'calls none of the app/schedule/reload helpers when DOTFILES_APPS_BRACKETED is set' do
      out = File.join(tmp, 'set.txt')
      _o, err, status = run_dry_run(out, 'DOTFILES_APPS_BRACKETED' => '1')
      expect(status.success?).to be(true), err
      expect(helper_calls(out)).to be_empty
      # The EXIT trap runs after the report is written; its calls land in the scratch command log.
      logs = Dir.glob(File.join(tmp, 'osx-defaults-dry-run.*', 'commands.log'))
      expect(logs.size).to eq(1)
      expect(File.read(logs.first)).not_to match(/^(kill_login_item_apps|restart_login_item_apps|suspend_softwareupdate_schedule|resume_softwareupdate_schedule|reload_macos_prefs)$/)
    end

    it 'never reads from the terminal in silent mode' do
      source = File.read(script, encoding: 'UTF-8')
      expect(source.lines.grep(/^\s*read\b/).size).to eq(1)
    end
  end
end
