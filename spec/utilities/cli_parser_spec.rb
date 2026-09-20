# frozen_string_literal: true

require 'cli_parser'

RSpec.describe CliParser do
  # OptionParser#parse! (called internally by CliParser.parse) always parses
  # the real ARGV constant -- save/restore it so these specs don't leak into
  # (or get polluted by) the actual process arguments rspec itself was run with.
  around do |example|
    original_argv = ARGV.dup
    example.run
  ensure
    ARGV.replace(original_argv)
  end

  describe '.parse' do
    it 'returns a Parser with the banner set from the given text' do
      ARGV.replace([])

      parser = described_class.parse('<dir> <output-file>')

      expect(parser.banner).to include('<dir> <output-file>')
    end

    it 'yields the parser to the block so options can be defined' do
      ARGV.replace(['--verbose'])
      verbose = false

      described_class.parse('<dir>') do |opts|
        opts.on('--verbose') { verbose = true }
      end

      expect(verbose).to be true
    end

    it 'exits with status 0 on -h/--help without requiring the block-defined options' do
      ARGV.replace(['-h'])

      expect { described_class.parse('<dir>') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    end

    it 'exits with status 1 and does not raise OptionParser::InvalidOption to the caller' do
      ARGV.replace(['--not-a-real-option'])
      allow(Logging).to receive(:warn)

      expect { described_class.parse('<dir>') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    it 'exits with status 1 when a required option argument is missing' do
      ARGV.replace(['--value'])
      allow(Logging).to receive(:warn)

      expect do
        described_class.parse('<dir>') do |opts|
          opts.on('--value VALUE') { |v| v }
        end
      end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end
  end

  describe CliParser::Parser do
    subject(:parser) { described_class.new }

    describe '#warn' do
      it 'delegates to Logging.warn instead of OptionParser default program-name-prefixed output' do
        expect(Logging).to receive(:warn).with('custom warning')

        parser.warn('custom warning')
      end
    end

    describe '#abort_with_usage' do
      it 'warns with the given message, prints usage, and exits with status 1' do
        allow(Logging).to receive(:warn)

        expect { parser.abort_with_usage('bad input') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        expect(Logging).to have_received(:warn).with('bad input')
      end
    end
  end
end
