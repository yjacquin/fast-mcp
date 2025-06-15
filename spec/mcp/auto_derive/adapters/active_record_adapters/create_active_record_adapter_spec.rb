# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/adapters/active_record_adapters/create_active_record_adapter'

module FastMcp
  module AutoDerive
    module Tools; end
  end
end

RSpec.describe FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::CreateActiveRecordAdapter do
  describe '.create_tool' do
    let(:tool_class) { Class.new }

    before do
      allow(described_class).to receive(:create_subclass).and_return(tool_class)
      allow(described_class).to receive(:define_call_method)
      allow(described_class).to receive(:configure_as_fast_mcp_tool)
    end

    it 'creates a subclass with correct parameters' do
      described_class.create_tool

      expect(described_class).to have_received(:create_subclass).with(
        hash_including(
          name: 'create_active_record_model',
          class_name: 'ActiveRecord',
          method_name: :create,
          description: 'Create a new record for any model'
        )
      )
    end

    it 'defines the call method on the subclass' do
      described_class.create_tool
      expect(described_class).to have_received(:define_call_method).with(tool_class)
    end

    it 'configures the subclass as a Fast MCP tool' do
      described_class.create_tool
      expect(described_class).to have_received(:configure_as_fast_mcp_tool).with(tool_class)
    end

    it 'returns the configured subclass' do
      expect(described_class.create_tool).to eq(tool_class)
    end
  end

  describe '.configure_as_fast_mcp_tool' do
    let(:subclass) { Class.new }

    it 'sets constants for the tool in appropriate namespaces' do
      described_class.configure_as_fast_mcp_tool(subclass)

      expect(FastMcp::AutoDerive::Tools.const_get('CreateActiveRecordModel')).to eq(subclass)
      expect(Object.const_get('MCPCreateActiveRecordModel')).to eq(subclass)
      expect(Object.const_get('ToolsCreateActiveRecordModel')).to eq(subclass)
    end
  end

  describe '.define_call_method' do
    let(:klass) { Class.new }
    let(:record) { instance_double(ActiveRecord::Base) }
    let(:test_model_class) do
      Class.new do
        def self.ancestors
          [ActiveRecord::Base]
        end

        def self.create(attributes)
          @record
        end

        def self.record=(record)
          @record = record
        end
      end
    end

    before do
      described_class.define_call_method(klass)

      test_model_class.record = record

      allow(record).to receive(:as_json).and_return({ id: '123', name: 'New Test' })

      unless Object.const_defined?('TestModel')
        Object.const_set('TestModel', test_model_class)
      end
    end

    after do
      Object.send(:remove_const, 'TestModel') if Object.const_defined?('TestModel')
    end

    it 'implements a call method that creates a record' do
      instance = klass.new

      allow(instance).to receive(:serialize_result).and_return({ id: '123', name: 'New Test' })

      result = instance.call({
        'model_name' => 'TestModel',
        'attributes' => '{"name":"New Test"}'
      })

      expect(result).to eq({ id: '123', name: 'New Test' })
    end

    context 'with invalid parameters' do
      let(:instance) { klass.new }

      it 'raises an error when model_name is missing' do
        expect {
          instance.call({ 'attributes' => '{}' })
        }.to raise_error("Required parameter 'model_name' not provided")
      end

      it 'raises an error when attributes is missing' do
        expect {
          instance.call({ 'model_name' => 'TestModel' })
        }.to raise_error("Required parameter 'attributes' not provided")
      end
    end
  end

  describe '.subclass_params' do
    it 'returns the correct parameters for creating a subclass' do
      params = described_class.subclass_params

      expect(params[:name]).to eq('create_active_record_model')
      expect(params[:class_name]).to eq('ActiveRecord')
      expect(params[:method_name]).to eq(:create)
      expect(params[:description]).to eq('Create a new record for any model')

      expect(params[:parameters]).to include(
        model_name: hash_including(type: :string, required: true),
        attributes: hash_including(type: :string, required: true)
      )

      expect(params[:annotations]).to include(
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true
      )
    end
  end
end
