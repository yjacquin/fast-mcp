# frozen_string_literal: true

module FastMcp
  module AutoDerive
    extend ActiveSupport::Concern

    included do
      class_attribute :mcp_exposed_methods, default: {}
    end

    def self.configuration
      @configuration ||= Configuration.new
    end

    def self.configure
      yield(configuration) if block_given?
    end

    class_methods do
      # Expose a method to the Model Context Protocol
      #
      # @param method_name [Symbol] The name of the method to expose
      # @param description [String] Description of what the method does
      # @param parameters [Hash] Description of parameters (optional)
      # @param read_only [Boolean] Whether this method modifies data (default: true)
      # @param finder_key [Symbol] The attribute to use for finding records (default: :id)
      # @param tool_name [String] Custom name for the tool (optional)
      def expose_to_mcp(method_name, description:, parameters: {}, read_only: true, finder_key: :id, tool_name: nil)
        tool_name ||= "#{name.underscore}_#{method_name}"

        self.mcp_exposed_methods = mcp_exposed_methods.merge(
          tool_name => {
            method_name: method_name,
            description: description,
            parameters: parameters,
            read_only: read_only,
            finder_key: finder_key,
            class_name: name
          }
        )
      end
    end
  end
end
