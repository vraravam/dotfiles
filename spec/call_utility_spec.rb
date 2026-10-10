# frozen_string_literal: true

require 'brew_bundle'
require 'cron'
require 'dev_environment'
require_relative '../scripts/call-utility'

RSpec.describe CallUtility do
  describe '.run' do
    it 'rejects a module that is not on the allow-list' do
      expect { described_class.run(target: 'Kernel.exit') }.to raise_error(ArgumentError, /Unknown utility module 'Kernel'/)
    end

    it 'rejects a target that is not <Module>.<method>' do
      expect { described_class.run(target: 'Cron') }.to raise_error(ArgumentError, /Expected <Module>.<method>/)
    end

    it 'rejects a method the module does not expose' do
      expect { described_class.run(target: 'Cron.no_such_method') }.to raise_error(ArgumentError, /no public method/)
    end

    it 'passes keyword arguments through, coercing booleans' do
      expect(DevEnvironment).to receive(:setup_dev_environment).with(first_install: true)

      expect(described_class.run(target: 'DevEnvironment.setup_dev_environment', args: ['--first_install=true'])).to be true
    end

    it 'lets the shell install the Brewfile and see a failure through --truthy' do
      expect(BrewBundle).to receive(:run).with(first_install: true).and_return(false)

      expect(described_class.run(target: 'BrewBundle.run', args: ['--first_install=true'], truthy: true)).to be false
    end

    it 'does not pass an empty keyword hash to methods that take none' do
      expect(Cron).to receive(:restore_cron).with('/tmp/f').and_return(true)

      described_class.run(target: 'Cron.restore_cron', args: ['/tmp/f'])
    end

    it 'treats everything after -- as positional, even if it looks like a keyword' do
      expect(Cron).to receive(:restore_cron).with('--looks=like-a-keyword').and_return(true)

      described_class.run(target: 'Cron.restore_cron', args: ['--', '--looks=like-a-keyword'])
    end

    it 'returns true regardless of the method result by default' do
      allow(Cron).to receive(:restore_cron).and_return(nil)

      expect(described_class.run(target: 'Cron.restore_cron', args: ['/x'])).to be true
    end

    it 'with truthy: true, reports a nil/false result as failure' do
      allow(Cron).to receive(:restore_cron).and_return(nil)

      expect(described_class.run(target: 'Cron.restore_cron', args: ['/x'], truthy: true)).to be false
    end

    it 'with truthy: true, reports a truthy result as success' do
      allow(Cron).to receive(:restore_cron).and_return('user')

      expect(described_class.run(target: 'Cron.restore_cron', args: ['/x'], truthy: true)).to be true
    end
  end

  describe '._split_args' do
    it 'coerces true/false keyword values to booleans and leaves other values as strings' do
      positional, keywords = described_class.send(:_split_args, ['p', '--a=true', '--b=false', '--c=text', '--d=a=b'])

      expect(positional).to eq(['p'])
      expect(keywords).to eq(a: true, b: false, c: 'text', d: 'a=b')
    end
  end
end
