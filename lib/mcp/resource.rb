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

      # Define URI for this resource
      # @param value [String, nil] The URI for this resource
      # @return [String] The URI for this resource
      def uri(value = nil)
        @uri = value if value
        @uri || (superclass.respond_to?(:uri) ? superclass.uri : nil)
      end

      # Define name for this resource
      # @param value [String, nil] The name for this resource
      # @return [String] The name for this resource
      def resource_name(value = nil)
        @name = value if value
        @name || (superclass.respond_to?(:resource_name) ? superclass.resource_name : nil)
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
        {
          uri: uri,
          name: resource_name,
          description: description,
          mimeType: mime_type
        }.compact
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

    # URI of the resource - delegates to class method
    # @return [String, nil] The URI for this resource
    def uri
      self.class.uri
    end

    # Name of the resource - delegates to class method
    # @return [String, nil] The name for this resource
    def name
      self.class.name
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
