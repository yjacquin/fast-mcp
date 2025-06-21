# frozen_string_literal: true

RSpec.describe FastMcp::Metadata do
  let(:test_class) do
    Class.new do
      include FastMcp::Metadata
    end
  end
  let(:instance) { test_class.new }

  describe 'RESERVED_PREFIXES' do
    it 'defines the correct reserved prefixes' do
      expect(described_class::RESERVED_PREFIXES).to eq(['mcp:', 'mcp-'])
    end
  end

  describe '#validate_meta_field' do
    context 'with valid metadata' do
      it 'accepts nil metadata' do
        expect { instance.validate_meta_field(nil) }.not_to raise_error
      end

      it 'accepts empty hash' do
        expect { instance.validate_meta_field({}) }.not_to raise_error
      end

      it 'accepts valid keys' do
        metadata = { 'custom_key' => 'value', 'another-key' => 'value2' }
        expect { instance.validate_meta_field(metadata) }.not_to raise_error
      end

      it 'accepts symbol keys' do
        metadata = { custom_key: 'value', another_key: 'value2' }
        expect { instance.validate_meta_field(metadata) }.not_to raise_error
      end
    end

    context 'with invalid metadata' do
      it 'raises error for non-hash metadata' do
        expect { instance.validate_meta_field('string') }.to raise_error(
          FastMcp::Metadata::InvalidMetadataError, 
          'Metadata must be a Hash, got String'
        )
      end

      it 'raises error for array metadata' do
        expect { instance.validate_meta_field([1, 2, 3]) }.to raise_error(
          FastMcp::Metadata::InvalidMetadataError,
          'Metadata must be a Hash, got Array'
        )
      end

      it 'raises error for empty key' do
        metadata = { '' => 'value' }
        expect { instance.validate_meta_field(metadata) }.to raise_error(
          FastMcp::Metadata::InvalidMetadataError,
          'Metadata keys cannot be empty'
        )
      end
    end

    context 'with reserved prefixes' do
      it 'raises error for mcp: prefix' do
        metadata = { 'mcp:reserved' => 'value' }
        expect { instance.validate_meta_field(metadata) }.to raise_error(
          FastMcp::Metadata::ReservedMetadataError,
          "Key 'mcp:reserved' uses reserved prefix"
        )
      end

      it 'raises error for mcp- prefix' do
        metadata = { 'mcp-reserved' => 'value' }
        expect { instance.validate_meta_field(metadata) }.to raise_error(
          FastMcp::Metadata::ReservedMetadataError,
          "Key 'mcp-reserved' uses reserved prefix"
        )
      end

      it 'raises error for symbol keys with reserved prefixes' do
        metadata = { 'mcp:symbol': 'value' }
        expect { instance.validate_meta_field(metadata) }.to raise_error(
          FastMcp::Metadata::ReservedMetadataError,
          "Key 'mcp:symbol' uses reserved prefix"
        )
      end
    end
  end

  describe '#sanitize_meta_field' do
    it 'returns empty hash for nil' do
      expect(instance.sanitize_meta_field(nil)).to eq({})
    end

    it 'returns empty hash for non-hash input' do
      expect(instance.sanitize_meta_field('string')).to eq({})
      expect(instance.sanitize_meta_field([1, 2, 3])).to eq({})
    end

    it 'removes reserved prefix keys' do
      metadata = {
        'valid_key' => 'value1',
        'mcp:reserved' => 'value2',
        'mcp-reserved' => 'value3',
        'another_valid' => 'value4'
      }
      
      result = instance.sanitize_meta_field(metadata)
      expect(result).to eq({
        'valid_key' => 'value1',
        'another_valid' => 'value4'
      })
    end

    it 'removes empty keys' do
      metadata = {
        'valid_key' => 'value1',
        '' => 'empty_key_value',
        'another_valid' => 'value2'
      }
      
      result = instance.sanitize_meta_field(metadata)
      expect(result).to eq({
        'valid_key' => 'value1',
        'another_valid' => 'value2'
      })
    end

    it 'preserves valid metadata' do
      metadata = {
        'app_version' => '1.0.0',
        'user_id' => '12345',
        'custom-data' => { 'nested' => 'value' }
      }
      
      result = instance.sanitize_meta_field(metadata)
      expect(result).to eq(metadata)
    end
  end

  describe '#merge_meta_fields' do
    it 'merges multiple metadata sources' do
      meta1 = { 'key1' => 'value1', 'common' => 'meta1' }
      meta2 = { 'key2' => 'value2', 'common' => 'meta2' }
      meta3 = { 'key3' => 'value3' }

      result = instance.merge_meta_fields(meta1, meta2, meta3)
      expect(result).to eq({
        'key1' => 'value1',
        'key2' => 'value2',
        'key3' => 'value3',
        'common' => 'meta2'  # Later sources take precedence
      })
    end

    it 'ignores nil sources' do
      meta1 = { 'key1' => 'value1' }
      meta2 = nil
      meta3 = { 'key3' => 'value3' }

      result = instance.merge_meta_fields(meta1, meta2, meta3)
      expect(result).to eq({
        'key1' => 'value1',
        'key3' => 'value3'
      })
    end

    it 'sanitizes reserved keys during merge' do
      meta1 = { 'valid1' => 'value1', 'mcp:reserved' => 'bad1' }
      meta2 = { 'valid2' => 'value2', 'mcp-reserved' => 'bad2' }

      result = instance.merge_meta_fields(meta1, meta2)
      expect(result).to eq({
        'valid1' => 'value1',
        'valid2' => 'value2'
      })
    end

    it 'handles empty input' do
      expect(instance.merge_meta_fields).to eq({})
    end
  end

  describe '#reserved_key?' do
    it 'returns true for mcp: prefix' do
      expect(instance.reserved_key?('mcp:something')).to be(true)
    end

    it 'returns true for mcp- prefix' do
      expect(instance.reserved_key?('mcp-something')).to be(true)
    end

    it 'returns false for valid keys' do
      expect(instance.reserved_key?('valid_key')).to be(false)
      expect(instance.reserved_key?('app-data')).to be(false)
      expect(instance.reserved_key?('custom:namespace')).to be(false)
    end

    it 'handles symbol keys' do
      expect(instance.reserved_key?(:'mcp:symbol')).to be(true)
      expect(instance.reserved_key?(:valid_symbol)).to be(false)
    end

    it 'is case sensitive' do
      expect(instance.reserved_key?('MCP:uppercase')).to be(false)
      expect(instance.reserved_key?('Mcp:mixed')).to be(false)
    end
  end

  describe '#format_meta_field' do
    it 'returns nil for nil input' do
      expect(instance.format_meta_field(nil)).to be_nil
    end

    it 'returns nil for empty hash' do
      expect(instance.format_meta_field({})).to be_nil
    end

    it 'returns sanitized metadata for valid input' do
      metadata = {
        'valid_key' => 'value',
        'mcp:reserved' => 'bad_value'
      }
      
      result = instance.format_meta_field(metadata)
      expect(result).to eq({ 'valid_key' => 'value' })
    end

    it 'returns nil if all keys are filtered out' do
      metadata = {
        'mcp:reserved1' => 'value1',
        'mcp-reserved2' => 'value2',
        '' => 'empty'
      }
      
      result = instance.format_meta_field(metadata)
      expect(result).to be_nil
    end
  end
end