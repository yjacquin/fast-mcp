# frozen_string_literal: true

require 'dry-schema'

Dry::Schema.load_extensions(:json_schema)

# Extend Dry::Schema macros to support description
module Dry
  module Schema
    module Macros
      # Add description method to Value macro
      class Value
        def description(text)
          key_name = name.to_sym
          schema_dsl.meta(key_name, :description, text)

          self
        end

        def hidden(hidden = true) # rubocop:disable Style/OptionalBooleanParameter
          key_name = name.to_sym
          schema_dsl.meta(key_name, :hidden, hidden)

          self
        end
      end

      # Add description method to Required macro
      class Required
        def description(text)
          key_name = name.to_sym
          schema_dsl.meta(key_name, :description, text)

          self
        end

        def hidden(hidden = true) # rubocop:disable Style/OptionalBooleanParameter
          key_name = name.to_sym
          schema_dsl.meta(key_name, :hidden, hidden)

          self
        end
      end

      # Add description method to Optional macro
      class Optional
        def description(text)
          key_name = name.to_sym
          schema_dsl.meta(key_name, :description, text)

          self
        end

        def hidden(hidden = true) # rubocop:disable Style/OptionalBooleanParameter
          key_name = name.to_sym
          schema_dsl.meta(key_name, :hidden, hidden)

          self
        end
      end

      # Add description method to Hash macro
      class Hash
        def description(text)
          key_name = name.to_sym
          schema_dsl.meta(key_name, :description, text)

          # Mark this hash as having metadata so we know to track nested context
          @has_metadata = true
          self
        end

        def hidden(hidden = true) # rubocop:disable Style/OptionalBooleanParameter
          key_name = name.to_sym
          schema_dsl.meta(key_name, :hidden, hidden)

          # Mark this hash as having metadata so we know to track nested context
          @has_metadata = true
          self
        end

        # Override call method to manage nested context
        alias original_call call

        def call(&block)
          if block
            # Use current context to track nested context if available
            context = MetadataContext.current
            if context
              context.with_nested(name) do
                original_call(&block)
              end
            else
              original_call(&block)
            end
          else
            original_call(&block)
          end
        end
      end
    end
  end
end

# Context object for managing nested metadata collection
class MetadataContext
  def initialize
    @metadata = {}
    @nesting_stack = []
  end

  attr_reader :metadata

  def store(property_name, meta_key, value)
    path = current_path + [property_name.to_s]
    full_path = path.join('.')

    @metadata[full_path] ||= {}
    @metadata[full_path][meta_key] = value
  end

  def with_nested(parent_property)
    @nesting_stack.push(parent_property.to_s)
    yield
  ensure
    @nesting_stack.pop
  end

  def current_path
    @nesting_stack.dup
  end

  # Class method to set/get current context for thread-safe access
  def self.current
    Thread.current[:metadata_context]
  end

  def self.with_context(context)
    old_context = Thread.current[:metadata_context]
    Thread.current[:metadata_context] = context
    yield
  ensure
    Thread.current[:metadata_context] = old_context
  end
end

# Extend Dry::Schema DSL to store metadata
module Dry
  module Schema
    class DSL
      def meta(key_name, meta_key, value)
        @meta ||= {}
        @meta[key_name] ||= {}
        @meta[key_name][meta_key] = value

        # Store in current context if available
        context = MetadataContext.current
        return unless context

        context.store(key_name, meta_key, value)
      end

      def meta_data
        @meta || {}
      end
    end
  end
end

# Schema metadata processor for handling custom predicates in JSON schema output
class SchemaMetadataProcessor
  def self.process(schema, collected_metadata = {})
    return nil unless schema

    base_schema = schema.json_schema.tap { _1.delete(:$schema) }
    metadata = extract_metadata(schema)

    # Merge traditional metadata with collected nested metadata
    all_metadata = merge_metadata(metadata, collected_metadata)

    apply_metadata_to_schema(base_schema, all_metadata)
  end

  private_class_method def self.extract_metadata(schema)
    schema_dsl = schema.instance_variable_get(:@schema_dsl)
    schema_dsl&.meta_data || {}
  end

  private_class_method def self.merge_metadata(traditional, collected)
    # Remove internal keys from collected metadata
    filtered_collected = collected.reject { |key, _| key.to_s.start_with?('_') }

    # Start with traditional metadata
    merged = traditional.dup

    # Add collected metadata with full paths
    filtered_collected.each do |path, metadata|
      merged[path] = metadata
    end

    merged
  end

  private_class_method def self.apply_metadata_to_schema(base_schema, metadata)
    return base_schema if !base_schema[:properties] || metadata.empty?

    base_schema[:properties] = process_properties_recursively(base_schema[:properties], metadata, [])
    base_schema[:required] = filter_required_properties(base_schema[:required], base_schema[:properties])
    base_schema
  end

  private_class_method def self.process_properties_recursively(properties, metadata, path_prefix = [])
    filtered_properties = {}

    properties.each do |property_name, property_schema|
      current_path = (path_prefix + [property_name.to_s]).join('.')

      # Look for metadata using both simple key and full path
      property_key = property_name.to_sym
      property_metadata = metadata[property_key] || metadata[current_path]

      # Skip hidden properties entirely
      next if property_metadata&.dig(:hidden)

      # Add description if present
      property_schema[:description] = property_metadata[:description] if property_metadata&.dig(:description)

      # Recursively process nested object properties
      if property_schema[:type] == 'object' && property_schema[:properties]
        nested_path = path_prefix + [property_name.to_s]
        property_schema[:properties] =
          process_properties_recursively(property_schema[:properties], metadata, nested_path)
        property_schema[:required] =
          filter_required_properties(property_schema[:required], property_schema[:properties])
      # Recursively process array items with object properties
      elsif property_schema[:type] == 'array' && !property_schema.key?(:items)
        property_schema[:items] = {}
      elsif property_schema[:type] == 'array' && property_schema.dig(:items, :type) == 'object' &&
            property_schema.dig(:items, :properties)
        nested_path = path_prefix + [property_name.to_s]
        property_schema[:items][:properties] =
          process_properties_recursively(property_schema[:items][:properties], metadata, nested_path)
        property_schema[:items][:required] =
          filter_required_properties(property_schema[:items][:required], property_schema[:items][:properties])
      end

      filtered_properties[property_name] = property_schema
    end

    filtered_properties
  end

  private_class_method def self.filter_required_properties(required_array, properties)
    return [] unless required_array

    required_array.select do |required_prop|
      properties.key?(required_prop.to_sym) || properties.key?(required_prop.to_s)
    end
  end
end

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
        @metadata_context = MetadataContext.new

        @input_schema = MetadataContext.with_context(@metadata_context) do
          Dry::Schema.JSON(&block)
        end

        @collected_metadata = @metadata_context.metadata
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
        SchemaMetadataProcessor.process(@input_schema, @collected_metadata || {})
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
