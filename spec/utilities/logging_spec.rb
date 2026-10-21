# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'logging'

RSpec.describe Logging do
  # An object that mixes Logging in the way CLI scripts do (`include Logging` at top level).
  let(:includer) { Class.new { include Logging }.new }

  around do |example|
    described_class.state.reset!
    # Depth 1 == outermost script, so summaries/banners print.
    with_env('_DOTFILES_SCRIPT_DEPTH' => '1', 'LOG_FILE' => nil, 'LOG_LEVEL' => nil, 'DIRENV_IN_ENVRC' => nil,
             'FORCE_COLOR' => nil) { example.run }
    described_class.state.reset!
  end

  describe 'shared state' do
    it 'is the same object for module and included receivers' do
      expect(includer.state).to be(described_class.state)
    end

    it 'lets an includer record issues that Logging.step_warnings / step_errors see' do
      expect do
        includer.record_warning('w1')
        includer.record_error('e1')
      end.to output.to_stdout

      expect(described_class.step_warnings.size).to eq(1)
      expect(described_class.step_errors.size).to eq(1)
      expect(described_class.warnings?).to be true
      expect(described_class.errors?).to be true
    end

    it 'lets a bare print_script_summary report issues recorded through the module' do
      described_class.script_name = 'demo.rb'
      expect { described_class.record_warning('careful') }.to output.to_stdout

      expect { includer.print_script_summary }.to output(/1 warning\(s\)/).to_stdout
    end
  end

  describe '.record_warning / .record_error' do
    it 'prefixes entries with the script and section names' do
      described_class.script_name = 'demo.rb'
      described_class.current_section = 'Step A'
      expect { described_class.record_warning('something') }.to output(/something/).to_stdout

      expect(described_class.step_warnings.first).to eq('[demo.rb][Step A] something')
    end

    it "uses 'unknown' when no section was set" do
      described_class.script_name = 'demo.rb'
      expect { described_class.record_error('boom') }.to output.to_stdout

      expect(described_class.step_errors.first).to eq('[demo.rb][unknown] boom')
    end
  end

  describe 'handing issues to a collecting shell script' do
    around do |example|
      Dir.mktmpdir('issues-spec-') do |dir|
        @issues = Pathname(dir).join('issues')
        example.run
      end
    end

    before { EnvVars.remove_instance_variable(:@_issues_file) if EnvVars.instance_variable_defined?(:@_issues_file) }
    after { EnvVars.remove_instance_variable(:@_issues_file) if EnvVars.instance_variable_defined?(:@_issues_file) }

    it 'appends one tab-separated line per recorded issue, in order, keeping earlier content' do
      @issues.write("warning\told\n")
      described_class.script_name = 'demo.rb'
      described_class.current_section = 'Step A'

      with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) do
        expect do
          described_class.record_warning('w1')
          described_class.record_error('e1')
        end.to output.to_stdout
      end

      expect(@issues.read).to eq("warning\told\nwarning\t[demo.rb][Step A] w1\nerror\t[demo.rb][Step A] e1\n")
    end

    it 'flattens multi-line messages so each issue stays on one line' do
      described_class.script_name = 'demo.rb'

      with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) do
        expect { described_class.record_error("first\n  second") }.to output.to_stdout
      end

      expect(@issues.readlines.length).to eq(1)
      expect(@issues.read).to include('first second')
    end

    describe 'in the process that owns the summary' do
      before { described_class.script_name = 'owner.sh' }

      def child_records(message)
        env = { '_DOTFILES_ISSUES_FILE' => @issues.to_s }
        code = %(require 'logging'; Logging.script_name = 'child.rb'; Logging.record_warning(#{message.inspect}))
        system(env, RbConfig.ruby, '-I', UTILITIES_DIR, '-e', code, out: File::NULL, err: File::NULL)
      end

      it 'adopts what the shell recorded, empties the file and then keeps its own issues in memory only' do
        @issues.write("warning\t[fresh.sh][Xcode] softwareupdate failed\nerror\t[fresh.sh][Xcode] boom\n")

        with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) do
          described_class.adopt_issues_file
          expect { described_class.record_warning('own') }.to output.to_stdout
        end

        expect(described_class.step_warnings).to eq(['[fresh.sh][Xcode] softwareupdate failed', '[owner.sh][unknown] own'])
        expect(described_class.step_errors).to eq(['[fresh.sh][Xcode] boom'])
        expect(@issues.read).to eq('')
      end

      it 'merges what child processes appended, once, and deletes the file' do
        with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) do
          described_class.adopt_issues_file
          expect { described_class.record_warning('own') }.to output.to_stdout
          expect(child_records('from child')).to be true
          described_class.merge_issues_file
        end

        expect(described_class.step_warnings).to eq(['[owner.sh][unknown] own', '[child.rb][unknown] from child'])
        expect(@issues).not_to exist
      end

      it 'ignores malformed lines' do
        @issues.write("nonsense\nwarning\n\nwarning\tok\n")

        with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) { described_class.merge_issues_file }

        expect(described_class.step_warnings).to eq(['ok'])
      end

      it 'does nothing when no issues file is configured' do
        with_env('_DOTFILES_ISSUES_FILE' => nil) do
          described_class.adopt_issues_file
          described_class.merge_issues_file
        end

        expect(described_class.step_warnings).to be_empty
        expect(described_class.state.issues_file_owner).to be false
      end
    end

    it 'writes nothing, and does not fail, when no file is configured' do
      with_env('_DOTFILES_ISSUES_FILE' => nil) do
        expect { described_class.record_warning('w') }.to output.to_stdout
      end

      expect(@issues).not_to exist
    end

    it 'ignores an unwritable file instead of breaking the run' do
      with_env('_DOTFILES_ISSUES_FILE' => @issues.join('missing-dir', 'f').to_s) do
        expect { described_class.record_warning('w') }.to output.to_stdout
      end

      expect(described_class.step_warnings.length).to eq(1)
    end
  end

  describe '.issue_summary_parts' do
    it 'is empty when nothing was recorded' do
      expect(described_class.issue_summary_parts).to eq([])
    end

    it 'lists errors first, then warnings, each with a count and the joined messages' do
      described_class.script_name = 'demo.rb'
      expect do
        described_class.record_warning('w1')
        described_class.record_error('e1')
        described_class.record_error('e2')
      end.to output.to_stdout

      parts = described_class.issue_summary_parts

      expect(parts.size).to eq(2)
      expect(parts[0]).to match(/\A2 error\(s\): .*e1; .*e2\z/)
      expect(parts[1]).to match(/\A1 warning\(s\): .*w1\z/)
    end

    it 'omits the collection that is empty' do
      described_class.script_name = 'demo.rb'
      expect { described_class.record_warning('only') }.to output.to_stdout

      expect(described_class.issue_summary_parts.map { |part| part[/\A\d+ \w+/] }).to eq(['1 warning'])
    end
  end

  describe '.print_script_summary' do
    it 'prints nothing when there is no issue and no message' do
      expect { described_class.print_script_summary }.not_to output.to_stdout
    end

    it 'prints the message, then the grouped warnings and errors' do
      described_class.script_name = 'demo.rb'
      expect do
        described_class.record_warning('w')
        described_class.record_error('e')
      end.to output.to_stdout

      expect { described_class.print_script_summary(nil, 'All done') }.to output(/All done.*1 warning\(s\).*1 error\(s\)/m).to_stdout
    end

    it 'is silent for nested scripts (depth > 1)' do
      with_env('_DOTFILES_SCRIPT_DEPTH' => '2') do
        expect { described_class.print_script_summary(nil, 'nested') }.not_to output.to_stdout
      end
    end
  end

  describe '.with_step' do
    it 'sets the section, prints the header and a timing line, and always pops the step' do
      expect { described_class.with_step('Install', 'Installing') { :ok } }.to output(/Installing.*Step:/m).to_stdout
      expect(described_class.state.current_section).to eq('Install')
      expect(described_class.state.step_start_times).to be_empty
    end

    it 'pops the step even when the block raises' do
      expect do
        expect { described_class.with_step('Boom') { raise 'x' } }.to raise_error('x')
      end.to output.to_stdout
      expect(described_class.state.step_start_times).to be_empty
    end
  end

  describe '.section_header' do
    it 'tracks the section automatically unless it was set manually' do
      expect { described_class.section_header('First') }.to output.to_stdout
      expect(described_class.state.current_section).to eq('First')

      described_class.current_section = 'Pinned'
      expect { described_class.section_header('Second') }.to output.to_stdout
      expect(described_class.state.current_section).to eq('Pinned')
    end
  end

  describe 'log level filtering' do
    it 'shows info by default' do
      expect { described_class.info('hello') }.to output(/hello/).to_stdout
    end

    it 'hides info and shows warn when LOG_LEVEL=warn' do
      with_env('LOG_LEVEL' => 'warn') do
        expect { described_class.info('quiet') }.not_to output.to_stdout
        expect { described_class.warn('loud') }.to output(/loud/).to_stdout
      end
    end

    it 'falls back to info for an unknown LOG_LEVEL' do
      with_env('LOG_LEVEL' => 'bogus') do
        expect { described_class.info('shown') }.to output(/shown/).to_stdout
      end
    end

    it 'is suppressed inside a direnv subshell' do
      with_env('DIRENV_IN_ENVRC' => '1') do
        expect { described_class.info('hidden') }.not_to output.to_stdout
      end
    end
  end

  describe '.error' do
    it 'prints and raises with the message' do
      expect do
        expect { described_class.error('fatal') }.to raise_error(RuntimeError, 'fatal')
      end.to output(/fatal/).to_stdout
    end
  end

  describe 'LOG_FILE sink' do
    it 'writes text entries without ANSI codes' do
      Dir.mktmpdir do |dir|
        log = File.join(dir, 'out.log')
        with_env('LOG_FILE' => log) do
          expect { described_class.warn('to-file') }.to output.to_stdout
        end
        expect(File.read(log)).to match(/\[WARN\] .*to-file/)
        expect(File.read(log)).not_to include("\e[")
      end
    end

    it 'writes JSON entries when LOG_FORMAT=json' do
      Dir.mktmpdir do |dir|
        log = File.join(dir, 'out.log')
        with_env('LOG_FILE' => log, 'LOG_FORMAT' => 'json') do
          expect { described_class.info('as-json') }.to output.to_stdout
        end
        entry = JSON.parse(File.read(log).lines.first)
        expect(entry).to include('level' => 'INFO', 'depth' => 1)
        expect(entry['message']).to include('as-json')
        expect(entry['timestamp']).to match(/\A\d{4}-\d\d-\d\dT/)
      end
    end

    it 'rotates an oversized log file, keeping numbered backups' do
      Dir.mktmpdir do |dir|
        log = File.join(dir, 'out.log')
        File.write(log, 'x' * (Logging::Sinks::MAX_LOG_BYTES + 1))
        with_env('LOG_FILE' => log) do
          expect { described_class.info('after-rotate') }.to output.to_stdout
        end
        expect(File.size("#{log}.1")).to be > Logging::Sinks::MAX_LOG_BYTES
        expect(File.read(log)).to include('after-rotate')
      end
    end
  end

  describe '.format_duration' do
    it 'formats seconds as HHh:MMm:SSs' do
      expect(described_class.format_duration(3_725)).to eq('01h:02m:05s')
      expect(described_class.format_duration(5)).to eq('00h:00m:05s')
    end
  end

  describe '.print_results_summary' do
    it 'prints totals and the failed items' do
      results = { total: 3, successful: %w[a b], failed: %w[c], skipped: 0 }
      expect { described_class.print_results_summary(results) }.to output(/Total repositories: 3.*Failed repository:.*- 'c'/m).to_stdout
    end
  end

  describe '.join_array' do
    it 'bullets and quotes each item at the requested nesting level' do
      expect(described_class.join_array(%w[a b], :red, level: 1)).to eq("  - 'a'\n  - 'b'")
    end

    it 'returns an empty string for an empty list' do
      expect(described_class.join_array([], :red)).to eq('')
    end
  end

  describe '.run_script_result' do
    it "returns the block's value even though run_script itself returns nil when nested" do
      allow(described_class).to receive(:run_script) { |*_args, &block| block.call(nil) && nil }

      expect(described_class.run_script_result('x', 'msg') { :outcome }).to eq(:outcome)
      expect(described_class.run_script_result('x', 'msg') { false }).to be(false)
    end

    it 'passes the name and message through' do
      expect(described_class).to receive(:run_script).with('named', 'done').and_yield

      described_class.run_script_result('named', 'done') { true }
    end

    it 'names the script after its caller when no name is given' do
      expect(described_class).to receive(:run_script).with('logging_spec', nil).and_yield

      described_class.run_script_result { true }
    end

    it 'runs the block once through the real run_script when nested' do
      EnvVars.script_depth = 1
      calls = 0

      result = described_class.run_script_result('nested') { (calls += 1) > 0 }

      expect(result).to be(true)
      expect(calls).to eq(1)
    ensure
      EnvVars.script_depth = 0
    end
  end
end
