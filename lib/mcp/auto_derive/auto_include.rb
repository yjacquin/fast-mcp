# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module AutoInclude
      extend ActiveSupport::Concern

      def self.initialize
        ActiveSupport.on_load(:active_record) do
          include FastMcp::AutoDerive
        end

        ActiveSupport.on_load(:action_controller) do
          include FastMcp::AutoDerive::ControllerAutoDeriveModule
        end
      end
    end
  end
end
