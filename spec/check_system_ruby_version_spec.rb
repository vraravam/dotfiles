# frozen_string_literal: true

require 'tmpdir'
require_relative '../.github/scripts/check-system-ruby-version'

RSpec.describe CheckSystemRubyVersion do
  let(:gemfile) { File.join(Dir.mktmpdir, 'Gemfile') }

  def write_gemfile(content)
    File.write(gemfile, content)
  end

  before do
    allow(described_class).to receive(:`).with("#{described_class::SYSTEM_RUBY} -e 'print RUBY_VERSION'").and_return('2.6.10')
    allow(described_class).to receive(:`).with("#{described_class::SYSTEM_RUBY} -v").and_return("ruby 2.6.10p210\n")
  end

  it 'succeeds quietly when the pin matches the system Ruby' do
    write_gemfile("source 'x'\nruby '2.6.10'\n")
    expect(described_class).not_to receive(:open_issue)

    expect { expect(described_class.run(gemfile: gemfile)).to be true }.to output(/In sync/).to_stdout
  end

  it 'fails when the Gemfile has no ruby pin' do
    write_gemfile("source 'x'\n")

    expect { expect(described_class.run(gemfile: gemfile)).to be false }.to output(/could not find a 'ruby' version pin/).to_stderr
  end

  it 'opens an issue when the pin and the system Ruby have drifted apart' do
    write_gemfile("ruby '2.5.0'\n")
    title = 'System Ruby version drift: Gemfile pins 2.5.0, runner has 2.6.10'
    expect(described_class).to receive(:open_issue).with(title, '2.5.0', 'ruby 2.6.10p210').and_return(true)

    expect { described_class.run(gemfile: gemfile) }.to output.to_stdout
  end

  describe '.issue_body' do
    it 'names both versions' do
      body = described_class.send(:issue_body, '2.5.0', 'ruby 2.6.10p210')

      expect(body).to include("ruby '2.5.0'", 'ruby 2.6.10p210')
    end
  end

  describe '.open_issue' do
    it 'does not file a duplicate when an open issue already reports this drift' do
      allow(Open3).to receive(:capture2).and_return(["7\n", nil])
      expect(described_class).not_to receive(:system)

      expect { expect(described_class.send(:open_issue, 'title', '2.5.0', 'ruby 2.6.10')).to be true }.to output(/Issue #7 already open/).to_stdout
    end
  end
end
