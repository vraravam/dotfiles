# frozen_string_literal: true

require 'hash_ext'

RSpec.describe Hash do
  describe '#deep_sort' do
    it 'sorts top-level keys' do
      expect({ b: 2, a: 1 }.deep_sort).to eq(a: 1, b: 2)
    end

    it 'recursively sorts nested hash values' do
      input = { b: { d: 1, c: 2 }, a: 3 }
      expect(input.deep_sort).to eq(a: 3, b: { c: 2, d: 1 })
    end

    it 'sorts deeply nested hashes at every level' do
      input = { z: { y: { x: 1, w: 2 } } }
      expect(input.deep_sort).to eq(z: { y: { w: 2, x: 1 } })
    end

    it 'leaves non-hash values untouched' do
      input = { b: [3, 2, 1], a: 'text' }
      expect(input.deep_sort).to eq(a: 'text', b: [3, 2, 1])
    end

    it 'returns an empty hash for an empty hash' do
      expect({}.deep_sort).to eq({})
    end

    it 'does not mutate the original hash' do
      input = { b: 2, a: 1 }
      input.deep_sort
      expect(input).to eq(b: 2, a: 1)
    end
  end
end
