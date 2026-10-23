# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require_relative '../scripts/ruby-lint'

RSpec.describe RubyLint do
  around do |example|
    Dir.mktmpdir('ruby-lint-spec-') do |dir|
      @target = Pathname(dir)
      example.run
    end
  end

  before do
    Logging.state.reset!
    allow(Logging).to receive(:info)
    allow(Logging).to receive(:success)
    allow(Logging).to receive(:warn)
    allow(Logging).to receive(:error)
    allow(described_class).to receive(:puts)
  end

  after { Logging.state.reset! }

  def installed(*commands)
    allow(PathUtils).to receive(:command_exists?) { |command| commands.include?(command) }
  end

  it 'fails, without running anything, when the target does not exist' do
    expect(Logging).to receive(:error).with(/Target does not exist/)
    expect(described_class).not_to receive(:system)

    expect(described_class.run(target: @target.join('nope'))).to be false
  end

  it 'succeeds with a warning when none of the tools is installed' do
    installed
    expect(Logging).to receive(:warn).with(/No static analysis tools available/)
    expect(described_class).not_to receive(:system)

    expect(described_class.run(target: @target)).to be true
  end

  it 'warns about the tools that are missing and runs the rest' do
    installed('rubocop')
    expect(Logging).to receive(:warn).with(/Missing tools.*reek.*flay.*flog/)
    expect(described_class).to receive(:system).with('rubocop', @target.to_s).and_return(true)

    expect(described_class.run(target: @target)).to be true
  end

  it 'runs every tool with the target, using the mass threshold for flay' do
    installed('rubocop', 'reek', 'flay', 'flog')
    expect(described_class).to receive(:system).with('rubocop', @target.to_s).and_return(true)
    expect(described_class).to receive(:system).with('reek', @target.to_s).and_return(true)
    expect(described_class).to receive(:system).with('flay', '--mass', '51', @target.to_s).and_return(true)
    expect(described_class).to receive(:system).with('flog', @target.to_s).and_return(true)

    expect(described_class.run(target: @target)).to be true
  end

  it 'still runs the remaining tools after one fails, then reports the failure' do
    installed('rubocop', 'reek')
    allow(described_class).to receive(:system).with('rubocop', anything).and_return(false)
    expect(described_class).to receive(:system).with('reek', anything).and_return(true)
    expect(Logging).to receive(:warn).with(/Failed checks.*RuboCop/)

    expect(described_class.run(target: @target)).to be false
  end

  it 'defaults the target to the scripts folder of the dotfiles repo' do
    installed
    # A stand-in repo: the real DOTFILES_DIR only exists at ~/.config/dotfiles, not where CI checks out.
    @target.join('scripts').mkpath
    stub_const('EnvVars::DOTFILES_DIR', @target)
    scripts_dir = @target.join('scripts').replace_home_path_with_tilde
    expect(Logging).to receive(:info).with(/Running static analysis on .*#{Regexp.escape(scripts_dir)}/)

    described_class.run
  end

  it 'expands a relative target' do
    installed
    Dir.chdir(@target.to_s) do
      expect(Logging).to receive(:info).with(/Running static analysis on .*#{Regexp.escape(File.basename(@target))}/)

      expect(described_class.run(target: '.')).to be true
    end
  end
end
