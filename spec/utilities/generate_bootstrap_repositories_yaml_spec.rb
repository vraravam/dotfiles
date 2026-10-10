# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'yaml'
require 'generate_bootstrap_repositories_yaml'

RSpec.describe GenerateBootstrapRepositoriesYaml do
  around do |example|
    Dir.mktmpdir('bootstrap-yaml-spec-') do |dir|
      @tmp = Pathname.new(dir)
      example.run
    end
  end

  let(:out) { @tmp.join('bootstrap.yml') }

  before do
    Logging.state.reset!
    stub_const('EnvVars::HOME', @tmp.join('home'))
    stub_const('EnvVars::PERSONAL_CONFIGS_DIR', @tmp.join('configs'))
    stub_const('EnvVars::PERSONAL_PROFILES_DIR', @tmp.join('profiles'))
    stub_const('EnvVars::KEYBASE_HOME_REPO_NAME', nil)
    stub_const('EnvVars::KEYBASE_PROFILES_REPO_NAME', nil)
    stub_const('EnvVars::ENCRYPTED_HOME_REPO_URL', nil)
    stub_const('EnvVars::ENCRYPTED_PROFILES_REPO_URL', nil)
    allow(Keybase).to receive(:repo_url) { |name| "keybase://private/me/#{name}" }
    allow(GpgEncrypt).to receive(:url) { |url| "gpg::#{url}" }
  end

  after { Logging.state.reset! }

  def generate
    original = $stdout
    $stdout = StringIO.new
    described_class.run(output_file: out)
  ensure
    $stdout = original
  end

  it 'is false, writing nothing, when no backup mechanism is configured' do
    expect(generate).to be false
    expect(out).not_to exist
  end

  it 'uses Keybase as the primary remote and the encrypted remote as the fallback' do
    stub_const('EnvVars::KEYBASE_HOME_REPO_NAME', 'home')
    stub_const('EnvVars::ENCRYPTED_HOME_REPO_URL', 'git@host:home.git')

    expect(generate).to be true
    entry = YAML.load_file(out.to_s).first
    expect(entry).to include('folder' => @tmp.join('home').to_s, 'remote' => 'keybase://private/me/home', 'other_remotes' => { 'origin2' => 'gpg::git@host:home.git' })
    expect(entry['post_checkout']).to eq(%w[set_ssh_folder_permissions set_gnupg_folder_permissions])
    expect(entry['post_clone']).to include('git fo --rebase')
  end

  it 'uses the encrypted remote alone when Keybase is not configured' do
    stub_const('EnvVars::ENCRYPTED_PROFILES_REPO_URL', 'git@host:profiles.git')

    expect(generate).to be true
    entries = YAML.load_file(out.to_s)
    expect(entries.length).to eq(1)
    expect(entries.first).to include('folder' => @tmp.join('profiles').to_s, 'remote' => 'gpg::git@host:profiles.git')
    expect(entries.first).not_to have_key('other_remotes')
    expect(entries.first['post_clone']).to eq(['git config --local pull.allowResetOnDivergedHistory true'])
  end

  it 'omits a repo that has no mechanism while keeping the one that has' do
    stub_const('EnvVars::KEYBASE_PROFILES_REPO_NAME', 'profiles')

    generate

    expect(YAML.load_file(out.to_s).map { |e| e['folder'] }).to eq([@tmp.join('profiles').to_s])
  end
end
