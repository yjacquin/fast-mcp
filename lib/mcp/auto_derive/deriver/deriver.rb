# frozen_string_literal: true

# require_relative '../adapters/model_method_adapter'
# require_relative '../adapters/controller_method_adapter'
# require_relative '../controller_auto_derive'
# require_relative '../auto_derive'
# require_relative '../auto_derive_configuration'
# require_relative 'derive_methods'
# require_relative '../adapters/auto_derive_adapter'

module FastMcp
  module AutoDerive
    # required namespace for tools
    module Tools
    end

    class Deriver
      def self.derive_tools(options: {})
        unless tools_enabled_in_current_environment?
          puts "Skipping tool generation in #{current_environment} environment"
          return []
        end
        tools = []

        begin
          ensure_auto_derive_modules_included

          Rails.application.eager_load!

          tools.concat(generate_model_tools(options: options))

          tools.concat(generate_controller_tools)
        rescue StandardError => e
          puts "Error in generate_tools: #{e.message}"
          puts e.backtrace.join("\n")
        end
        tools
      end

      def self.current_environment
        return :sidekiq if running_in_sidekiq?
        return :console if running_in_console?
        return :test if running_in_test?

        :web
      end

      def self.tools_enabled_in_current_environment?
        return true if ENV['FORCE_AUTO_DERIVE'] == 'true'
        return false if ENV['DISABLE_AUTO_DERIVE'] == 'true'

        config = FastMcp::AutoDerive.configuration
        case current_environment
        when :sidekiq
          config.enabled_in_sidekiq
        when :console
          config.enabled_in_console
        when :test
          config.enabled_in_test
        when :web
          config.enabled_in_web
        else
          true
        end
      end

      def self.running_in_sidekiq?
        return true if $PROGRAM_NAME.include?('sidekiq')

        return true if defined?(Sidekiq) &&
                       (defined?(Sidekiq::CLI) ||
                        defined?(Sidekiq::Worker) &&
                        caller.any? { |c| c.include?('/sidekiq/') })

        return true if ENV['SIDEKIQ_WORKER'] == 'true'

        return true if defined?(Rails) && Rails.env.respond_to?(:sidekiq?) && Rails.env.sidekiq?

        false
      end

      def self.running_in_console?
        return true if defined?(Rails::Console)
        return true if $PROGRAM_NAME.include?('console')
        return true if caller.any? { |c| c.include?('irb') || c.include?('console') }

        false
      end

      def self.running_in_test?
        return true if defined?(Rails) && Rails.env.test?
        return true if ENV['RAILS_ENV'] == 'test'
        return true if ENV['RACK_ENV'] == 'test'

        false
      end

      def self.ensure_auto_derive_modules_included
        unless ActiveRecord::Base.included_modules.include?(FastMcp::AutoDerive)
          ActiveRecord::Base.include(FastMcp::AutoDerive)
        end

        if defined?(FastMcp::AutoDerive::ControllerAutoDeriveModule) && defined?(ActionController::Base) && !ActionController::Base.included_modules.include?(FastMcp::AutoDerive::ControllerAutoDeriveModule)
          ActionController::Base.include(FastMcp::AutoDerive::ControllerAutoDeriveModule)
        end
      rescue StandardError => e
        puts "Error including AutoDerive modules: #{e.message}"
        puts e.backtrace.join("\n")
      end

      def self.generate_model_tools(options: {})
        tools = []

        unified_ar_tools = FastMcp::AutoDerive::AutoDeriveAdapter.derive_active_record_tools(options: options)
        tools.concat(unified_ar_tools)

        ActiveRecord::Base.descendants.each do |model|
          next if model.abstract_class?
          next if options[:exclusions][:models].include?(model.name)
          next if options[:exclusions][:namespaces].include?(model.name.split('::').first)

          has_exposed_methods = model.respond_to?(:mcp_exposed_methods) && !model.mcp_exposed_methods.empty?

          if has_exposed_methods
            model.mcp_exposed_methods.each do |tool_name, metadata|
              tools << derive_model_method(model, tool_name, metadata)
            end
          end
        rescue StandardError => e
          puts "Error processing model #{model.name}: #{e.message}"
          puts e.backtrace.join("\n")
        end

        tools
      end

      def self.generate_controller_tools
        tools = []

        controllers = ApplicationController.descendants

        controllers.each do |controller|
          has_exposed_actions = controller.respond_to?(:mcp_exposed_actions) && !controller.mcp_exposed_actions.empty?

          if has_exposed_actions
            controller.mcp_exposed_actions.each do |tool_name, metadata|
              tools << derive_controller_action(controller, tool_name, metadata)
            end
          end
        rescue StandardError => e
          puts "Error processing controller #{controller.name}: #{e.message}"
          puts e.backtrace.join("\n")
        end

        tools
      end
    end
  end
end
