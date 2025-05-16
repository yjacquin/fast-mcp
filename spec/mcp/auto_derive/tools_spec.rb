# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/tools'

RSpec.describe FastMcp::AutoDerive::Tools do
  it 'exists as a module' do
    expect(described_class).to be_a(Module)
  end

  it 'can have constants defined on it' do
    test_class = Class.new
    FastMcp::AutoDerive::Tools.const_set('TestTool', test_class)

    expect(FastMcp::AutoDerive::Tools::TestTool).to eq(test_class)

    FastMcp::AutoDerive::Tools.send(:remove_const, 'TestTool')
  end
end
