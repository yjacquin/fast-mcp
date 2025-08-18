# frozen_string_literal: true
require 'spec_helper'
require 'base64'

RSpec.describe FastMcp::MessageBuilder do
  let(:builder) { described_class.new }

  describe '#initialize' do
    it 'initializes with empty messages array' do
      expect(builder.messages).to eq([])
    end
  end

  describe '#add_message' do
    it 'adds a message with specified role and content' do
      builder.add_message(role: 'user', content: 'Hello!')
      expect(builder.messages).to eq([{ role: 'user', content: 'Hello!' }])
    end

    it 'returns self for method chaining' do
      result = builder.add_message(role: 'user', content: 'Hello!')
      expect(result).to eq(builder)
    end

    it 'supports multiple messages' do
      builder.add_message(role: 'user', content: 'First')
             .add_message(role: 'assistant', content: 'Second')

      expect(builder.messages).to eq([
        { role: 'user', content: 'First' },
        { role: 'assistant', content: 'Second' }
      ])
    end
  end

  describe '#user' do
    it 'adds a user message' do
      builder.user('Hello from user')
      expect(builder.messages).to eq([{ role: 'user', content: 'Hello from user' }])
    end
  end

  describe '#assistant' do
    it 'adds an assistant message' do
      builder.assistant('Hello from assistant')
      expect(builder.messages).to eq([{ role: 'assistant', content: 'Hello from assistant' }])
    end
  end

  describe 'multiple same-role messages' do
    it 'supports multiple user messages' do
      builder.user('First user message')
             .user('Second user message')

      expect(builder.messages).to eq([
        { role: 'user', content: 'First user message' },
        { role: 'user', content: 'Second user message' }
      ])
    end

    it 'supports complex conversation patterns' do
      builder.user('Example 1')
             .assistant('Response 1')
             .user('Example 2')
             .assistant('Response 2')
             .user('Follow-up question')

      expect(builder.messages.size).to eq(5)
      expect(builder.messages[0]).to eq({ role: 'user', content: 'Example 1' })
      expect(builder.messages[1]).to eq({ role: 'assistant', content: 'Response 1' })
      expect(builder.messages[4]).to eq({ role: 'user', content: 'Follow-up question' })
    end
  end
end

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

    describe 'with hash input (backward compatibility)' do
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

    describe 'with array input' do
      it 'creates multiple messages from an array of message hashes' do
        result = instance.messages([
          { role: 'user', content: 'Hello!' },
          { role: 'assistant', content: 'Hi there!' },
          { role: 'user', content: 'How are you?' }
        ])

        expect(result).to be_an(Array)
        expect(result.size).to eq(3)
        expect(result[0][:role]).to eq('user')
        expect(result[0][:content][:type]).to eq('text')
        expect(result[0][:content][:text]).to eq('Hello!')
        expect(result[1][:role]).to eq('assistant')
        expect(result[1][:content][:type]).to eq('text')
        expect(result[1][:content][:text]).to eq('Hi there!')
        expect(result[2][:role]).to eq('user')
        expect(result[2][:content][:type]).to eq('text')
        expect(result[2][:content][:text]).to eq('How are you?')
      end

      it 'supports multiple messages with the same role' do
        result = instance.messages([
          { role: 'user', content: 'Example 1' },
          { role: 'assistant', content: 'Response 1' },
          { role: 'user', content: 'Example 2' },
          { role: 'assistant', content: 'Response 2' }
        ])

        expect(result.size).to eq(4)
        expect(result[0][:role]).to eq('user')
        expect(result[0][:content][:text]).to eq('Example 1')
        expect(result[1][:role]).to eq('assistant')
        expect(result[1][:content][:text]).to eq('Response 1')
        expect(result[2][:role]).to eq('user')
        expect(result[2][:content][:text]).to eq('Example 2')
        expect(result[3][:role]).to eq('assistant')
        expect(result[3][:content][:text]).to eq('Response 2')
      end

      it 'handles complex content types in array format' do
        valid_base64 = Base64.strict_encode64('test image data')
        
        result = instance.messages([
          { 
            role: 'user', 
            content: {
              type: 'image',
              data: valid_base64,
              mimeType: 'image/png'
            }
          },
          {
            role: 'assistant',
            content: {
              type: 'resource',
              resource: {
                uri: 'resource://example',
                mimeType: 'text/plain',
                text: 'Resource content'
              }
            }
          }
        ])

        expect(result.size).to eq(2)
        expect(result[0][:content][:type]).to eq('image')
        expect(result[0][:content][:data]).to eq(valid_base64)
        expect(result[1][:content][:type]).to eq('resource')
        expect(result[1][:content][:resource][:uri]).to eq('resource://example')
      end

      it 'raises an error for empty array' do
        expect do
          instance.messages([])
        end.to raise_error(ArgumentError, /At least one message must be provided/)
      end

      it 'raises an error for invalid message structure' do
        expect do
          instance.messages([
            { role: 'user' }  # missing content
          ])
        end.to raise_error(ArgumentError, /Each message must be a hash with :role and :content keys/)
      end

      it 'raises an error for invalid role in array format' do
        expect do
          instance.messages([
            { role: 'invalid_role', content: 'Hello!' }
          ])
        end.to raise_error(ArgumentError, /Invalid role/)
      end
    end

    describe 'with builder pattern' do
      it 'creates messages using block syntax' do
        result = instance.messages do
          user 'Hello!'
          assistant 'Hi there!'
          user 'How are you?'
        end

        expect(result).to be_an(Array)
        expect(result.size).to eq(3)
        expect(result[0][:role]).to eq('user')
        expect(result[0][:content]).to eq('Hello!')
        expect(result[1][:role]).to eq('assistant')
        expect(result[1][:content]).to eq('Hi there!')
        expect(result[2][:role]).to eq('user')
        expect(result[2][:content]).to eq('How are you?')
      end

      it 'supports add_message method for explicit role specification' do
        result = instance.messages do
          add_message(role: 'user', content: 'Example 1')
          add_message(role: 'assistant', content: 'Response 1')
          add_message(role: 'user', content: 'Example 2')
          add_message(role: 'assistant', content: 'Response 2')
        end

        expect(result.size).to eq(4)
        expect(result[0][:role]).to eq('user')
        expect(result[0][:content]).to eq('Example 1')
        expect(result[1][:role]).to eq('assistant')
        expect(result[1][:content]).to eq('Response 1')
        expect(result[2][:role]).to eq('user')
        expect(result[2][:content]).to eq('Example 2')
        expect(result[3][:role]).to eq('assistant')
        expect(result[3][:content]).to eq('Response 2')
      end
    end

    describe 'error handling' do
      it 'raises an error for nil input' do
        expect do
          instance.messages(nil)
        end.to raise_error(ArgumentError, /At least one message must be provided/)
      end

      it 'raises an error for unsupported input types' do
        expect do
          instance.messages('invalid input')
        end.to raise_error(ArgumentError, /Messages input must be an Array or Hash/)
      end
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

  describe "tags" do
    it "supports tag assignment" do
      test_class = Class.new(described_class)
      test_class.tags :ai, :review, :automated
      
      expect(test_class.tags).to eq([:ai, :review, :automated])
    end
    
    it "returns empty array when no tags" do
      test_class = Class.new(described_class)
      expect(test_class.tags).to eq([])
    end

    it "accepts nested arrays and flattens them" do
      test_class = Class.new(described_class)
      test_class.tags [:ai, :review], :automated
      
      expect(test_class.tags).to eq([:ai, :review, :automated])
    end

    it "converts strings to symbols" do
      test_class = Class.new(described_class)
      test_class.tags 'ai', 'review'
      
      expect(test_class.tags).to eq([:ai, :review])
    end
  end

  describe "metadata" do
    it "stores and retrieves metadata" do
      test_class = Class.new(described_class)
      test_class.metadata :version, "1.0"
      test_class.metadata :author, "Test"
      
      expect(test_class.metadata(:version)).to eq("1.0")
      expect(test_class.metadata(:author)).to eq("Test")
    end

    it "returns empty hash when no metadata" do
      test_class = Class.new(described_class)
      expect(test_class.metadata).to eq({})
    end

    it "returns all metadata when called without arguments" do
      test_class = Class.new(described_class)
      test_class.metadata :version, "1.0"
      test_class.metadata :author, "Test"
      
      expect(test_class.metadata).to eq({ version: "1.0", author: "Test" })
    end

    it "returns nil for non-existent metadata keys" do
      test_class = Class.new(described_class)
      expect(test_class.metadata(:non_existent)).to be_nil
    end
  end

  describe "annotations" do
    it "supports annotations hash" do
      test_class = Class.new(described_class)
      test_class.annotations experimental: true, beta: true
      
      expect(test_class.annotations).to eq(experimental: true, beta: true)
    end

    it "returns empty hash when no annotations" do
      test_class = Class.new(described_class)
      expect(test_class.annotations).to eq({})
    end

    it "overwrites existing annotations" do
      test_class = Class.new(described_class)
      test_class.annotations experimental: true
      test_class.annotations beta: true
      
      expect(test_class.annotations).to eq(beta: true)
    end
  end

  describe "authorization" do
    it "supports authorization blocks" do
      test_class = Class.new(described_class) do
        authorize { |user:| user.admin? }
      end
      
      prompt = test_class.new(headers: {})
      admin = double(admin?: true)
      user = double(admin?: false)
      
      expect(prompt.authorized?(user: admin)).to be true
      expect(prompt.authorized?(user: user)).to be false
    end
    
    it "allows multiple authorization blocks" do
      test_class = Class.new(described_class) do
        authorize { |user:| user.logged_in? }
        authorize { |user:| user.has_permission?(:prompts) }
      end
      
      prompt = test_class.new(headers: {})
      authorized_user = double(logged_in?: true, has_permission?: true)
      unauthorized_user = double(logged_in?: true, has_permission?: false)
      not_logged_in_user = double(logged_in?: false, has_permission?: true)
      
      expect(prompt.authorized?(user: authorized_user)).to be true
      expect(prompt.authorized?(user: unauthorized_user)).to be false
      expect(prompt.authorized?(user: not_logged_in_user)).to be false
    end

    it "returns true when no authorization blocks are defined" do
      test_class = Class.new(described_class)
      prompt = test_class.new(headers: {})
      
      expect(prompt.authorized?).to be true
    end

    it "validates arguments before running authorization" do
      test_class = Class.new(described_class) do
        arguments do
          required(:user).filled(:hash)
        end
        
        authorize { |user:| user[:admin] }
      end
      
      prompt = test_class.new(headers: {})
      
      expect {
        prompt.authorized?(invalid: "data")
      }.to raise_error(FastMcp::Prompt::InvalidArgumentsError)
    end

    it "supports authorization blocks without parameters" do
      test_class = Class.new(described_class) do
        authorize { true }
      end
      
      prompt = test_class.new(headers: {})
      expect(prompt.authorized?).to be true
    end
  end

  describe "headers" do
    it "accepts headers on initialization" do
      prompt = described_class.new(headers: { "Authorization" => "Bearer token" })
      expect(prompt.headers).to eq({ "Authorization" => "Bearer token" })
    end

    it "defaults to empty hash when no headers provided" do
      prompt = described_class.new
      expect(prompt.headers).to eq({})
    end

    it "allows access to headers in authorization blocks" do
      test_class = Class.new(described_class) do
        authorize { headers["Authorization"] == "Bearer valid-token" }
      end
      
      valid_prompt = test_class.new(headers: { "Authorization" => "Bearer valid-token" })
      invalid_prompt = test_class.new(headers: { "Authorization" => "Bearer invalid-token" })
      
      expect(valid_prompt.authorized?).to be true
      expect(invalid_prompt.authorized?).to be false
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

  describe "prompt filtering" do
    let(:server) { FastMcp::Server.new(name: "test", version: "1.0.0") }
    
    before do
      # Create some test prompt classes for filtering
      @public_prompt = Class.new(described_class) do
        prompt_name "public_prompt"
        tags :public
        description "A public prompt"
        def call
          messages(user: "Public prompt")
        end
      end
      
      @private_prompt = Class.new(described_class) do
        prompt_name "private_prompt"
        tags :private
        description "A private prompt"
        def call
          messages(user: "Private prompt")
        end
      end
      
      @admin_prompt = Class.new(described_class) do
        prompt_name "admin_prompt"
        tags :admin
        description "An admin prompt"
        authorize { |user:| user[:admin] }
        arguments do
          required(:user).filled(:hash)
        end
        def call(**args)
          messages(user: "Admin prompt")
        end
      end
    end

    it "filters prompts by tags" do
      server.register_prompt(@public_prompt)
      server.register_prompt(@private_prompt)
      
      server.filter_prompts do |request, prompts|
        prompts.select { |p| p.tags.include?(:public) }
      end
      
      # Create a filtered copy
      request = double("request")
      filtered_server = server.create_filtered_copy(request)
      
      # Verify only public prompts are included
      expect(filtered_server.prompts.size).to eq(1)
      expect(filtered_server.prompts.values.first).to eq(@public_prompt)
    end
    
    it "chains multiple filters" do
      server.register_prompt(@public_prompt)
      server.register_prompt(@private_prompt)
      server.register_prompt(@admin_prompt)
      
      # First filter: only non-admin prompts
      server.filter_prompts { |r, p| p.reject { |prompt| prompt.tags.include?(:admin) } }
      # Second filter: only prompts with tags
      server.filter_prompts { |r, p| p.select { |prompt| prompt.tags.any? } }
      
      request = double("request")
      filtered_server = server.create_filtered_copy(request)
      
      # Should include public and private, but not admin
      expect(filtered_server.prompts.size).to eq(2)
      prompt_classes = filtered_server.prompts.values
      expect(prompt_classes).to include(@public_prompt, @private_prompt)
      expect(prompt_classes).not_to include(@admin_prompt)
    end

    it "supports filtering by authorization status" do
      server.register_prompt(@public_prompt)
      server.register_prompt(@admin_prompt)
      
      # Filter to only include prompts that don't require authorization or are authorized
      server.filter_prompts do |request, prompts|
        prompts.select do |prompt_class|
          # Check if prompt has authorization requirements
          auth_blocks = prompt_class.authorization_blocks
          if auth_blocks.nil? || auth_blocks.empty?
            true # No authorization required
          else
            # Check authorization with mock user data
            begin
              prompt_instance = prompt_class.new(headers: request.headers || {})
              prompt_instance.authorized?(user: { admin: true })
            rescue
              false # Authorization failed
            end
          end
        end
      end
      
      # Mock request with headers
      request = double("request", headers: { "user" => "admin" })
      filtered_server = server.create_filtered_copy(request)
      
      # Should include both prompts since we're passing admin user
      expect(filtered_server.prompts.size).to eq(2)
    end

    it "handles empty filter results" do
      server.register_prompt(@public_prompt)
      
      # Filter that excludes everything
      server.filter_prompts { |r, p| [] }
      
      request = double("request")
      filtered_server = server.create_filtered_copy(request)
      
      expect(filtered_server.prompts).to be_empty
    end
  end
end
