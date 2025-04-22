# frozen_string_literal: true

module FastMcp
  module AutoDerive
    class AutoDeriveAdapter < FastMcp::Tool
      def self.method_name
        raise NotImplementedError, 'Subclasses must define method_name'
      end

      def self.class_name
        raise NotImplementedError, 'Subclasses must define class_name'
      end

      def self.description
        raise NotImplementedError, 'Subclasses must define description'
      end

      def self.parameters
        {}
      end

      def self.read_only?
        true
      end

      def self.finder_key
        :id
      end

      def self.post_process(result, _params)
        result
      end

      def call(params)
        raise NotImplementedError, 'Subclasses must implement the call method'
      end

      def self.create_subclass(name:, class_name:, method_name:, description:, parameters: {}, read_only: true, finder_key: :id, post_process: nil)
        Class.new(self) do
          define_singleton_method(:name) { name }
          define_singleton_method(:tool_name) { name }
          define_singleton_method(:class_name) { class_name }
          define_singleton_method(:method_name) { method_name }
          define_singleton_method(:description) { description }
          define_singleton_method(:parameters) { parameters }
          define_singleton_method(:read_only?) { read_only }
          define_singleton_method(:finder_key) { finder_key }

          arguments do
            if finder_key && !parameters.key?(finder_key.to_sym) && !parameters.key?(finder_key.to_s)
              required(finder_key).filled(:string, format?: /\A[0-9]+\z/)
            end

            parameters.each do |param_name, param_details|
              param_type = (param_details[:type] || :string).to_sym
              required = param_details[:required] != false # Default to required unless explicitly optional

              if required
                required(param_name).filled(param_type)
              else
                optional(param_name).value(param_type)
              end
            end
          end

          if post_process
            define_singleton_method(:post_process) do |result, params|
              post_process.call(result, params)
            end
          end
        end
      end
    end
  end
end
