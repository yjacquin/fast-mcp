# frozen_string_literal: true

require 'dry-schema'
require_relative 'json_schema_compiler'

module FastMcp
  # Main Tool class that represents an MCP Tool
  class Tool
    class InvalidArgumentsError < StandardError; end

    class << self
      attr_accessor :server

      # Add tagging support for tools
      def tags(*tag_list)
        if tag_list.empty?
          @tags || []
        else
          @tags = tag_list.flatten.map(&:to_sym)
        end
      end

      # Add metadata support for tools
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

      def arguments(&block)
        @input_schema = Dry::Schema.JSON(&block)
      end

      def input_schema
        @input_schema ||= Dry::Schema.JSON
      end

      def tool_name(name = nil)
        name = @name || self.name if name.nil?
        return if name.nil?

        name = name.gsub(/[^a-zA-Z0-9_-]/, '')[0, 64]

        @name = name
      end

      def description(description = nil)
        return @description if description.nil?

        @description = description
      end

      def annotations(annotations_hash = nil)
        return @annotations || {} if annotations_hash.nil?

        @annotations = annotations_hash
      end

      def authorize(&block)
        @authorization_blocks ||= []
        @authorization_blocks.push block
      end

      def call(**args)
        raise NotImplementedError, 'Subclasses must implement the call method'
      end

      def input_schema_to_json
        return nil unless @input_schema

        JSONSchemaCompiler.process(@input_schema)
      end
    end

    def initialize(headers: {})
      @_meta = {}
      @headers = headers
    end

    def authorized?(**args)
      auth_checks = self.class.ancestors.filter_map do |ancestor|
        ancestor.ancestors.include?(FastMcp::Tool) &&
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

    attr_accessor :_meta
    attr_reader :headers

    def notify_resource_updated(uri)
      self.class.server.notify_resource_updated(uri)
    end

    def call_with_schema_validation!(**args)
      arg_validation = self.class.input_schema.call(args)
      raise InvalidArgumentsError, arg_validation.errors.to_h.to_json if arg_validation.errors.any?

      # When calling the tool, its metadata can be altered to be returned in response.
      # We return the altered metadata with the tool's result
      [call(**args), _meta]
    end
  end
end

# Example
# class ExampleTool < FastMcp::Tool
#   description 'An example tool'

#   arguments do
#     required(:name).filled(:string)
#     required(:age).filled(:integer, gt?: 18)
#     required(:email).filled(:string)
#     optional(:metadata).hash do
#       required(:address).filled(:string)
#       required(:phone).filled(:string)
#     end
#   end

#   def call(name:, age:, email:, metadata: nil)
#     puts "Hello, #{name}! You are #{age} years old. Your email is #{email}."
#     puts "Your metadata is #{metadata.inspect}." if metadata
#   end
# end
