# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/auto_derive'
require 'mcp/auto_derive/auto_derive_configuration'

RSpec.describe FastMcp::AutoDerive do
  let(:test_model_class) do
    Class.new do
      class << self
        attr_accessor :mcp_exposed_methods

        def name
          'test_model'
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

      def is_valid?
        true
      end

      expose_to_mcp :is_valid?,
                    description: 'Check if the model is valid'
    end
  end

  describe 'method name sanitization' do
    it 'automatically sanitizes tool names for methods with question marks' do
      expect(test_model_class.mcp_exposed_methods.keys).to include('test_model_is_valid_is')
    end

    it 'preserves the original method name in the metadata' do
      sanitized_name = test_model_class.mcp_exposed_methods.keys.first

      expect(test_model_class.mcp_exposed_methods[sanitized_name][:method_name]).to eq(:is_valid?)
    end

    it 'can call the question mark method through the tool' do
      tool_class = FastMcp::AutoDerive::Deriver.send(:derive_model_method,
        test_model_class,
        test_model_class.mcp_exposed_methods.keys.first,
        test_model_class.mcp_exposed_methods.values.first
      )
      instance = tool_class.new
      result = instance.call(id: 1)
      expect(result).to be true
    end
  end
end
