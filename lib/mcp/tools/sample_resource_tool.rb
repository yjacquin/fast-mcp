# frozen_string_literal: true

module FastMcp
  module Tools
    # SampleResourceTool provides a tool to retrieve content from any registered resource
    class SampleResourceTool < FastMcp::Tool
      tool_name 'resource_content'
      description 'Get content from a resource'

      arguments do
        required(:resource_uri).filled(:string).description('The URI of the resource to fetch')
        optional(:record_id).maybe(:string).description('Record ID if accessing an instance resource')
        optional(:params).maybe(:hash).description('Parameters to pass to the resource')
      end

      def call(resource_uri:, record_id: nil, params: {})
        # Find the resource class by URI
        resource_class = find_resource_class(resource_uri)
        return { error: "Resource not found: #{resource_uri}" } unless resource_class

        # Get the resource instance with parameters
        resource = if resource_class.respond_to?(:instance)
                     # For auto-derived resources that support parameters
                     resource_class.instance(record_id, params.transform_keys(&:to_sym))
                   else
                     # For standard singleton resources
                     resource_class.instance
                   end

        # Return the resource contents
        resource.contents
      rescue StandardError => e
        { error: 'Error fetching resource content', details: e.message }
      end

      private

      def find_resource_class(uri)
        FastMcp::Resource.descendants.find { |klass| klass.uri == uri }
      end
    end
  end
end
