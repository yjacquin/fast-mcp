# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/adapters/model_method_adapter'

RSpec.describe FastMcp::AutoDerive::Adapters::ModelMethodAdapter do
  let(:test_model_class) do
    Class.new do
      class << self
        attr_accessor :mcp_exposed_methods

        def name
          'TestModel'
        end

        def underscore
          'test_model'
        end

        def find_by(id:)
          @instance ||= new
        end
      end

      self.mcp_exposed_methods = {}

      include FastMcp::AutoDerive

      def test_method(param1:)
        "test result with #{param1}"
      end

      def is_valid?
        true
      end

      def self.expose_to_mcp(method_name, description:, parameters: {}, read_only: true, finder_key: :id, tool_name: nil,
                            title: nil, destructive: nil, idempotent: false, open_world: true)
        tool_name ||= "#{name.underscore}_#{method_name}"

        self.mcp_exposed_methods = mcp_exposed_methods.merge(
          tool_name => {
            method_name: method_name,
            description: description,
            parameters: parameters,
            read_only: read_only,
            finder_key: finder_key,
            class_name: name,
            title: title,
            destructive: destructive,
            idempotent: idempotent,
            open_world: open_world
          }
        )
      end

      expose_to_mcp :test_method,
                   description: 'Test method',
                   parameters: { param1: { type: :string, description: 'Test parameter', required: true } },
                   read_only: true

      expose_to_mcp :is_valid?,
                   description: 'Check if the model is valid',
                   read_only: true
    end
  end

  describe '.derive_model_method' do
    let(:tool_name) { test_model_class.mcp_exposed_methods.keys.first }
    let(:metadata) { test_model_class.mcp_exposed_methods[tool_name] }

    it 'creates a subclass with correct parameters' do
      tool_class = described_class.derive_model_method(test_model_class, :test_method, metadata)

      expect(tool_class.name).to eq('test_model_test_method')
      expect(tool_class.class_name).to eq('TestModel')
      expect(tool_class.method_name).to eq(:test_method)
      expect(tool_class.description).to eq('Test method')
      expect(tool_class.parameters).to include(param1: { type: :string, description: 'Test parameter', required: true })
      expect(tool_class.read_only?).to be(true)
    end

    it 'can call the method through the tool with parameters' do
      tool_class = described_class.derive_model_method(test_model_class, :test_method, metadata)
      instance = tool_class.new
      result = instance.call(id: 1, param1: 'test')
      expect(result).to eq('test result with test')
    end

    it 'can call a question mark method through the tool' do
      question_mark_tool_name = test_model_class.mcp_exposed_methods.keys.last
      question_mark_metadata = test_model_class.mcp_exposed_methods[question_mark_tool_name]
      tool_class = described_class.derive_model_method(test_model_class, :is_valid?, question_mark_metadata)
      instance = tool_class.new
      result = instance.call(id: 1)
      expect(result).to be true
    end
  end
end
