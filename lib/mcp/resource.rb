# frozen_string_literal: true

require 'json'
require 'base64'
require 'mime/types'
require 'singleton'

module FastMcp
  # Resource class for MCP Resources feature
  # Represents a resource that can be exposed to clients
  class Resource
    class << self
      attr_accessor :server
      attr_reader :template_params

      # Define URI for this resource
      # @param value [String, nil] The URI for this resource
      # @return [String] The URI for this resource
      def uri(value = nil)
        if value
          @uri = value
          # Check if URI contains template parameters
          if value.include?('{') && value.include?('}')
            @is_template = true
            @template_params = value.scan(/\{([^\}]+)\}/).flatten

            # Generate a regex pattern for matching this URI
            escaped_uri = Regexp.escape(value)

            @template_params.each do |param|
              escaped_param = Regexp.escape("{#{param}}")
              escaped_uri = escaped_uri.sub(escaped_param, '([^/]+)')
            end

            @uri_pattern = Regexp.new("^#{escaped_uri}$")
          else
            @is_template = false
            @template_params = nil
            @uri_pattern = nil
          end
        end
        @uri || (superclass.respond_to?(:uri) ? superclass.uri : nil)
      end

      # Check if this resource has a templated URI
      # @return [Boolean] true if the URI contains template parameters
      def templated?
        @is_template || false
      end

      # Get the regex pattern for matching this URI
      # @return [Regexp, nil] The pattern for matching this URI
      def uri_pattern
        @uri_pattern || (superclass.respond_to?(:uri_pattern) && superclass.templated? ? superclass.uri_pattern : nil)
      end

      # Create a new instance with the given params
      # @param params [Hash] The parameters for this resource instance
      # @return [Resource] A new resource instance
      def with_params(params)
        resource_class = Class.new(self)
        resource_class.instance_variable_set(:@params, params)

        resource_class.define_singleton_method(:instance) do
          @instance ||= begin
            instance = new
            instance.instance_variable_set(:@params, params)
            instance
          end
        end

        resource_class
      end

      # Get the parameters for this resource instance
      # @return [Hash] The parameters for this resource instance
      def params
        @params || {}
      end

      # Define name for this resource
      # @param value [String, nil] The name for this resource
      # @return [String] The name for this resource
      def resource_name(value = nil)
        @name = value if value
        @name || (superclass.respond_to?(:resource_name) ? superclass.resource_name : nil)
      end

      alias original_name name
      def name
        return resource_name if resource_name

        original_name
      end

      # Define description for this resource
      # @param value [String, nil] The description for this resource
      # @return [String] The description for this resource
      def description(value = nil)
        @description = value if value
        @description || (superclass.respond_to?(:description) ? superclass.description : nil)
      end

      # Define MIME type for this resource
      # @param value [String, nil] The MIME type for this resource
      # @return [String] The MIME type for this resource
      def mime_type(value = nil)
        @mime_type = value if value
        @mime_type || (superclass.respond_to?(:mime_type) ? superclass.mime_type : nil)
      end

      # Get the resource metadata (without content)
      # @return [Hash] Resource metadata
      def metadata
        if templated?
          {
            uriTemplate: uri,
            name: resource_name,
            description: description,
            mimeType: mime_type
          }.compact
        else
          {
            uri: uri,
            name: resource_name,
            description: description,
            mimeType: mime_type
          }.compact
        end
      end

      # Load content from a file (class method)
      # @param file_path [String] Path to the file
      # @return [Resource] New resource instance with content loaded from file
      def from_file(file_path, name: nil, description: nil)
        file_uri = "file://#{File.absolute_path(file_path)}"
        file_name = name || File.basename(file_path)

        # Create a resource subclass on the fly
        Class.new(self) do
          uri file_uri
          resource_name file_name
          description description if description

          # Auto-detect mime type
          extension = File.extname(file_path)
          unless extension.empty?
            detected_types = MIME::Types.type_for(extension)
            mime_type detected_types.first.to_s unless detected_types.empty?
          end

          # Override content method to load from file
          define_method :content do
            if binary?
              File.binread(file_path)
            else
              File.read(file_path)
            end
          end
        end
      end
    end

    include Singleton

    # Initialize with instance variables
    def initialize
      @params = {}
    end

    # URI of the resource - delegates to class method
    # @return [String, nil] The URI for this resource
    def uri
      self.class.uri
    end

    # Name of the resource - delegates to class method
    # @return [String, nil] The name for this resource
    def name
      self.class.resource_name
    end

    # Description of the resource - delegates to class method
    # @return [String, nil] The description for this resource
    def description
      self.class.description
    end

    # MIME type of the resource - delegates to class method
    # @return [String, nil] The MIME type for this resource
    def mime_type
      self.class.mime_type
    end

    # Get parameters from the URI template
    # @return [Hash] The parameters extracted from the URI
    def params
      @params || self.class.params
    end

    # Method to be overridden by subclasses to dynamically generate content
    # @return [String, nil] Generated content for this resource
    def content
      raise NotImplementedError, 'Subclasses must implement content'
    end

    # Check if the resource is binary
    # @return [Boolean] true if the resource is binary, false otherwise
    def binary?
      return false if mime_type.nil?

      !(mime_type.start_with?('text/') ||
        mime_type == 'application/json' ||
        mime_type == 'application/xml' ||
        mime_type == 'application/javascript')
    end

    # Get the resource contents
    # @return [Hash] Resource contents
    def contents
      result = {
        uri: uri,
        mimeType: mime_type
      }

      content_value = content
      if content_value
        if binary?
          result[:blob] = Base64.strict_encode64(content_value)
        else
          result[:text] = content_value
        end
      end

      result
    end
  end
end
