# frozen_string_literal: true

module MCP
  # Prompt class for MCP prompt templates
  class Prompt
    attr_reader :name, :description, :arguments

    # Initialize a new Prompt
    # @param name [String] The unique identifier for the prompt
    # @param description [String] Optional human-readable description
    # @param messages [Array<Hash>] The messages content of the prompt
    # @param arguments [Array<Hash>] Optional arguments for customization
    def initialize(name:, description: nil, messages: [], arguments: [])
      @name = name
      @description = description || ""
      @messages = messages
      @arguments = arguments || []
    end

    # Returns a hash representation of the prompt for listing
    # @return [Hash] The prompt definition hash
    def to_list_hash
      {
        name: @name,
        description: @description,
        arguments: @arguments.map do |arg|
          {
            name: arg[:name],
            description: arg[:description] || "",
            required: arg[:required] || false
          }
        end
      }
    end

    # Return the full prompt content with arguments applied
    # @param arguments [Hash] Arguments to populate in the prompt
    # @return [Hash] The complete prompt content
    def get_content(arguments = {})
      result = {
        description: @description,
        messages: @messages.map do |message|
          process_message(message, arguments)
        end
      }

      result
    end

    private

    # Process a single message, filling placeholders with argument values
    # @param message [Hash] The original message
    # @param arguments [Hash] Arguments to populate
    # @return [Hash] The processed message
    def process_message(message, arguments)
      processed = message.dup
      
      if processed[:content].is_a?(Hash) && processed[:content][:type] == "text"
        # For text content, replace placeholders
        processed[:content][:text] = interpolate_text(processed[:content][:text], arguments)
      end
      
      processed
    end

    # Replace placeholders in text with argument values
    # @param text [String] The original text
    # @param arguments [Hash] Arguments to populate
    # @return [String] The interpolated text
    def interpolate_text(text, arguments)
      result = text.dup
      
      arguments.each do |key, value|
        placeholder = "{{#{key}}}"
        # Handle newlines properly - don't convert to literal '\n'
        value_str = value.to_s
        if result.include?(placeholder)
          result = result.gsub(placeholder, value_str)
        end
      end
      
      result
    end
  end
end