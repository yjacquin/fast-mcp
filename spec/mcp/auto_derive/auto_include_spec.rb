# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/auto_include'
require 'mcp/auto_derive/controller_auto_derive'

RSpec.describe FastMcp::AutoDerive::AutoInclude do
  describe '.initialize' do
    context 'when ApplicationController is defined' do
      before do
        @mock_application_controller = class_double('ApplicationController')
        expect(@mock_application_controller).to receive(:include)
          .with(FastMcp::AutoDerive::ControllerAutoDeriveModule)
        stub_const('ApplicationController', @mock_application_controller)

        allow(ActiveSupport).to receive(:on_load)
      end

      it 'includes ControllerAutoDeriveModule in ApplicationController' do
        described_class.initialize
      end
    end

    context 'when ApplicationController is not defined' do
      before do
        allow(ActiveSupport).to receive(:on_load)

        if defined?(ApplicationController)
          @original_application_controller = ApplicationController
          Object.send(:remove_const, :ApplicationController)
        end
      end

      after do
        if instance_variable_defined?(:@original_application_controller)
          ApplicationController = @original_application_controller
        end
      end

      it 'does not try to include the module' do
        expect { described_class.initialize }.not_to raise_error
      end
    end
  end
end
