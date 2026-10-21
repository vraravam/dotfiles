# encoding: utf-8
# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'bootstrap_repos'

RSpec.describe BootstrapRepos do
  around do |example|
    Dir.mktmpdir('bootstrap-repos-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  let(:config) { @tmp.join('.bootstrap-repositories.yml') }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOME', @tmp)
    allow(Keybase).to receive(:bootstrap_login).and_return(true)
    allow(GenerateBootstrapRepositoriesYaml).to receive(:run).and_return(true)
    allow(ResurrectRepositories).to receive(:run).and_return(true)
    allow(DevEnvironment).to receive(:setup_dev_environment)
  end

  after { Logging.state.reset! }

  def run_quietly(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    described_class.run(**kwargs)
  ensure
    $stdout = original
  end

  it 'generates the config in HOME, resurrects from it, then sets up the dev environment' do
    expect(GenerateBootstrapRepositoriesYaml).to receive(:run).with(output_file: config).ordered.and_return(true)
    expect(ResurrectRepositories).to receive(:run).with(resurrect: config).ordered.and_return(true)
    expect(DevEnvironment).to receive(:setup_dev_environment).with(maxdepth: DevEnvironment::SHALLOW_MAXDEPTH).ordered

    expect(run_quietly).to be true
  end

  it 'makes sure Keybase is logged in before cloning' do
    expect(Keybase).to receive(:bootstrap_login).ordered
    expect(GenerateBootstrapRepositoriesYaml).to receive(:run).ordered.and_return(true)

    run_quietly
  end

  it 'carries on cloning when the Keybase login fails' do
    allow(Keybase).to receive(:bootstrap_login).and_return(false)
    expect(ResurrectRepositories).to receive(:run).and_return(true)

    expect(run_quietly).to be true
  end

  it 'skips the resurrection, records an error and returns false when the config cannot be generated' do
    allow(GenerateBootstrapRepositoriesYaml).to receive(:run).and_return(false)
    expect(ResurrectRepositories).not_to receive(:run)

    expect(run_quietly).to be false
    expect(Logging.issue_summary_parts).not_to be_empty
  end

  it 'still runs the dev-environment safety net when the config cannot be generated' do
    allow(GenerateBootstrapRepositoriesYaml).to receive(:run).and_return(false)
    expect(DevEnvironment).to receive(:setup_dev_environment)

    run_quietly
  end

  it 'returns false, with a warning, when some repo could not be resurrected' do
    allow(ResurrectRepositories).to receive(:run).and_return(false)

    expect(run_quietly).to be false
    expect(Logging.issue_summary_parts).not_to be_empty
  end
end
