# frozen_string_literal: true
require 'spec_helper'
require 'base64'

RSpec.describe FastMcp::Prompt do
  let(:roles) { { assistant: 'assistant', user: 'user' } }

  describe '.prompt_name' do
    it 'sets and returns the name' do
      test_class = Class.new(described_class)
      test_class.prompt_name('custom_prompt')

      expect(test_class.prompt_name).to eq('custom_prompt')
    end

    it 'returns the current name when called with nil' do
      test_class = Class.new(described_class)
      test_class.prompt_name('custom_prompt')

      expect(test_class.prompt_name(nil)).to eq('custom_prompt')
    end

    it 'returns a snake_cased version of the class name for named classes when name is not set' do
      # Create a class with a known name in the FastMcp namespace
      module FastMcp
        class ExampleTestPrompt < Prompt; end
      end

      expect(FastMcp::ExampleTestPrompt.prompt_name).to eq('example_test')
      
      # Clean up
      FastMcp.send(:remove_const, :ExampleTestPrompt)
    end
  end

  describe '.description' do
    it 'sets and returns the description' do
      test_class = Class.new(described_class)
      test_class.description('A test prompt')

      expect(test_class.description).to eq('A test prompt')
    end

    it 'returns the current description when called with nil' do
      test_class = Class.new(described_class)
      test_class.description('A test prompt')

      expect(test_class.description(nil)).to eq('A test prompt')
    end
  end

  describe '.arguments' do
    it 'sets up the input schema using Dry::Schema' do
      test_class = Class.new(described_class) do
        arguments do
          required(:code).filled(:string)
          optional(:programming_language).filled(:string)
        end
      end

      expect(test_class.input_schema).to be_a(Dry::Schema::JSON)
    end
  end

  describe '.input_schema_to_json' do
    it 'returns nil when no input schema is defined' do
      test_class = Class.new(described_class)
      expect(test_class.input_schema_to_json).to be_nil
    end

    it 'converts the schema to JSON format using SchemaCompiler' do
      test_class = Class.new(described_class) do
        arguments do
          required(:code).filled(:string).description('Code to analyze')
          optional(:programming_language).filled(:string).description('Language the code is written in')
        end
      end

      json_schema = test_class.input_schema_to_json
      expect(json_schema[:type]).to eq('object')
      expect(json_schema[:properties][:code][:type]).to eq('string')
      expect(json_schema[:properties][:code][:description]).to eq('Code to analyze')
      expect(json_schema[:properties][:programming_language][:type]).to eq('string')
      expect(json_schema[:properties][:programming_language][:description]).to eq('Language the code is written in')
      expect(json_schema[:required]).to include('code')
      expect(json_schema[:required]).not_to include('programming_language')
    end
  end

  describe '.call' do
    it 'raises NotImplementedError by default' do
      test_class = Class.new(described_class)
      expect { test_class.call }.to raise_error(NotImplementedError, 'Subclasses must implement the call method')
    end
  end

  describe '#call_with_schema_validation!' do
    let(:test_class) do
      Class.new(described_class) do
        arguments do
          required(:code).filled(:string)
          optional(:programming_language).filled(:string)
        end

        def call(code:, programming_language: nil)
          messages(
            assistant: "I'll review your #{programming_language || 'code'}.",
            user: "Please review: #{code}"
          )
        end
      end
    end

    let(:instance) { test_class.new }


    it 'validates arguments against the schema and calls the method' do
      result = instance.call_with_schema_validation!(code: 'def hello(): pass', programming_language: 'Python')
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result[0][:role]).to eq('assistant')
      expect(result[0][:content][:text]).to eq("I'll review your Python.")
      expect(result[1][:role]).to eq('user')
      expect(result[1][:content][:text]).to eq('Please review: def hello(): pass')
    end

    it 'works with optional parameters omitted' do
      result = instance.call_with_schema_validation!(code: 'def hello(): pass')
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result[0][:role]).to eq('assistant')
      expect(result[0][:content][:text]).to eq("I'll review your code.")
      expect(result[1][:role]).to eq('user')
      expect(result[1][:content][:text]).to eq('Please review: def hello(): pass')
    end

    it 'raises InvalidArgumentsError when validation fails' do
      expect do
        instance.call_with_schema_validation!(programming_language: 'Python')
      end.to raise_error(FastMcp::Prompt::InvalidArgumentsError)
    end
  end

  describe '#message' do
    let(:instance) { described_class.new }

    it 'creates a valid message with text content' do
      message = instance.message(
        role: 'user',
        content: {
          type: 'text',
          text: 'Hello, world!'
        }
      )

      expect(message[:role]).to eq('user')
      expect(message[:content][:type]).to eq('text')
      expect(message[:content][:text]).to eq('Hello, world!')
    end

    it 'creates a valid message with image content' do
      # Using valid base64 data for testing
      valid_base64 = Base64.strict_encode64('test image data')
      
      message = instance.message(
        role: 'user',
        content: {
          type: 'image',
          data: valid_base64,
          mimeType: 'image/png'
        }
      )

      expect(message[:role]).to eq('user')
      expect(message[:content][:type]).to eq('image')
      expect(message[:content][:data]).to eq(valid_base64)
      expect(message[:content][:mimeType]).to eq('image/png')
    end

    it 'creates a valid message with resource content' do
      message = instance.message(
        role: 'assistant',
        content: {
          type: 'resource',
          resource: {
            uri: 'resource://example',
            mimeType: 'text/plain',
            text: 'Resource content'
          }
        }
      )

      expect(message[:role]).to eq('assistant')
      expect(message[:content][:type]).to eq('resource')
      expect(message[:content][:resource][:uri]).to eq('resource://example')
      expect(message[:content][:resource][:mimeType]).to eq('text/plain')
      expect(message[:content][:resource][:text]).to eq('Resource content')
    end

    it 'raises an error for invalid role' do
      expect do
        instance.message(
          role: 'invalid_role',
          content: {
            type: 'text',
            text: 'Hello, world!'
          }
        )
      end.to raise_error(ArgumentError, /Invalid role/)
    end

    it 'raises an error for invalid content type' do
      expect do
        instance.message(
          role: 'user',
          content: {
            type: 'invalid_type',
            text: 'Hello, world!'
          }
        )
      end.to raise_error(ArgumentError, /Invalid content type/)
    end

    it 'raises an error for missing text in text content' do
      expect do
        instance.message(
          role: 'user',
          content: {
            type: 'text'
          }
        )
      end.to raise_error(ArgumentError, /Missing :text/)
    end

    it 'raises an error for missing data in image content' do
      expect do
        instance.message(
          role: 'user',
          content: {
            type: 'image',
            mimeType: 'image/png'
          }
        )
      end.to raise_error(ArgumentError, /Missing :data/)
    end

    it 'raises an error for missing mimeType in image content' do
      expect do
        instance.message(
          role: 'user',
          content: {
            type: 'image',
            data: 'base64-encoded-image-data'
          }
        )
      end.to raise_error(ArgumentError, /Missing :mimeType/)
    end
  end

  describe '#messages' do
    let(:instance) { described_class.new }

    it 'creates multiple messages from a hash' do
      result = instance.messages(
        assistant: 'Hello!',
        user: 'How are you?'
      )

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result[0][:role]).to eq('assistant')
      expect(result[0][:content][:type]).to eq('text')
      expect(result[0][:content][:text]).to eq('Hello!')
      expect(result[1][:role]).to eq('user')
      expect(result[1][:content][:type]).to eq('text')
      expect(result[1][:content][:text]).to eq('How are you?')
    end

    it 'preserves the order of messages' do
      result = instance.messages(
        user_1: 'First message',
        assistant: 'Second message',
        user_2: 'Third message'
      )

      expect(result.size).to eq(3)
      expect(result[0][:content][:text]).to eq('First message')
      expect(result[1][:content][:text]).to eq('Second message')
      expect(result[2][:content][:text]).to eq('Third message')
    end

    it 'raises an error for empty messages hash' do
      expect do
        instance.messages({})
      end.to raise_error(ArgumentError, /At least one message must be provided/)
    end

    it 'raises an error for invalid role' do
      expect do
        instance.messages(
          invalid_role: 'Hello!'
        )
      end.to raise_error(KeyError, /key not found: :invalid_role/)
    end
  end

  describe '#text_content' do
    let(:instance) { described_class.new }

    it 'creates a valid text content object' do
      content = instance.text_content('Hello, world!')
      expect(content[:type]).to eq('text')
      expect(content[:text]).to eq('Hello, world!')
    end
  end

  describe '#image_content' do
    let(:instance) { described_class.new }

    it 'creates a valid image content object' do
      # Using valid base64 data for testing
      valid_base64 = Base64.strict_encode64('test image data')
      
      content = instance.image_content(valid_base64, 'image/png')
      expect(content[:type]).to eq('image')
      expect(content[:data]).to eq(valid_base64)
      expect(content[:mimeType]).to eq('image/png')
    end
  end

  describe '#resource_content' do
    let(:instance) { described_class.new }

    it 'creates a valid resource content object with text' do
      content = instance.resource_content('resource://example', 'text/plain', text: 'Resource content')
      expect(content[:type]).to eq('resource')
      expect(content[:resource][:uri]).to eq('resource://example')
      expect(content[:resource][:mimeType]).to eq('text/plain')
      expect(content[:resource][:text]).to eq('Resource content')
      expect(content[:resource][:blob]).to be_nil
    end

    it 'creates a valid resource content object with blob' do
      content = instance.resource_content('resource://example', 'application/octet-stream', blob: 'binary_data')
      expect(content[:type]).to eq('resource')
      expect(content[:resource][:uri]).to eq('resource://example')
      expect(content[:resource][:mimeType]).to eq('application/octet-stream')
      expect(content[:resource][:blob]).to eq('binary_data')
      expect(content[:resource][:text]).to be_nil
    end
  end

  # Integration test with ERB templates
  describe 'integration with ERB templates' do
    let(:test_class) do
      Class.new(described_class) do
        arguments do
          required(:code).filled(:string)
          optional(:programming_language).filled(:string)
        end

        def call(code:, programming_language: nil)
          # Create templates inline for testing
          assistant_template = "I'll help you review your <%= programming_language || 'code' %>."
          user_template = "<% if programming_language %>\nPlease review this <%= programming_language %> code:\n<%= code %>\n<% else %>\nPlease review this code:\n<%= code %>\n<% end %>"

          messages(
            assistant: ERB.new(assistant_template).result(binding),
            user: ERB.new(user_template).result(binding)
          )
        end
      end
    end

    let(:instance) { test_class.new }

    it 'correctly renders ERB templates with all parameters' do
      result = instance.call_with_schema_validation!(
        code: 'def hello(): pass',
        programming_language: 'Python'
      )

      expect(result[0][:content][:text]).to eq("I'll help you review your Python.")
      expect(result[1][:content][:text]).to eq("\nPlease review this Python code:\ndef hello(): pass\n")
    end

    it 'correctly renders ERB templates with optional parameters omitted' do
      result = instance.call_with_schema_validation!(
        code: 'def hello(): pass'
      )

      expect(result[0][:content][:text]).to eq("I'll help you review your code.")
      expect(result[1][:content][:text]).to eq("\nPlease review this code:\ndef hello(): pass\n")
    end
  end
end
