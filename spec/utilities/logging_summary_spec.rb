# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'logging'

# Complements logging_spec.rb (which covers the summary printing, the issues-file hand-over
# and format_duration) with the query helpers and the issues-file edge cases.
RSpec.describe Logging::Summary do
  around do |example|
    Logging.state.reset!
    with_env('LOG_FILE' => nil, 'LOG_LEVEL' => nil, '_DOTFILES_SCRIPT_DEPTH' => '1',
             'DIRENV_IN_ENVRC' => nil, '_DOTFILES_ISSUES_FILE' => nil) { example.run }
    Logging.state.reset!
  end

  before do
    EnvVars.remove_instance_variable(:@_issues_file) if EnvVars.instance_variable_defined?(:@_issues_file)
    Logging.script_name = 'demo.rb'
    Logging.current_section = 'Step A'
  end

  after do
    EnvVars.remove_instance_variable(:@_issues_file) if EnvVars.instance_variable_defined?(:@_issues_file)
  end

  describe 'issue queries' do
    it 'reports nothing when nothing was recorded' do
      expect(Logging.warnings?).to be false
      expect(Logging.errors?).to be false
      expect(Logging.step_warnings).to eq([])
      expect(Logging.step_errors).to eq([])
    end

    it 'tells warnings and errors apart' do
      expect { Logging.record_warning('w') }.to output.to_stdout

      expect(Logging.warnings?).to be true
      expect(Logging.errors?).to be false

      expect { Logging.record_error('e') }.to output.to_stdout

      expect(Logging.errors?).to be true
    end

    it 'prefixes each recorded entry with the script and section' do
      expect { Logging.record_warning('w') }.to output.to_stdout

      expect(Logging.step_warnings).to eq(['[demo.rb][Step A] w'])
    end

    it 'falls back to "unknown" when neither script nor section is known' do
      Logging.state.reset!

      expect { Logging.record_error('e') }.to output.to_stdout

      expect(Logging.step_errors.first).to match(/\A\[.+\]\[unknown\] e\z/)
    end

    it 'exposes the live collections, not copies' do
      expect(Logging.step_warnings).to equal(Logging.state.warnings)
      expect(Logging.step_errors).to equal(Logging.state.errors)
    end
  end

  describe '.issue_summary_parts' do
    it 'lists errors before warnings, each with a count and the entries joined by "; "' do
      expect do
        Logging.record_warning('w1')
        Logging.record_error('e1')
        Logging.record_error('e2')
      end.to output.to_stdout

      parts = Logging.issue_summary_parts

      expect(parts.size).to eq(2)
      expect(parts[0]).to start_with('2 error(s): ').and include('e1; ').and include('e2')
      expect(parts[1]).to start_with('1 warning(s): ').and include('w1')
    end
  end

  describe 'issues file' do
    around do |example|
      Dir.mktmpdir('summary-spec-') do |dir|
        @issues = Pathname(dir).join('issues')
        example.run
      end
    end

    it 'does nothing when no issues file is configured' do
      expect { Logging.adopt_issues_file }.not_to raise_error
      expect { Logging.merge_issues_file }.not_to raise_error
      expect(Logging.state.issues_file_owner).to be false
    end

    it 'skips blank lines, unknown severities and lines without an entry when loading' do
      @issues.write("warning\tkept w\nbogus\tignored\nerror\n\nerror\tkept e\n")

      with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) { Logging.merge_issues_file }

      expect(Logging.step_warnings).to eq(['kept w'])
      expect(Logging.step_errors).to eq(['kept e'])
    end

    it 'deletes the file after merging' do
      @issues.write("warning\tw\n")

      with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) { Logging.merge_issues_file }

      expect(@issues).not_to exist
    end

    it 'tolerates a configured file that does not exist yet' do
      with_env('_DOTFILES_ISSUES_FILE' => @issues.to_s) do
        expect { Logging.merge_issues_file }.not_to raise_error
      end

      expect(Logging.warnings?).to be false
    end

    it 'never fails the real work when the issues file cannot be written' do
      with_env('_DOTFILES_ISSUES_FILE' => @issues.join('missing-dir', 'issues').to_s) do
        expect { Logging.record_error('still recorded in memory') }.to output.to_stdout
      end

      expect(Logging.step_errors.size).to eq(1)
    end
  end

  describe '.print_script_summary' do
    it 'prints nothing when this is not the outermost script' do
      with_env('_DOTFILES_SCRIPT_DEPTH' => '2') do
        expect { Logging.record_warning('w') }.to output.to_stdout
        expect { Logging.print_script_summary }.not_to output.to_stdout
      end
    end

    it 'prints the optional message even when there are no issues' do
      expect { Logging.print_script_summary(nil, 'all good') }.to output(/all good/).to_stdout
    end
  end
end
