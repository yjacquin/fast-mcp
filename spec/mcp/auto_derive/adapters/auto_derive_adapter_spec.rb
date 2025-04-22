# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/adapters/auto_derive_adapter'

module FastMcp
  module AutoDerive
    module Adapters
      module ActiveRecordAdapters
        class FindActiveRecordAdapter; end
        class WhereActiveRecordAdapter; end
        class CreateActiveRecordAdapter; end
        class UpdateActiveRecordAdapter; end
        class DestroyActiveRecordAdapter; end
        class RandomActiveRecordAdapter; end
      end
    end
  end
end

RSpec.describe FastMcp::AutoDerive::AutoDeriveAdapter do
  describe '.derive_active_record_tools' do
    let(:random_adapter) { double('RandomActiveRecordAdapter') }
    let(:find_adapter) { double('FindActiveRecordAdapter') }
    let(:where_adapter) { double('WhereActiveRecordAdapter') }
    let(:create_adapter) { double('CreateActiveRecordAdapter') }
    let(:update_adapter) { double('UpdateActiveRecordAdapter') }
    let(:destroy_adapter) { double('DestroyActiveRecordAdapter') }

    before do
      allow(FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::RandomActiveRecordAdapter)
        .to receive(:create_tool).and_return(random_adapter)

      allow(FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::FindActiveRecordAdapter)
        .to receive(:create_tool).and_return(find_adapter)

      allow(FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::WhereActiveRecordAdapter)
        .to receive(:create_tool).and_return(where_adapter)

      allow(FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::CreateActiveRecordAdapter)
        .to receive(:create_tool).and_return(create_adapter)

      allow(FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::UpdateActiveRecordAdapter)
        .to receive(:create_tool).and_return(update_adapter)

      allow(FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::DestroyActiveRecordAdapter)
        .to receive(:create_tool).and_return(destroy_adapter)
    end

    context 'when read_only_mode is false' do
      it 'returns all tools' do
        tools = described_class.derive_active_record_tools
        expect(tools).to eq([
          random_adapter,
          find_adapter,
          where_adapter,
          create_adapter,
          update_adapter,
          destroy_adapter
        ])
      end
    end

    context 'when read_only_mode is true' do
      it 'returns only read-only tools' do
        tools = described_class.derive_active_record_tools(options: { read_only_mode: true })
        expect(tools).to eq([random_adapter, find_adapter, where_adapter])
      end
    end

    context 'when an error occurs' do
      before do
        allow(FastMcp::AutoDerive::Adapters::ActiveRecordAdapters::FindActiveRecordAdapter)
          .to receive(:create_tool).and_raise(StandardError, 'Test error')
      end

      it 'rescues the error and returns an empty array' do
        expect(described_class.derive_active_record_tools).to eq([])
      end
    end
  end
end
