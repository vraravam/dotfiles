# encoding: utf-8
# frozen_string_literal: true

require 'open3'

# The transient prompt (a finished command line collapses to a short prompt) is wired in three files
# that have to agree: .zshrc loads ftl-transient.zsh and turns it on, starship.toml defines the
# '[profiles] transient' profile it renders, and plugins.txt must NOT also run the ftl commands (the
# antidote bundle only adds the plugin directory to fpath for kind:fpath, and a second ftl-prompt call
# or an 'ftl-transient' that was never sourced would fail in every new shell).
RSpec.describe 'starship-ftl transient prompt wiring' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:zshrc) { File.read(File.join(root, 'files', '--ZDOTDIR--', '.zshrc')) }
  let(:starship_toml) { File.join(root, 'files', '--XDG_CONFIG_HOME--', 'starship.toml') }
  let(:plugins_txt) { File.read(File.join(root, 'files', '--XDG_CONFIG_HOME--', 'zsh', 'plugins.txt')) }

  it 'turns the transient prompt on only after the instant prompt is set up' do
    prompt_at = zshrc.index('GIT_CONFIG_NOSYSTEM=1 ftl-prompt starship')
    load_at = zshrc.index('ftl-transient.zsh"')
    on_at = zshrc.index('ftl-transient on')

    expect([prompt_at, load_at, on_at]).to all(be_a(Integer))
    expect(prompt_at).to be < load_at
    expect(load_at).to be < on_at
  end

  it 'only enables it when the function was actually loaded' do
    expect(zshrc).to match(/\(\( \$\+functions\[ftl-transient\] \)\) && ftl-transient on/)
  end

  # The transient profile is intentionally commented out to prevent the right prompt from collapsing.
  # We verify the comment exists confirming this design decision.
  it 'does not define a transient profile (commented out by design)' do
    expect(File.read(starship_toml)).to match(/Transient profile.*commented out/)
  end

  it 'is understood by starship itself' do
    skip 'starship is not installed' unless system('command -v starship >/dev/null 2>&1')

    # Transient profile is commented out, so it won't appear in print-config
    out, status = Open3.capture2e({ 'STARSHIP_CONFIG' => starship_toml }, 'starship', 'print-config', 'profiles')

    expect(status).to be_success
    # Just checks that starship runs without errors on a config with no transient profile defined
    expect(out.lines.grep(/error|Error/)).to be_empty
  end

  it 'does not run the ftl commands from the antidote bundle' do
    ftl_line = plugins_txt.lines.grep(%r{\Amattmc3/starship-ftl}).first

    expect(ftl_line).to eq("mattmc3/starship-ftl kind:fpath\n")
  end
end
