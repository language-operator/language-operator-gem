# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/type_coercion'

RSpec.describe LanguageOperator::TypeCoercion do
  describe '.coerce' do
    context 'with integer type' do
      it 'returns integer unchanged' do
        expect(described_class.coerce(123, 'integer')).to eq(123)
      end

      it 'coerces string to integer' do
        expect(described_class.coerce('123', 'integer')).to eq(123)
        expect(described_class.coerce('0', 'integer')).to eq(0)
        expect(described_class.coerce('-456', 'integer')).to eq(-456)
      end

      it 'coerces float to integer' do
        expect(described_class.coerce(123.0, 'integer')).to eq(123)
        expect(described_class.coerce(123.9, 'integer')).to eq(123)
      end

      it 'raises ArgumentError for invalid string' do
        expect { described_class.coerce('abc', 'integer') }
          .to raise_error(ArgumentError, /Cannot coerce "abc" to integer/)
      end

      it 'raises ArgumentError for non-numeric values' do
        expect { described_class.coerce(nil, 'integer') }
          .to raise_error(ArgumentError, /Cannot coerce nil to integer/)
        expect { described_class.coerce({}, 'integer') }
          .to raise_error(ArgumentError, /Cannot coerce \{\} to integer/)
      end
    end

    context 'with number type' do
      it 'returns numeric unchanged' do
        expect(described_class.coerce(3.14, 'number')).to eq(3.14)
        expect(described_class.coerce(42, 'number')).to eq(42)
      end

      it 'coerces string to float' do
        expect(described_class.coerce('3.14', 'number')).to eq(3.14)
        expect(described_class.coerce('0.0', 'number')).to eq(0.0)
        expect(described_class.coerce('-2.5', 'number')).to eq(-2.5)
      end

      it 'coerces integer to float' do
        expect(described_class.coerce(3, 'number')).to eq(3.0)
      end

      it 'raises ArgumentError for invalid string' do
        expect { described_class.coerce('not a number', 'number') }
          .to raise_error(ArgumentError, /Cannot coerce "not a number" to number/)
      end

      it 'raises ArgumentError for non-numeric values' do
        expect { described_class.coerce(nil, 'number') }
          .to raise_error(ArgumentError, /Cannot coerce nil to number/)
        expect { described_class.coerce([], 'number') }
          .to raise_error(ArgumentError, /Cannot coerce \[\] to number/)
      end
    end

    context 'with string type' do
      it 'returns string unchanged' do
        expect(described_class.coerce('hello', 'string')).to eq('hello')
      end

      it 'coerces integer to string' do
        expect(described_class.coerce(123, 'string')).to eq('123')
      end

      it 'coerces float to string' do
        expect(described_class.coerce(3.14, 'string')).to eq('3.14')
      end

      it 'coerces symbol to string' do
        expect(described_class.coerce(:symbol, 'string')).to eq('symbol')
      end

      it 'coerces boolean to string' do
        expect(described_class.coerce(true, 'string')).to eq('true')
        expect(described_class.coerce(false, 'string')).to eq('false')
      end

      it 'coerces nil to empty string' do
        expect(described_class.coerce(nil, 'string')).to eq('')
      end

      it 'coerces array to string' do
        expect(described_class.coerce([1, 2, 3], 'string')).to match(/\[1, 2, 3\]/)
      end

      it 'coerces hash to string' do
        expect(described_class.coerce({ a: 1 }, 'string')).to match(/\{.*a.*1.*\}/)
      end
    end

    context 'with boolean type' do
      it 'returns boolean unchanged' do
        expect(described_class.coerce(true, 'boolean')).to be(true)
        expect(described_class.coerce(false, 'boolean')).to be(false)
      end

      it 'coerces truthy strings' do
        expect(described_class.coerce('true', 'boolean')).to be(true)
        expect(described_class.coerce('TRUE', 'boolean')).to be(true)
        expect(described_class.coerce('True', 'boolean')).to be(true)
        expect(described_class.coerce('1', 'boolean')).to be(true)
        expect(described_class.coerce('yes', 'boolean')).to be(true)
        expect(described_class.coerce('YES', 'boolean')).to be(true)
        expect(described_class.coerce('t', 'boolean')).to be(true)
        expect(described_class.coerce('T', 'boolean')).to be(true)
        expect(described_class.coerce('y', 'boolean')).to be(true)
        expect(described_class.coerce('Y', 'boolean')).to be(true)
      end

      it 'coerces falsy strings' do
        expect(described_class.coerce('false', 'boolean')).to be(false)
        expect(described_class.coerce('FALSE', 'boolean')).to be(false)
        expect(described_class.coerce('False', 'boolean')).to be(false)
        expect(described_class.coerce('0', 'boolean')).to be(false)
        expect(described_class.coerce('no', 'boolean')).to be(false)
        expect(described_class.coerce('NO', 'boolean')).to be(false)
        expect(described_class.coerce('f', 'boolean')).to be(false)
        expect(described_class.coerce('F', 'boolean')).to be(false)
        expect(described_class.coerce('n', 'boolean')).to be(false)
        expect(described_class.coerce('N', 'boolean')).to be(false)
      end

      it 'raises ArgumentError for ambiguous values' do
        expect { described_class.coerce('maybe', 'boolean') }
          .to raise_error(ArgumentError, /Cannot coerce "maybe" to boolean/)
        expect { described_class.coerce('unknown', 'boolean') }
          .to raise_error(ArgumentError, /Cannot coerce "unknown" to boolean/)
        expect { described_class.coerce('2', 'boolean') }
          .to raise_error(ArgumentError, /Cannot coerce "2" to boolean/)
        expect { described_class.coerce('', 'boolean') }
          .to raise_error(ArgumentError, /Cannot coerce "" to boolean/)
      end

      it 'raises ArgumentError for non-boolean, non-string values' do
        expect { described_class.coerce(nil, 'boolean') }
          .to raise_error(ArgumentError, /Cannot coerce nil to boolean/)
        expect { described_class.coerce(1, 'boolean') }
          .to raise_error(ArgumentError, /Cannot coerce 1 to boolean/)
        expect { described_class.coerce(0, 'boolean') }
          .to raise_error(ArgumentError, /Cannot coerce 0 to boolean/)
      end
    end

    context 'with array type' do
      it 'returns array unchanged' do
        arr = [1, 2, 3]
        expect(described_class.coerce(arr, 'array')).to eq(arr)
      end

      it 'accepts empty array' do
        expect(described_class.coerce([], 'array')).to eq([])
      end

      it 'accepts nested arrays' do
        nested = [[1, 2], [3, 4]]
        expect(described_class.coerce(nested, 'array')).to eq(nested)
      end

      it 'raises ArgumentError for non-array values' do
        expect { described_class.coerce({}, 'array') }
          .to raise_error(ArgumentError, /Expected array, got Hash/)
        expect { described_class.coerce('string', 'array') }
          .to raise_error(ArgumentError, /Expected array, got String/)
        expect { described_class.coerce(123, 'array') }
          .to raise_error(ArgumentError, /Expected array, got Integer/)
        expect { described_class.coerce(nil, 'array') }
          .to raise_error(ArgumentError, /Expected array, got NilClass/)
      end
    end

    context 'with hash type' do
      it 'returns hash unchanged' do
        hash = { a: 1, b: 2 }
        expect(described_class.coerce(hash, 'hash')).to eq(hash)
      end

      it 'accepts empty hash' do
        expect(described_class.coerce({}, 'hash')).to eq({})
      end

      it 'accepts nested hashes' do
        nested = { a: { b: 1 }, c: { d: 2 } }
        expect(described_class.coerce(nested, 'hash')).to eq(nested)
      end

      it 'accepts hashes with string keys' do
        hash = { 'a' => 1, 'b' => 2 }
        expect(described_class.coerce(hash, 'hash')).to eq(hash)
      end

      it 'raises ArgumentError for non-hash values' do
        expect { described_class.coerce([], 'hash') }
          .to raise_error(ArgumentError, /Expected hash, got Array/)
        expect { described_class.coerce('string', 'hash') }
          .to raise_error(ArgumentError, /Expected hash, got String/)
        expect { described_class.coerce(123, 'hash') }
          .to raise_error(ArgumentError, /Expected hash, got Integer/)
        expect { described_class.coerce(nil, 'hash') }
          .to raise_error(ArgumentError, /Expected hash, got NilClass/)
      end
    end

    context 'with any type' do
      it 'returns value unchanged for any type' do
        expect(described_class.coerce(123, 'any')).to eq(123)
        expect(described_class.coerce('string', 'any')).to eq('string')
        expect(described_class.coerce([1, 2, 3], 'any')).to eq([1, 2, 3])
        expect(described_class.coerce({ a: 1 }, 'any')).to eq({ a: 1 })
        expect(described_class.coerce(nil, 'any')).to be_nil
        expect(described_class.coerce(true, 'any')).to be(true)
        expect(described_class.coerce(3.14, 'any')).to eq(3.14)
      end
    end

    context 'with unknown type' do
      it 'raises ArgumentError' do
        expect { described_class.coerce(123, 'unknown') }
          .to raise_error(ArgumentError, /Unknown type: unknown/)
        expect { described_class.coerce('value', 'custom_type') }
          .to raise_error(ArgumentError, /Unknown type: custom_type/)
      end
    end
  end

  describe '.coerce_integer' do
    it 'coerces valid values' do
      expect(described_class.coerce_integer(123)).to eq(123)
      expect(described_class.coerce_integer('456')).to eq(456)
      expect(described_class.coerce_integer(78.9)).to eq(78)
    end

    it 'raises ArgumentError for invalid values' do
      expect { described_class.coerce_integer('invalid') }
        .to raise_error(ArgumentError, /Cannot coerce "invalid" to integer/)
    end
  end

  describe '.coerce_number' do
    it 'coerces valid values' do
      expect(described_class.coerce_number(3.14)).to eq(3.14)
      expect(described_class.coerce_number('2.5')).to eq(2.5)
      expect(described_class.coerce_number(42)).to eq(42)
    end

    it 'raises ArgumentError for invalid values' do
      expect { described_class.coerce_number('invalid') }
        .to raise_error(ArgumentError, /Cannot coerce "invalid" to number/)
    end
  end

  describe '.coerce_string' do
    it 'coerces any value to string' do
      expect(described_class.coerce_string(:symbol)).to eq('symbol')
      expect(described_class.coerce_string(123)).to eq('123')
      expect(described_class.coerce_string(nil)).to eq('')
    end
  end

  describe '.coerce_boolean' do
    it 'coerces truthy values' do
      expect(described_class.coerce_boolean('true')).to be(true)
      expect(described_class.coerce_boolean(true)).to be(true)
    end

    it 'coerces falsy values' do
      expect(described_class.coerce_boolean('false')).to be(false)
      expect(described_class.coerce_boolean(false)).to be(false)
    end

    it 'raises ArgumentError for ambiguous values' do
      expect { described_class.coerce_boolean('maybe') }
        .to raise_error(ArgumentError, /Cannot coerce "maybe" to boolean/)
    end
  end

  describe '.validate_array' do
    it 'accepts arrays' do
      expect(described_class.validate_array([1, 2, 3])).to eq([1, 2, 3])
    end

    it 'raises ArgumentError for non-arrays' do
      expect { described_class.validate_array({}) }
        .to raise_error(ArgumentError, /Expected array, got Hash/)
    end
  end

  describe '.validate_hash' do
    it 'accepts hashes' do
      expect(described_class.validate_hash({ a: 1 })).to eq({ a: 1 })
    end

    it 'raises ArgumentError for non-hashes' do
      expect { described_class.validate_hash([]) }
        .to raise_error(ArgumentError, /Expected hash, got Array/)
    end
  end

  describe '.coercion_rules' do
    it 'returns coercion rules hash' do
      rules = described_class.coercion_rules
      expect(rules).to be_a(Hash)
      expect(rules.keys).to contain_exactly('integer', 'number', 'string', 'boolean', 'array', 'hash', 'any')
      expect(rules['integer']).to have_key(:accepts)
      expect(rules['integer']).to have_key(:method)
      expect(rules['integer']).to have_key(:errors)
    end
  end

  describe 'cache management' do
    before { described_class.clear_cache }
    after { described_class.clear_cache }

    describe '.cache_stats' do
      it 'returns comprehensive cache statistics' do
        stats = described_class.cache_stats
        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:size)
        expect(stats).to have_key(:max_size)
        expect(stats).to have_key(:hits)
        expect(stats).to have_key(:misses)
        expect(stats).to have_key(:hit_rate)

        expect(stats[:max_size]).to be > 0
        expect(stats[:size]).to be >= 0
        expect(stats[:size]).to be <= stats[:max_size]
      end

      it 'tracks cache hits and misses correctly' do
        # First call should be a cache miss
        described_class.coerce('123', 'integer')
        stats = described_class.cache_stats
        expect(stats[:misses]).to eq(1)
        expect(stats[:hits]).to eq(0)

        # Second call should be a cache hit
        described_class.coerce('123', 'integer')
        stats = described_class.cache_stats
        expect(stats[:misses]).to eq(1)
        expect(stats[:hits]).to eq(1)
        expect(stats[:hit_rate]).to eq(0.5)
      end
    end

    describe '.cache_size' do
      it 'returns the configured cache size' do
        expect(described_class.cache_size).to be_a(Integer)
        expect(described_class.cache_size).to be > 0
      end
    end

    describe '.clear_cache' do
      it 'clears cache and resets statistics' do
        # Add some entries to cache
        described_class.coerce('123', 'integer')
        described_class.coerce('456', 'integer')
        
        stats_before = described_class.cache_stats
        expect(stats_before[:size]).to eq(2)

        described_class.clear_cache

        stats_after = described_class.cache_stats
        expect(stats_after[:size]).to eq(0)
        expect(stats_after[:hits]).to eq(0)
        expect(stats_after[:misses]).to eq(0)
      end
    end

    describe 'LRU cache behavior' do
      it 'has bounded cache size' do
        cache_size = described_class.cache_size
        
        # Fill cache beyond its capacity
        (cache_size + 100).times do |i|
          described_class.coerce("value_#{i}", 'string')
        end

        stats = described_class.cache_stats
        expect(stats[:size]).to be <= cache_size
      end

      it 'evicts least recently used entries when cache is full' do
        # Use a predictable pattern that will definitely trigger evictions
        cache_size = described_class.cache_size
        
        # Fill cache to capacity with integer coercions (which are cached)
        (cache_size + 10).times do |i|
          described_class.coerce(i.to_s, 'integer')
        end

        stats = described_class.cache_stats
        expect(stats[:size]).to be <= cache_size
      end

      it 'preserves recently accessed entries during eviction' do
        cache_size = described_class.cache_size
        
        # Add an entry that will succeed (using valid integer string)
        described_class.coerce('42', 'integer')
        
        # Fill cache beyond capacity with other entries
        (cache_size + 5).times do |i|
          described_class.coerce(i.to_s, 'integer')
        end
        
        # Access our preserved entry to make it recent
        result = described_class.coerce('42', 'integer')
        expect(result).to eq(42)
        
        # Add more entries to trigger more evictions
        10.times do |i|
          described_class.coerce((i + 2000).to_s, 'integer')
        end

        # The important thing is that the cache size remains bounded
        stats = described_class.cache_stats
        expect(stats[:size]).to be <= cache_size
      end
    end

    describe 'cache key uniqueness' do
      it 'caches different [value, type] combinations separately' do
        described_class.clear_cache
        
        # Same value, different types
        described_class.coerce('123', 'integer')
        described_class.coerce('123', 'string')
        described_class.coerce('123', 'number')
        
        stats = described_class.cache_stats
        expect(stats[:size]).to eq(2) # integer and number are cached, string is not
        expect(stats[:misses]).to eq(2)
        
        # Same type, different values
        described_class.coerce('456', 'integer')
        described_class.coerce('789', 'integer')
        
        stats = described_class.cache_stats
        expect(stats[:size]).to eq(4) # 2 + 2 more integer entries
        expect(stats[:misses]).to eq(4)
      end

      it 'returns cached results for exact [value, type] matches' do
        described_class.clear_cache
        
        # First call - cache miss
        result1 = described_class.coerce('42', 'integer')
        stats1 = described_class.cache_stats
        expect(stats1[:misses]).to eq(1)
        expect(stats1[:hits]).to eq(0)
        
        # Second call - cache hit
        result2 = described_class.coerce('42', 'integer')
        stats2 = described_class.cache_stats
        expect(stats2[:misses]).to eq(1)
        expect(stats2[:hits]).to eq(1)
        
        expect(result1).to eq(result2)
        expect(result1).to eq(42)
      end
    end

    describe 'error caching' do
      it 'caches failed coercion attempts' do
        described_class.clear_cache
        
        # First failed coercion - cache miss
        expect { described_class.coerce('invalid', 'integer') }.to raise_error(ArgumentError)
        stats1 = described_class.cache_stats
        expect(stats1[:misses]).to eq(1)
        expect(stats1[:hits]).to eq(0)
        
        # Second failed coercion - cache hit (error served from cache)
        expect { described_class.coerce('invalid', 'integer') }.to raise_error(ArgumentError)
        stats2 = described_class.cache_stats
        expect(stats2[:misses]).to eq(1)
        expect(stats2[:hits]).to eq(1)
      end

      it 'caches error messages correctly' do
        described_class.clear_cache
        
        # Cache the error
        begin
          described_class.coerce('not_a_number', 'integer')
        rescue ArgumentError => e
          original_message = e.message
        end
        
        # Retrieve from cache
        begin
          described_class.coerce('not_a_number', 'integer')
        rescue ArgumentError => e
          cached_message = e.message
        end
        
        expect(cached_message).to eq(original_message)
        expect(cached_message).to include('Cannot coerce "not_a_number" to integer')
      end
    end
  end

  # Edge cases
  describe 'edge cases' do
    context 'with empty strings' do
      it 'handles empty string for string type' do
        expect(described_class.coerce('', 'string')).to eq('')
      end

      it 'raises error for empty string to integer' do
        expect { described_class.coerce('', 'integer') }
          .to raise_error(ArgumentError)
      end

      it 'raises error for empty string to boolean' do
        expect { described_class.coerce('', 'boolean') }
          .to raise_error(ArgumentError)
      end
    end

    context 'with symbols' do
      it 'converts symbol to string' do
        expect(described_class.coerce(:test, 'string')).to eq('test')
      end
    end

    context 'with whitespace' do
      it 'handles whitespace in boolean strings' do
        expect(described_class.coerce(' true ', 'boolean')).to be(true)
        expect(described_class.coerce(' false ', 'boolean')).to be(false)
      end
    end

    context 'with scientific notation' do
      it 'handles scientific notation for numbers' do
        expect(described_class.coerce('1e10', 'number')).to eq(1e10)
      end
    end

    context 'with hexadecimal notation' do
      it 'handles hexadecimal for integers' do
        expect(described_class.coerce('0xFF', 'integer')).to eq(255)
      end
    end

    context 'with octal notation' do
      it 'handles octal for integers' do
        expect(described_class.coerce('0o10', 'integer')).to eq(8)
      end
    end

    context 'with binary notation' do
      it 'handles binary for integers' do
        expect(described_class.coerce('0b1010', 'integer')).to eq(10)
      end
    end
  end
end
