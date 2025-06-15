# frozen_string_literal: true

module FastMcp
  module AutoDerive
    class Configuration
      attr_accessor :enabled_in_web,
                    :enabled_in_console,
                    :enabled_in_sidekiq,
                    :enabled_in_test,
                    :auto_derive_active_record_methods,
                    :read_only_mode,
                    :autoregister

      def initialize
        @enabled_in_web = true
        @enabled_in_console = false
        @enabled_in_sidekiq = false
        @enabled_in_test = false
        @auto_derive_active_record_methods = [:find, :limit, :sample]
        @read_only_mode = false
        @autoregister = true
      end
    end
  end
end
