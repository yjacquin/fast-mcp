# frozen_string_literal: true

require 'json'
require 'base64'
require 'mime/types'
require 'addressable/template'

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

      # Variabilize the URI with the given params
      # @param params [Hash] The parameters to variabilize the URI with
      # @return [String] The variabilized URI
      def variabilized_uri(params = {})
        addressable_template.partial_expand(params).pattern
      end

      # Get the Addressable::Template for this resource
      # @return [Addressable::Template] The Addressable::Template for this resource
      def addressable_template
        @addressable_template ||= Addressable::Template.new(uri)
      end

      # Get the template variables for this resource
      # @return [Array] The template variables for this resource
      def template_variables
        addressable_template.variables
      end

      # Check if this resource has a templated URI
      # @return [Boolean] true if the URI contains template parameters
      def templated?
        template_variables.any?
      end

      # Check if this resource has a non-templated URI
      # @return [Boolean] true if the URI does not contain template parameters
      def non_templated?
        !templated?
      end

      # Match the given URI against the resource's addressable template
      # @param uri [String] The URI to match
      # @return [Addressable::Template::MatchData, nil] The match data if the URI matches, nil otherwise
      def match(uri)
        addressable_template.match(uri)
      end

      # Initialize a new instance from the given URI
      # @param uri [String] The URI to initialize from
      # @param headers [Hash] The HTTP headers from the request
      # @return [Resource] A new resource instance
      def initialize_from_uri(uri, headers: {})
        new(params_from_uri(uri), headers: headers)
      end

      # Get the parameters from the given URI
      # @param uri [String] The URI to get the parameters from
      # @return [Hash] The parameters from the URI
      def params_from_uri(uri)
        match(uri).mapping.transform_keys(&:to_sym)
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

      # Add authorization block for this resource
      # The block will be called to determine if access is allowed
      # @param block [Proc] The authorization logic block
      def authorize(&block)
        @authorization_blocks ||= []
        @authorization_blocks.push block
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

    # Initialize with instance variables
    # @param params [Hash] The parameters for this resource instance
    # @param headers [Hash] The HTTP headers from the request
    def initialize(params = {}, headers: {})
      @params = params
      @headers = headers
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
    attr_reader :params

    # Get headers from the request
    # @return [Hash] The HTTP headers from the request
    attr_reader :headers

    # Check if this resource access is authorized based on authorization blocks
    # @return [Boolean] true if authorized, false otherwise
    def authorized?
      auth_checks = self.class.ancestors.filter_map do |ancestor|
        ancestor.ancestors.include?(FastMcp::Resource) &&
          ancestor.instance_variable_get(:@authorization_blocks)
      end.flatten

      return true if auth_checks.empty?

      auth_checks.all? do |auth_check|
        instance_exec(&auth_check)
      end
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
  end
end
