# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      class ControllerMethodAdapter < FastMcp::AutoDerive::AutoDeriveAdapter
        def self.derive_controller_action(controller, metadata)
          param_definitions = define_parameters(metadata)

          create_subclass(**subclass_params(controller, metadata, param_definitions)).tap do |klass|
            klass.define_singleton_method(:controller_class) { controller }
            klass.define_singleton_method(:metadata) { metadata }
            klass.define_singleton_method(:action_name) { metadata[:action_name] }

            klass.define_method(:call) do |**params|
              handle_errors do
                controller_class = self.class.controller_class
                action_name = self.class.action_name

                controller = if controller_class.is_a?(Class)
                               controller_class.new
                             else
                               controller_class.class.new
                             end

                setup_minimal_context(controller, params)

                controller.send(action_name)

                serialize_result(controller.response)
              end
            end
          end
        end

        def self.define_parameters(metadata)
          param_definitions = {}

          if metadata[:parameters].present?
            metadata[:parameters].each do |param_name, param_details|
              param_details = param_details.is_a?(Hash) ? param_details.dup : { description: param_details.to_s }

              param_details[:type] ||= :string
              param_details[:description] ||= "#{param_name} parameter"
              param_details[:required] = param_details[:optional] != true

              param_definitions[param_name.to_sym] = param_details
            end
          end

          param_definitions
        end

        def self.subclass_params(controller, metadata, param_definitions)
          annotations = metadata[:annotations] || begin
            {
              readOnlyHint: false,
              destructiveHint: false,
              idempotentHint: false,
              openWorldHint: false
            }
          end

          {
            name: metadata[:tool_name] || "#{controller.name.underscore.gsub('_controller',
                                                                             '')}_#{metadata[:action_name]}",
            class_name: controller.name,
            method_name: metadata[:action_name],
            description: metadata[:description],
            parameters: param_definitions,
            finder_key: nil,
            title: metadata[:title],
            annotations: annotations
          }
        end

        private

        def setup_minimal_context(controller, params)
          params_hash = params.transform_keys(&:to_s)

          env = {
            'rack.input' => StringIO.new,
            'action_dispatch.request.request_parameters' => params_hash
          }

          request = ActionDispatch::Request.new(env)
          response = ActionDispatch::Response.new

          controller.request = request
          controller.response = response
          controller.params = ActionController::Parameters.new(params_hash)
        end

        def serialize_result(response)
          if response.content_type == 'application/json'
            begin
              JSON.parse(response.body)
            rescue StandardError
              response.body
            end
          else
            response.body
          end
        end
      end
    end
  end
end
