# frozen_string_literal: true

require 'step_counter'

RSpec.describe StepCounter do
  subject(:counter) { described_class.new(3) }

  describe '#next_prefix' do
    it 'numbers the steps in order, with a purple "Step N of TOTAL" label' do
      expect(counter.next_prefix).to eq("[#{'Step 1 of 3'.purple}] ")
      expect(counter.next_prefix).to eq("[#{'Step 2 of 3'.purple}] ")
    end
  end

  describe '#step' do
    it 'prefixes the title with the progress label, passes the header through and returns the block value' do
      expect(Logging).to receive(:with_step).with("#{"[#{'Step 1 of 3'.purple}] "}Install thing", 'Installing').and_yield.and_return(:done)

      expect(counter.step('Install thing', 'Installing') { :ignored }).to eq(:done)
    end

    it 'advances the shared counter' do
      allow(Logging).to receive(:with_step)

      counter.step('one')
      counter.step('two')

      expect(counter.next_prefix).to eq("[#{'Step 3 of 3'.purple}] ")
    end
  end
end
