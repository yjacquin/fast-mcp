# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      class ControllerMethodAdapter < AutoDeriveAdapter
        # Factory method to create controller action-specific adapter classes
        def self.for_action(controller, metadata)
          puts "  Creating ControllerMethodAdapter for controller: #{controller.name}, action: #{metadata[:action_name]}"

          # Get parameter definitions for the Tool class
          param_definitions = {}

          if metadata[:parameters].present?
            metadata[:parameters].each do |param_name, param_details|
              # Ensure param_details is a hash with required keys
              param_details = param_details.is_a?(Hash) ? param_details.dup : { description: param_details.to_s }

              # Set defaults
              param_details[:type] ||= :string
              param_details[:description] ||= "#{param_name} parameter"
              param_details[:required] = !(param_details[:optional] == true)

              param_definitions[param_name.to_sym] = param_details
            end
          end

          # Create a new subclass with the provided configuration
          create_subclass(
            name: metadata[:tool_name] || "#{controller.name.underscore.gsub('_controller',
                                                                             '')}_#{metadata[:action_name]}",
            class_name: controller.name,
            method_name: metadata[:action_name],
            description: metadata[:description],
            parameters: param_definitions,
            read_only: metadata[:read_only] || true,
            finder_key: nil
          ).tap do |klass|
            # Store additional metadata on the class
            klass.define_singleton_method(:controller_class) { controller }
            klass.define_singleton_method(:metadata) { metadata }
            klass.define_singleton_method(:action_name) { metadata[:action_name] }

            # Define the call method that will be used to invoke the controller action
            klass.define_method(:call) do |params|
              controller_class = self.class.controller_class
              action_name = self.class.action_name

              # Create a controller instance
              controller = controller_class.new

              # Set up the controller context
              setup_controller_context(controller, params)

              # Call the action
              result = controller.send(action_name)

              # Extract the response data
              serialize_result(controller.response)
            end
          end
        end

        private

        # Set up the controller with request parameters and environment
        def setup_controller_context(controller, params)
          # Create a mock request with the provided parameters
          params = ActionController::Parameters.new(params)

          # Set up the request and response objects
          request = ActionDispatch::Request.new({
                                                  'rack.input' => StringIO.new,
                                                  'CONTENT_TYPE' => 'application/json',
                                                  'REQUEST_METHOD' => 'GET' # Default to GET, could be overridden
                                                })

          # Set the parameters on the request
          request.parameters.merge!(params)

          # Set up the controller with our request
          controller.request = request
          controller.response = ActionDispatch::Response.new
          controller.params = params
        end

        # Helper method to serialize controller response
        def serialize_result(response)
          # If the response body is JSON, parse it
          if response.content_type == 'application/json'
            begin
              JSON.parse(response.body.first)
            rescue StandardError
              response.body
            end
          else
            # Return the raw response body for other content types
            response.body
          end
        end
      end
    end
  end
end
