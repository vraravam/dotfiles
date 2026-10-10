# frozen_string_literal: true

require 'pathname'

require 'brew'

# The vanilla-OS install installs only the part of the Brewfile above the '# FIRST_INSTALL:'
# sentinel and the rest in the background. These specs keep that split from silently
# breaking again (an earlier cut pattern skipped comment lines and so selected the whole file).
RSpec.describe 'files/--HOME--/Brewfile FIRST_INSTALL sentinel' do
  let(:brewfile) { Pathname.new(File.expand_path('../files/--HOME--/Brewfile', __dir__)) }
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

  it 'is what the install cuts: Brew.base_brewfile_content returns exactly the lines above the sentinel' do
    expect(Brew.base_brewfile_content(brewfile)).to eq(lines[0...sentinel_indexes.first].map { |line| "#{line}\n" }.join)
  end
end
