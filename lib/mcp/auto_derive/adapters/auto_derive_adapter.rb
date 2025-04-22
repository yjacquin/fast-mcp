# frozen_string_literal: true

module FastMcp
  module AutoDerive
    class AutoDeriveAdapter < FastMcp::AutoDerive::BaseAdapter
      def self.derive_active_record_tools(options: {})
        tools = []
        random_tool = FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::RandomActiveRecordAdapter.create_tool
        tools << random_tool

        find_tool = FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::FindActiveRecordAdapter.create_tool
        tools << find_tool

        where_tool = FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::WhereActiveRecordAdapter.create_tool
        tools << where_tool
        return tools if options[:read_only_mode]

        create_tool = FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::CreateActiveRecordAdapter.create_tool
        tools << create_tool

        update_tool = FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::UpdateActiveRecordAdapter.create_tool
        tools << update_tool

        destroy_tool = FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::DestroyActiveRecordAdapter.create_tool
        tools << destroy_tool

        tools
      rescue StandardError => e
        puts "Error deriving ActiveRecord tools: #{e.message}"
        puts e.backtrace.join("\n")
        []
      end
    end
  end
end
