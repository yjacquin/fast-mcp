# frozen_string_literal: true

module FastMcp
  module AutoDerive
    # AutoInclude class for injecting functionality into Rails e.g. expose_action_to_mcp
    class AutoInclude
      def self.initialize
        ActiveSupport.on_load(:active_record) do
          include FastMcp::AutoDerive
        end

        # Include ControllerAutoDeriveModule in ApplicationController
        return unless defined?(ApplicationController)

        ApplicationController.include(FastMcp::AutoDerive::ControllerAutoDeriveModule)
      end
    end
  end
end
