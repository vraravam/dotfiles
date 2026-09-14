# frozen_string_literal: true

require 'enumerable_ext'

RSpec.describe Enumerable do
  # This polyfill is only defined when the native Ruby 2.7+ method is absent
  # (see enumerable_ext.rb) -- on Ruby >= 2.7 (including the version running
  # this spec suite in CI) these specs exercise the native implementation
  # instead. Either way, the observable behavior must match, so the specs
  # assert on behavior only, not on which implementation ran.
  describe '#filter_map' do
    it 'maps then filters out nil results in a single pass' do
      result = [1, 2, 3, 4].filter_map { |n| n * 2 if n.even? }
      expect(result).to eq([4, 8])
    end

    it 'returns an empty array when every result is nil' do
      expect([1, 2, 3].filter_map { |_n| nil }).to eq([])
    end

    it 'keeps falsy-but-not-nil results (only nil is filtered)' do
      expect([true, false, nil].filter_map { |v| v }).to eq([true, false])
    end

    it 'returns an Enumerator when called without a block' do
      expect([1, 2, 3].filter_map).to be_a(Enumerator)
    end
  end
end
