# frozen_string_literal: true

require 'dry-schema'
require 'erb'
require 'base64'

module FastMcp
  # Builder class for creating messages with a fluent API
  #
  # The MessageBuilder provides a convenient way to construct arrays of messages
  # using a fluent interface. It supports method chaining and provides convenience
  # methods for common message roles.
  #
  # @example Basic usage
  #   builder = MessageBuilder.new
  #   builder.user("Hello").assistant("Hi there!")
  #   messages = builder.messages
  #
  # @example Block-style usage
  #   messages = MessageBuilder.new.tap do |b|
  #     b.user("What's the weather?")
  #     b.assistant("It's sunny today!")
  #   end.messages
  #
  # @since 1.6.0
  class MessageBuilder
    # Initialize a new MessageBuilder
    #
    # @since 1.6.0
    def initialize
      @messages = []
    end

    # Array of messages built by this builder
    #
    # @return [Array<Hash>] Array of message hashes with :role and :content keys
    # @since 1.6.0
    attr_reader :messages

    # Add a message with specified role and content
    #
    # @param role [String, Symbol] The role of the message (e.g., 'user', 'assistant')
    # @param content [String, Hash] The content of the message
    # @return [MessageBuilder] Returns self for method chaining
    # @example
    #   builder.add_message(role: 'user', content: 'Hello world')
    # @since 1.6.0
    def add_message(role:, content:)
      @messages << { role: role.to_s, content: content }
      self
    end

    # Convenience method for adding user messages
    #
    # @param content [String, Hash] The content of the user message
    # @return [MessageBuilder] Returns self for method chaining
    # @example
    #   builder.user("What's the weather like today?")
    # @since 1.6.0
    def user(content)
      add_message(role: 'user', content: content)
    end

    # Convenience method for adding assistant messages
    #
    # @param content [String, Hash] The content of the assistant message
    # @return [MessageBuilder] Returns self for method chaining
    # @example
    #   builder.assistant("It's sunny and 75 degrees!")
    # @since 1.6.0
    def assistant(content)
      add_message(role: 'assistant', content: content)
    end
  end

  # Main Prompt class that represents an MCP Prompt
  #
  # The Prompt class provides a framework for creating structured message templates
  # for Language Model interactions following the Model Context Protocol (MCP) specification.
  # It supports argument validation, authorization, message creation with multiple content
  # types, and flexible template patterns.
  #
  # Key features:
  # - Dry::Schema-based argument validation
  # - Authorization blocks for access control
  # - Support for text, image, and resource content types
  # - Fluent message building API
  # - Template interpolation and rendering
  # - Metadata, tags, and annotations support
  #
  # @example Basic prompt implementation
  #   class GreetingPrompt < FastMcp::Prompt
  #     arguments do
  #       required(:name).filled(:string)
  #     end
  #
  #     def self.call(name:)
  #       new.messages(user: "Hello #{name}!")
  #     end
  #   end
  #
  # @example Advanced prompt with authorization
  #   class AdminPrompt < FastMcp::Prompt
  #     authorize { headers['role'] == 'admin' }
  #
  #     def self.call
  #       new.messages(user: "Admin-only content")
  #     end
  #   end
  #
  # @see MessageBuilder
  # @see FastMcp::Resource
  # @see FastMcp::Tool
  # @since 1.6.0
  class Prompt
    # Exception raised when prompt arguments fail validation
    #
    # @since 1.6.0
    class InvalidArgumentsError < StandardError; end

    # Valid message roles supported by the MCP protocol
    #
    # @return [Hash<Symbol, String>] Mapping of role symbols to string values
    # @since 1.6.0
    ROLES = {
      user: 'user',
      assistant: 'assistant'
    }.freeze

    # Content type constant for text content
    # @since 1.6.0
    CONTENT_TYPE_TEXT = 'text'
    
    # Content type constant for image content
    # @since 1.6.0
    CONTENT_TYPE_IMAGE = 'image'
    
    # Content type constant for resource content
    # @since 1.6.0
    CONTENT_TYPE_RESOURCE = 'resource'

    class << self
      # Server instance associated with this prompt class
      #
      # @return [FastMcp::Server, nil] The server instance
      # @since 1.6.0
      attr_accessor :server
      
      # Authorization blocks defined for this prompt class
      #
      # @return [Array<Proc>, nil] Array of authorization blocks
      # @since 1.6.0
      attr_reader :authorization_blocks

      # Define the input schema for prompt arguments using Dry::Schema
      #
      # @param block [Proc] Block containing Dry::Schema definition
      # @return [Dry::Schema::JSON] The configured schema
      # @example
      #   arguments do
      #     required(:name).filled(:string)
      #     optional(:age).filled(:integer)
      #   end
      # @since 1.6.0
      def arguments(&block)
        @input_schema = Dry::Schema.JSON(&block)
      end

      # Get or set tags for this prompt
      #
      # @param tag_list [Array<String, Symbol>] Tags to assign to the prompt
      # @return [Array<Symbol>] Current tags when called without arguments
      # @example Setting tags
      #   tags :utility, :text_processing
      # @example Getting tags
      #   tags # => [:utility, :text_processing]
      # @since 1.6.0
      def tags(*tag_list)
        if tag_list.empty?
          @tags || []
        else
          @tags = tag_list.flatten.map(&:to_sym)
        end
      end

      # Get or set metadata for this prompt
      #
      # @param key [String, Symbol, nil] Metadata key
      # @param value [Object, nil] Metadata value
      # @return [Hash, Object] Full metadata hash, specific value, or nil
      # @example Setting metadata
      #   metadata(:author, "John Doe")
      #   metadata("version", "1.0.0")
      # @example Getting all metadata
      #   metadata # => { author: "John Doe", version: "1.0.0" }
      # @example Getting specific metadata
      #   metadata(:author) # => "John Doe"
      # @since 1.6.0
      def metadata(key = nil, value = nil)
        @metadata ||= {}
        if key.nil?
          @metadata
        elsif value.nil?
          @metadata[key]
        else
          @metadata[key] = value
        end
      end

      # Get or set annotations for this prompt
      #
      # @param annotations_hash [Hash, nil] Hash of annotations to set
      # @return [Hash] Current annotations
      # @example Setting annotations
      #   annotations({
      #     audience: "developers",
      #     level: "intermediate"
      #   })
      # @example Getting annotations
      #   annotations # => { audience: "developers", level: "intermediate" }
      # @since 1.6.0
      def annotations(annotations_hash = nil)
        return @annotations || {} if annotations_hash.nil?

        @annotations = annotations_hash
      end

      # Add an authorization block for this prompt
      #
      # Authorization blocks are executed to determine if a user is authorized
      # to use this prompt. All blocks must return truthy values for authorization.
      #
      # @param block [Proc] Authorization logic block
      # @return [Array<Proc>] Current authorization blocks
      # @example Simple authorization
      #   authorize { headers['role'] == 'admin' }
      # @example Authorization with arguments
      #   authorize { |name:| name != 'blocked_user' }
      # @since 1.6.0
      def authorize(&block)
        @authorization_blocks ||= []
        @authorization_blocks.push block
      end

      # Get the input schema for this prompt
      #
      # @return [Dry::Schema::JSON] The input schema, or empty schema if none defined
      # @since 1.6.0
      def input_schema
        @input_schema ||= Dry::Schema.JSON
      end

      # Get or set the prompt name
      #
      # When no name is provided, auto-generates a name from the class name
      # by removing "Prompt" suffix and converting to snake_case.
      #
      # @param name [String, Symbol, nil] Name to set for the prompt
      # @return [String] The prompt name
      # @example Setting custom name
      #   prompt_name "my_custom_prompt"
      # @example Auto-generated name
      #   # For class "GreetingPrompt"
      #   prompt_name # => "greeting"
      # @since 1.6.0
      def prompt_name(name = nil)
        if name.nil?
          return @name if @name

          # Get the actual class name without namespace
          class_name = self.name.to_s.split('::').last
          # Remove "Prompt" suffix and convert to snake_case
          return class_name.gsub(/Prompt$/, '').gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
        end

        @name = name
      end

      # Get or set the prompt description
      #
      # @param description [String, nil] Description to set
      # @return [String, nil] Current description
      # @example
      #   description "A prompt for generating greetings"
      # @since 1.6.0
      def description(description = nil)
        return @description if description.nil?

        @description = description
      end

      # Execute the prompt with the given arguments
      #
      # This is an abstract method that must be implemented by subclasses.
      # It should return an array of messages or use the messages helper.
      #
      # @param args [Hash] Arguments passed to the prompt
      # @return [Array<Hash>] Array of message hashes
      # @raise [NotImplementedError] Always raised as this is abstract
      # @abstract Subclasses must implement this method
      # @example
      #   def self.call(name:)
      #     new.messages(user: "Hello #{name}!")
      #   end
      # @since 1.6.0
      def call(**args)
        raise NotImplementedError, 'Subclasses must implement the call method'
      end

      # Convert the input schema to JSON Schema format
      #
      # @return [Hash, nil] JSON Schema representation, or nil if no schema defined
      # @since 1.6.0
      def input_schema_to_json
        return nil unless @input_schema

        compiler = SchemaCompiler.new
        compiler.process(@input_schema)
      end
    end

    # Initialize a new Prompt instance
    #
    # @param headers [Hash] Request headers, typically used for authorization
    # @example
    #   prompt = MyPrompt.new(headers: { 'role' => 'admin' })
    # @since 1.6.0
    def initialize(headers: {})
      @headers = headers
    end

    # Request headers for this prompt instance
    #
    # @return [Hash] The headers passed during initialization
    # @since 1.6.0
    attr_reader :headers

    # Execute the prompt with automatic schema validation
    #
    # This method validates the provided arguments against the defined schema
    # before executing the prompt. If validation fails, an exception is raised.
    #
    # @param args [Hash] Arguments to validate and pass to the prompt
    # @return [Array<Hash>] Array of message hashes from the prompt execution
    # @raise [InvalidArgumentsError] When arguments fail schema validation
    # @example
    #   prompt = GreetingPrompt.new
    #   messages = prompt.call_with_schema_validation!(name: "Alice")
    # @since 1.6.0
    def call_with_schema_validation!(**args)
      arg_validation = self.class.input_schema.call(args)
      raise InvalidArgumentsError, arg_validation.errors.to_h.to_json if arg_validation.errors.any?

      call(**args)
    end

    # Check if the current request is authorized to use this prompt
    #
    # Evaluates all authorization blocks defined for this prompt class hierarchy.
    # All authorization blocks must return truthy values for the request to be authorized.
    #
    # @param args [Hash] Arguments to pass to authorization blocks that accept parameters
    # @return [Boolean] true if authorized, false otherwise
    # @raise [InvalidArgumentsError] When arguments fail schema validation
    # @example
    #   prompt = AdminPrompt.new(headers: { 'role' => 'admin' })
    #   if prompt.authorized?(user_id: 123)
    #     # Execute admin-only prompt
    #   end
    # @since 1.6.0
    def authorized?(**args)
      auth_checks = self.class.ancestors.filter_map do |ancestor|
        ancestor.ancestors.include?(FastMcp::Prompt) &&
          ancestor.instance_variable_get(:@authorization_blocks)
      end.flatten

      return true if auth_checks.empty?

      arg_validation = self.class.input_schema.call(args)
      raise InvalidArgumentsError, arg_validation.errors.to_h.to_json if arg_validation.errors.any?

      auth_checks.all? do |auth_check|
        if auth_check.parameters.empty?
          instance_exec(&auth_check)
        else
          instance_exec(**args, &auth_check)
        end
      end
    end

    # Create a single message with the given role and content
    #
    # @param role [String, Symbol] The role of the message ('user' or 'assistant')
    # @param content [String, Hash] The content of the message
    # @return [Hash] A message hash with :role and :content keys
    # @raise [ArgumentError] When role or content is invalid
    # @example
    #   message = prompt.message(role: 'user', content: 'Hello!')
    #   # => { role: 'user', content: { type: 'text', text: 'Hello!' } }
    # @since 1.6.0
    def message(role:, content:)
      validate_role(role)
      validate_content(content)

      {
        role: role,
        content: content
      }
    end

    # Create multiple messages from various input formats
    #
    # This method supports three different ways to create messages:
    # 1. Hash of role => content pairs (backward compatibility)
    # 2. Array of message hashes with :role and :content keys
    # 3. Block-based builder pattern using MessageBuilder
    #
    # @param messages_input [Hash, Array, nil] Input messages in hash or array format
    # @param block [Proc] Optional block for builder pattern
    # @return [Array<Hash>] Array of message hashes with :role and :content keys
    # @raise [ArgumentError] When input format is invalid or no messages provided
    # @example Hash format (backward compatibility)
    #   messages(user: "Hello", assistant: "Hi there!")
    # @example Array format
    #   messages([
    #     { role: 'user', content: 'Hello' },
    #     { role: 'assistant', content: 'Hi there!' }
    #   ])
    # @example Block format
    #   messages do
    #     user "Hello"
    #     assistant "Hi there!"
    #   end
    # @since 1.6.0
    def messages(messages_input = nil, &block)
      if block_given?
        builder = MessageBuilder.new
        builder.instance_eval(&block)
        return builder.messages
      end

      raise ArgumentError, 'At least one message must be provided' if messages_input.nil? || messages_input.empty?

      case messages_input
      when Array
        process_array_messages(messages_input)
      when Hash
        process_hash_messages(messages_input)
      else
        raise ArgumentError, 'Messages input must be an Array or Hash'
      end
    end

    private

    # Process array of message hashes
    def process_array_messages(messages_array)
      messages_array.map do |message_hash|
        unless message_hash.is_a?(Hash) && message_hash[:role] && message_hash[:content]
          raise ArgumentError, 'Each message must be a hash with :role and :content keys'
        end

        role = message_hash[:role].to_s
        content = message_hash[:content]
        
        validate_role(role)
        processed_content = content.is_a?(Hash) && content[:type] ? content : content_from(content)
        validate_content(processed_content)

        {
          role: role,
          content: processed_content
        }
      end
    end

    # Process hash of role => content pairs (backward compatibility)
    def process_hash_messages(messages_hash)
      messages_hash.map do |role_key, content|
        role = role_key.to_s.gsub(/_\d+$/, '').to_sym
        { role: ROLES.fetch(role), content: content_from(content) }
      end
    end

    public

    # Extract and normalize content from various input formats
    #
    # This helper method converts different content formats into standardized
    # content objects with proper type information.
    #
    # @param content [String, Hash] Content in various formats
    # @return [Hash] Normalized content hash with :type key
    # @example String content
    #   content_from("Hello") # => { type: 'text', text: 'Hello' }
    # @example Hash with text
    #   content_from(text: "Hello") # => { type: 'text', text: 'Hello' }
    # @example Hash with image data
    #   content_from(data: "base64data", mimeType: "image/png")
    #   # => { type: 'image', data: 'base64data', mimeType: 'image/png' }
    # @since 1.6.0
    def content_from(content)
      if content.is_a?(String)
        text_content(content)
      elsif content.key?(:text)
        text_content(content[:text])
      elsif content.key?(:data) && content.key?(:mimeType)
        image_content(content[:data], content[:mimeType])
      elsif content.key?(:resource)
        hash
      else
        text_content('unsupported content')
      end
    end

    # Create a text content object
    #
    # @param text [String] The text content
    # @return [Hash] Text content hash with type and text keys
    # @example
    #   text_content("Hello world")
    #   # => { type: 'text', text: 'Hello world' }
    # @since 1.6.0
    def text_content(text)
      {
        type: CONTENT_TYPE_TEXT,
        text: text
      }
    end

    # Create an image content object
    #
    # @param data [String] Base64-encoded image data
    # @param mime_type [String] MIME type of the image (e.g., 'image/png', 'image/jpeg')
    # @return [Hash] Image content hash with type, data, and mimeType keys
    # @example
    #   image_content("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==", "image/png")
    #   # => { type: 'image', data: '...', mimeType: 'image/png' }
    # @since 1.6.0
    def image_content(data, mime_type)
      {
        type: CONTENT_TYPE_IMAGE,
        data: data,
        mimeType: mime_type
      }
    end

    # Create a resource content object
    #
    # @param uri [String] URI of the resource
    # @param mime_type [String] MIME type of the resource
    # @param text [String, nil] Optional text content of the resource
    # @param blob [String, nil] Optional binary blob content (base64-encoded)
    # @return [Hash] Resource content hash with type and resource keys
    # @raise [ArgumentError] When neither text nor blob is provided
    # @example With text content
    #   resource_content("file://readme.txt", "text/plain", text: "Hello world")
    # @example With blob content
    #   resource_content("file://image.png", "image/png", blob: "base64data...")
    # @since 1.6.0
    def resource_content(uri, mime_type, text: nil, blob: nil)
      resource = {
        uri: uri,
        mimeType: mime_type
      }

      resource[:text] = text if text
      resource[:blob] = blob if blob

      {
        type: CONTENT_TYPE_RESOURCE,
        resource: resource
      }
    end

    # Validate that a role is one of the supported values
    #
    # @param role [String, Symbol] The role to validate
    # @return [String] The validated role string
    # @raise [ArgumentError] When role is not supported
    # @example
    #   validate_role('user') # => 'user'
    #   validate_role(:assistant) # => 'assistant'
    # @since 1.6.0
    def validate_role(role)
      # Convert role to symbol if it's a string
      role_key = role.is_a?(String) ? role.to_sym : role

      # Use fetch with a block for better error handling
      ROLES.fetch(role_key) do
        raise ArgumentError, "Invalid role: #{role}. Must be one of: #{ROLES.keys.join(', ')}"
      end
    end

    # Validate that content has the correct structure and required fields
    #
    # @param content [Hash] The content object to validate
    # @return [Hash] The validated content (same as input if valid)
    # @raise [ArgumentError] When content structure or data is invalid
    # @example Valid text content
    #   validate_content({ type: 'text', text: 'Hello' })
    # @example Valid image content
    #   validate_content({ type: 'image', data: 'base64...', mimeType: 'image/png' })
    # @since 1.6.0
    def validate_content(content)
      unless content.is_a?(Hash) && content[:type]
        raise ArgumentError, "Invalid content: #{content}. Must be a hash with a :type key"
      end

      case content[:type]
      when CONTENT_TYPE_TEXT
        raise ArgumentError, 'Missing :text in text content' unless content[:text]
      when CONTENT_TYPE_IMAGE
        raise ArgumentError, 'Missing :data in image content' unless content[:data]
        raise ArgumentError, 'Missing :mimeType in image content' unless content[:mimeType]

        # Validate that data is a string
        unless content[:data].is_a?(String)
          raise ArgumentError, 'Image :data must be a string containing base64-encoded data'
        end

        # Validate that data is valid base64
        begin
          # Try to decode the base64 data
          Base64.strict_decode64(content[:data])
        rescue ArgumentError
          raise ArgumentError, 'Image :data must be valid base64-encoded data'
        end
      when CONTENT_TYPE_RESOURCE
        validate_resource_content(content[:resource])
      else
        raise ArgumentError, "Invalid content type: #{content[:type]}"
      end
    end

    # Validate resource content structure and required fields
    #
    # @param resource [Hash] The resource object to validate
    # @return [Hash] The validated resource (same as input if valid)
    # @raise [ArgumentError] When resource structure is invalid or required fields are missing
    # @example Valid resource
    #   validate_resource_content({
    #     uri: 'file://readme.txt',
    #     mimeType: 'text/plain',
    #     text: 'Hello world'
    #   })
    # @since 1.6.0
    def validate_resource_content(resource)
      raise ArgumentError, 'Missing :resource in resource content' unless resource
      raise ArgumentError, 'Missing :uri in resource content' unless resource[:uri]
      raise ArgumentError, 'Missing :mimeType in resource content' unless resource[:mimeType]
      raise ArgumentError, 'Resource must have either :text or :blob' unless resource[:text] || resource[:blob]
    end
  end
end
