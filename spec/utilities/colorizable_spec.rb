# encoding: utf-8
# frozen_string_literal: true

# core must load first: core -> pathname_ext -> colorizable (see the NOTE in colorizable.rb).
require 'core'
require 'colorizable'
require 'pathname_ext'
require 'string_ext'

RSpec.describe Colorizable do
  let(:home) { '/Users/spec-user' }

  describe 'on a TTY with NO_COLOR unset' do
    around do |example|
      with_env('NO_COLOR' => nil, 'HOME' => home) { example.run }
    end

    before { allow(Core).to receive(:running_in_tty?).and_return(true) }

    {
      black: '0;30', dark_gray: '1;30', red: '0;31', light_red: '1;31',
      green: '0;32', light_green: '1;32', orange: '0;33', yellow: '1;33',
      blue: '0;34', light_blue: '1;34', purple: '0;35', light_purple: '1;35',
      cyan: '0;36', light_cyan: '1;36', light_gray: '0;37', white: '1;37'
    }.each do |color, code|
      it "wraps text for #{color} in SGR code #{code} and resets afterwards" do
        expect('text'.public_send(color)).to eq("\e[#{code}mtext\e[0m")
      end
    end

    it 'shortens the HOME path to ~ before colorizing' do
      expect("#{home}/projects".cyan).to eq("\e[0;36m~/projects\e[0m")
    end
  end

  describe 'when color must be suppressed' do
    around do |example|
      with_env('HOME' => home) { example.run }
    end

    it 'returns plain text (still tilde-shortened) when stdout is not a TTY' do
      allow(Core).to receive(:running_in_tty?).and_return(false)

      with_env('NO_COLOR' => nil) do
        expect("#{home}/x".red).to eq('~/x')
      end
    end

    it 'returns plain text when NO_COLOR is set, even on a TTY' do
      allow(Core).to receive(:running_in_tty?).and_return(true)

      with_env('NO_COLOR' => '1') do
        expect('text'.red).to eq('text')
      end
    end
  end

  describe '#replace_home_path_with_tilde' do
    it 'replaces only the first occurrence of HOME' do
      with_env('HOME' => home) do
        expect("#{home}/a#{home}".replace_home_path_with_tilde).to eq("~/a#{home}")
      end
    end

    it 'leaves strings without HOME untouched' do
      with_env('HOME' => home) do
        expect('/opt/other'.replace_home_path_with_tilde).to eq('/opt/other')
      end
    end

    it 'does nothing when HOME is empty (an empty pattern would prefix ~ to everything)' do
      with_env('HOME' => '') do
        expect('/opt/other'.replace_home_path_with_tilde).to eq('/opt/other')
      end
    end
  end

  it 'keeps colorize private so it is not part of the public API' do
    expect { 'text'.colorize('0;31') }.to raise_error(NoMethodError)
  end
end

RSpec.describe Pathname do
  it 'gains the color methods and returns a String' do
    allow(Core).to receive(:running_in_tty?).and_return(true)

    with_env('NO_COLOR' => nil, 'HOME' => '/Users/spec-user') do
      colored = Pathname('/Users/spec-user/dir').cyan

      expect(colored).to be_a(String)
      expect(colored).to eq("\e[0;36m~/dir\e[0m")
    end
  end

  it 'still converts to a plain String for system calls' do
    expect(Pathname('/tmp/x').to_s).to eq('/tmp/x')
  end
end
