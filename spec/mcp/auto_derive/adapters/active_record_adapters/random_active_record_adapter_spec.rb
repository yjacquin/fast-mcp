# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/adapters/active_record_adapters/random_active_record_adapter'

module FastMcp
  module AutoDerive
    module Tools; end
  end
end

RSpec.describe FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::RandomActiveRecordAdapter do
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
          name: 'random_active_record_model',
          class_name: 'ActiveRecord',
          method_name: :random,
          description: 'Get 5 random records from any model'
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

      expect(FastMcp::AutoDerive::Tools.const_get('RandomActiveRecordModel')).to eq(subclass)
      expect(Object.const_get('MCPRandomActiveRecordModel')).to eq(subclass)
      expect(Object.const_get('ToolsRandomActiveRecordModel')).to eq(subclass)
    end
  end

  describe '.define_call_method' do
    let(:subclass) { Class.new }
    let(:model_class) { double('ModelClass') }
    let(:records) { [double('Record1'), double('Record2')] }

    before do
      allow(model_class).to receive(:ancestors).and_return([ActiveRecord::Base])
      allow(model_class).to receive(:order).with('RANDOM()').and_return(model_class)
      allow(model_class).to receive(:limit).with(5).and_return(records)
    end

    it 'implements a call method that gets random records' do
      described_class.define_call_method(subclass)
      instance = subclass.new

      allow(instance).to receive(:serialize_result).with(records).and_return(records)
      model_name = double('ModelName')
      allow(model_name).to receive(:constantize).and_return(model_class)

      result = instance.call(model_name: model_name)
      expect(result).to eq(records)
    end

    context 'with invalid parameters' do
      it 'raises an error when model_name is missing' do
        described_class.define_call_method(subclass)
        instance = subclass.new

        expect { instance.call({}) }.to raise_error("Required parameter 'model_name' not provided")
      end

      it 'raises an error when model is not an ActiveRecord model' do
        described_class.define_call_method(subclass)
        instance = subclass.new

        non_active_record_class = double('NonActiveRecordClass')
        allow(non_active_record_class).to receive(:ancestors).and_return([])
        model_name = double('ModelName', to_s: 'TestModel')
        allow(model_name).to receive(:constantize).and_return(non_active_record_class)

        expect { instance.call(model_name: model_name) }
          .to raise_error("Class 'TestModel' is not an ActiveRecord model")
      end

      it 'raises an error when model is not found' do
        described_class.define_call_method(subclass)
        instance = subclass.new

        model_name = double('ModelName', to_s: 'TestModel')
        allow(model_name).to receive(:constantize)
          .and_raise(NameError.new('uninitialized constant TestModel'))

        expect { instance.call(model_name: model_name) }
          .to raise_error("Model 'TestModel' not found: uninitialized constant TestModel")
      end
    end
  end
end
