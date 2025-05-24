# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/base_adapter'
require 'support/shared/test_base_adapter'

class TestBaseAdapter < FastMcp::AutoDerive::BaseAdapter
  include TestBaseAdapterHelper

  def self.read_only
    true
  end

  def self.read_only?
    @read_only_hint.nil? ? read_only : @read_only_hint
  end

  def self.read_only_hint=(value)
    @read_only_hint = value
  end
end

RSpec.describe FastMcp::AutoDerive::BaseAdapter do
  describe 'abstract methods' do
    subject(:adapter) { described_class.new }

    %i[method_name class_name description].each do |method|
      it "requires subclasses to implement #{method}" do
        expect { described_class.public_send(method) }
          .to raise_error(NotImplementedError, "Subclasses must define #{method}")
      end
    end

    it 'requires subclasses to implement call' do
      expect { adapter.call({}) }
        .to raise_error(NotImplementedError, 'Subclasses must implement the call method')
    end
  end

  describe '.parameters' do
    it 'returns an empty hash by default' do
      expect(described_class.parameters).to eq({})
    end
  end

  describe '.read_only?' do
    it 'returns true by default' do
      expect(described_class.read_only?).to be(true)
    end
  end

  describe '.finder_key' do
    it 'returns :id by default' do
      expect(described_class.finder_key).to eq(:id)
    end
  end

  describe '.post_process' do
    it 'returns the result unchanged by default' do
      result = { test: 'value' }
      expect(described_class.post_process(result, {})).to eq(result)
    end
  end

  describe '.annotations' do
    it 'returns a hash with default annotation values' do
      expect(described_class.annotations).to include(
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true
      )
    end
  end

  describe '.to_tool_definition' do
    let(:test_adapter_class) do
      Class.new(described_class) do
        include TestBaseAdapterHelper

        def self.tool_name; 'test_tool'; end
        def self.method_name; :test_method; end
        def self.class_name; 'TestClass'; end
        def self.description; 'Test description'; end
        def self.input_schema_to_json; { type: 'object', properties: {} }; end
      end
    end

    it 'returns a hash with tool definition properties' do
      tool_def = test_adapter_class.to_tool_definition
      expect(tool_def).to include(
        name: 'test_tool',
        description: 'Test description',
        inputSchema: { type: 'object', properties: {} }
      )
    end
  end

  describe '.create_subclass' do
    let(:subclass) do
      TestBaseAdapter.create_subclass(
        name: 'test_adapter',
        class_name: 'TestClass',
        method_name: :test_method,
        description: 'Test adapter',
        parameters: {
          test_param: { type: :string, description: 'Test parameter' }
        },
        title: 'Test Adapter',
        annotations: {
          readOnlyHint: false,
          destructiveHint: true,
          idempotentHint: true,
          openWorldHint: false
        }
      )
    end

    before do
      subclass.read_only_hint = false
    end

    it 'creates a subclass with all specified attributes' do
      expect(subclass).to have_attributes(
        name: 'test_adapter',
        tool_name: 'test_adapter',
        class_name: 'TestClass',
        method_name: :test_method,
        description: 'Test adapter',
        title: 'Test Adapter'
      )
      expect(subclass.parameters).to include(test_param: { type: :string, description: 'Test parameter' })
      expect(subclass).to have_attributes(
        read_only?: false,
        destructive?: true,
        idempotent?: true,
        open_world?: false
      )
    end
  end

  describe '#serialize_result' do
    subject(:adapter) { Class.new(described_class).new }

    context 'with ActiveRecord instance' do
      let(:record) do
        instance_double(ActiveRecord::Base).tap do |r|
          allow(r).to receive(:is_a?).with(ActiveRecord::Base).and_return(true)
          allow(r).to receive(:as_json).and_return({ id: 1, name: 'Test' })
          allow(r).to receive(:instance_variable_defined?).with(:@double_name).and_return(true)
          allow(r).to receive(:instance_variable_get).with(:@double_name).and_return("ActiveRecord::Base")
        end
      end

      it 'serializes to JSON' do
        expect(adapter.serialize_result(record)).to eq({ id: 1, name: 'Test' })
      end
    end

    context 'with array of ActiveRecord instances' do
      let(:records) do
        [
          instance_double(ActiveRecord::Base, as_json: { id: 1, name: 'Test 1' }),
          instance_double(ActiveRecord::Base, as_json: { id: 2, name: 'Test 2' })
        ].each do |record|
          allow(record).to receive(:is_a?).and_return(false)
          allow(record).to receive(:is_a?).with(ActiveRecord::Base).and_return(true)
        end
      end

      it 'serializes each record to JSON' do
        expect(adapter.serialize_result(records)).to eq([
          { id: 1, name: 'Test 1' },
          { id: 2, name: 'Test 2' }
        ])
      end
    end

    context 'with non-ActiveRecord data' do
      it 'returns the data unchanged' do
        data = { test: 'value' }
        expect(adapter.serialize_result(data)).to eq(data)
      end
    end
  end
end
