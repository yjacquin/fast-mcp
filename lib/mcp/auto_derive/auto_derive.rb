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
      # @param title [String] Human-readable title for the tool (optional)
      # @param destructive [Boolean] If true, the tool performs destructive updates (default: !read_only)
      # @param idempotent [Boolean] If true, calling repeatedly with same args has same effect (default: false)
      # @param open_world [Boolean] If true, the tool interacts with external systems (default: true)
      def expose_to_mcp(method_name, description:, parameters: {}, read_only: true, finder_key: :id, tool_name: nil,
                        title: nil, destructive: nil, idempotent: false, open_world: true)
        if tool_name.nil?
          safe_method_name = method_name.to_s
                                        .gsub(/\?$/, '_is')
                                        .gsub(/!$/, '_bang')
                                        .gsub(/=$/, '_equals')
                                        .gsub(/[^a-zA-Z0-9_]/, '')

          class_name = respond_to?(:underscore) ? underscore : name.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
          tool_name = "#{class_name}_#{safe_method_name}"
        end

        self.mcp_exposed_methods = mcp_exposed_methods.merge(
          tool_name => {
            method_name: method_name,
            description: description,
            parameters: parameters,
            read_only: read_only,
            finder_key: finder_key,
            class_name: name,
            title: title,
            destructive: destructive,
            idempotent: idempotent,
            open_world: open_world
          }
        )
      end
    end
  end
end
