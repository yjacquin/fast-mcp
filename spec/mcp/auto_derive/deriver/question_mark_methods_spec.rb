# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/auto_derive'
require 'mcp/auto_derive/auto_derive_configuration'
require 'mcp/auto_derive/deriver/deriver'
require 'mcp/auto_derive/deriver/derive_methods'
require 'mcp/auto_derive/adapters/model_method_adapter'

# Create a test model with a method that has a question mark
class QuestionMarkModel
  class << self
    attr_accessor :mcp_exposed_methods

    def name
      'QuestionMarkModel'
    end

    def underscore
      'question_mark_model'
    end

    # Needed for derive_model_method to work
    def ancestors
      [self]
    end

    def find_by(id:)
      @instance ||= new
    end
  end

  self.mcp_exposed_methods = {}

  include FastMcp::AutoDerive

  # Define a method with a question mark
  def is_special?
    true
  end

  # Expose the method to MCP
  expose_to_mcp :is_special?,
                description: 'Check if the model is special'
end

RSpec.describe "Question mark method integration" do
  let(:model) { QuestionMarkModel }
  let(:sanitized_tool_name) { model.mcp_exposed_methods.keys.first }
  let(:metadata) { model.mcp_exposed_methods[sanitized_tool_name] }

  it "can access the tool by its sanitized name" do
    expect(sanitized_tool_name).to eq('question_mark_model_is_special_is')
    expect(metadata[:method_name]).to eq(:is_special?)
  end

  describe "when deriving a tool from the method" do
    let(:tool_class) do
      # Use the private method to derive the tool class
      FastMcp::AutoDerive::Deriver.send(:derive_model_method, model, sanitized_tool_name, metadata)
    end

    it "creates a valid class constant" do
      expect(tool_class).to be_a(Class)

      # Check if the constant was created in the Tools namespace
      constant_name = sanitized_tool_name.camelize
      expect(FastMcp::AutoDerive::Tools.const_defined?(constant_name)).to be true
    end

    it "preserves the original method name in the derived class" do
      # The method_name stored in the class should still have the question mark
      expect(tool_class.method_name).to eq(:is_special?)
    end

    it "can call the question mark method through the tool" do
      instance = tool_class.new
      result = instance.call(id: 1)
      expect(result).to be true
    end
  end
end
