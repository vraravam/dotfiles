# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'tmpdir'

require 'brew_bundle'

# The vanilla-OS install installs only the part of the Brewfile above the '# FIRST_INSTALL:'
# sentinel and the rest in the background. These specs keep that split from silently
# breaking again (an earlier cut pattern skipped comment lines and so selected the whole file).
RSpec.describe 'files/--HOME--/Brewfile FIRST_INSTALL sentinel' do
  let(:brewfile) { Pathname(File.expand_path('../files/--HOME--/Brewfile', __dir__)) }
  let(:lines) { brewfile.read(encoding: 'UTF-8').lines.map(&:chomp) }
  let(:sentinel_indexes) { lines.each_index.select { |i| lines[i].start_with?('# FIRST_INSTALL:') } }

  it 'has exactly one sentinel comment line' do
    expect(sentinel_indexes.size).to eq(1)
  end

  it 'has no other line that mentions FIRST_INSTALL' do
    others = lines.each_index.reject { |i| sentinel_indexes.include?(i) }.select { |i| lines[i].include?('FIRST_INSTALL') }

    expect(others).to be_empty
  end

  it 'cuts into a smaller, non-empty base section with the formulae and casks below it' do
    base = lines[0...sentinel_indexes.first]
    rest = lines[(sentinel_indexes.first + 1)..]

    expect(base.grep(/^\s*(brew|cask) /)).not_to be_empty
    expect(rest.grep(/^\s*(brew|cask) /)).not_to be_empty
    expect(base.size).to be < lines.size
  end

  it 'is what the install cuts: BrewBundle.base_brewfile_content returns exactly the lines above the sentinel' do
    expect(BrewBundle.base_brewfile_content(brewfile)).to eq(lines[0...sentinel_indexes.first].map { |line| "#{line}\n" }.join)
  end
end

# 'brew bundle' hands a postinstall string to /bin/sh unchanged (Ruby does not expand '${...}'), so a
# variable inside single quotes is never expanded: the antidote hook once tested for the literal file
# '${ZDOTDIR}/.aliases', which does not exist, so the && chain stopped and '|| true' hid it.
RSpec.describe 'files/--HOME--/Brewfile antidote postinstall hook' do
  let(:brewfile) { Pathname(File.expand_path('../files/--HOME--/Brewfile', __dir__)) }
  let(:command) do
    line = brewfile.read(encoding: 'UTF-8').lines.grep(/update_antidote_and_regenerate_plugin_bundle/).first
    # The same Ruby string literal Homebrew evaluates (it contains no interpolation).
    eval(line[/postinstall: (".*")/, 1]) # rubocop:disable Security/Eval
  end

  def run_hook(env: {}, aliases: "update_antidote_and_regenerate_plugin_bundle() { echo HOOK-RAN; }\n")
    Dir.mktmpdir('brewfile-hook-spec-') do |dir|
      zdotdir = Pathname(dir).join('zsh')
      zdotdir.mkpath
      zdotdir.join('.aliases').write(aliases) if aliases
      out, err, status = Open3.capture3({ 'ZDOTDIR' => zdotdir.to_s }.merge(env), '/bin/sh', '-c', command)
      [out, err, status]
    end
  end

  it 'finds the hook line in the Brewfile' do
    expect(command).to include('update_antidote_and_regenerate_plugin_bundle')
  end

  it 'calls the function when ${ZDOTDIR}/.aliases exists' do
    out, _err, status = run_hook

    expect(out).to include('HOOK-RAN')
    expect(status).to be_success
  end

  it 'does nothing, and still succeeds, when .aliases does not exist yet' do
    out, _err, status = run_hook(aliases: nil)

    expect(out).to eq('')
    expect(status).to be_success
  end

  it 'still succeeds, without breaking brew bundle, when the function fails' do
    _out, _err, status = run_hook(aliases: "update_antidote_and_regenerate_plugin_bundle() { return 3; }\n")

    expect(status).to be_success
  end
end
