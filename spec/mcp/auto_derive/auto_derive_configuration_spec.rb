# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/auto_derive_configuration'

RSpec.describe FastMcp::AutoDerive::Configuration do
  subject(:configuration) { described_class.new }

  describe '#initialize' do
    it 'sets default values' do
      expect(configuration).to have_attributes(
        enabled_in_web: true,
        enabled_in_console: false,
        enabled_in_sidekiq: false,
        enabled_in_test: false,
        auto_derive_active_record_methods: [:find, :limit, :sample],
        read_only_mode: false,
        autoregister: true
      )
    end
  end

  describe 'configuration attributes' do
    %i[enabled_in_web enabled_in_console enabled_in_sidekiq enabled_in_test
       read_only_mode autoregister].each do |attr|
      it "allows modification of #{attr}" do
        configuration.public_send("#{attr}=", true)
        expect(configuration.public_send(attr)).to be(true)
      end
    end

    it 'allows modification of auto_derive_active_record_methods' do
      new_methods = [:where, :all]
      configuration.auto_derive_active_record_methods = new_methods
      expect(configuration.auto_derive_active_record_methods).to eq(new_methods)
    end
  end
end
