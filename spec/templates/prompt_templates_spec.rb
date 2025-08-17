# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'Prompt Generator Templates' do
  let(:template_dir) { File.expand_path('../../lib/generators/fast_mcp/install/templates', __dir__) }
  
  describe 'sample_prompt.rb template' do
    let(:template_path) { File.join(template_dir, 'sample_prompt.rb') }
    let(:template_content) { File.read(template_path) }
    
    it 'exists' do
      expect(File.exist?(template_path)).to be true
    end
    
    it 'has valid Ruby syntax' do
      # Create a test that validates the Ruby syntax
      test_code = <<~RUBY
        class ApplicationPrompt; end
        #{template_content}
      RUBY
      
      # Check syntax with Ruby's parser
      expect { RubyVM::InstructionSequence.compile(test_code) }.not_to raise_error
    end
    
    it 'uses the call method, not a non-existent template method' do
      # Ensure it uses 'def call' and not 'template do'
      expect(template_content).to include('def call')
      expect(template_content).not_to include('template do')
      expect(template_content).not_to include('template {')
    end
    
    it 'only uses valid roles (user and assistant, not system)' do
      # Check that it doesn't use invalid 'system' role
      expect(template_content).not_to match(/system:/)
      expect(template_content).not_to match(/role:\s*["']system["']/)
      expect(template_content).not_to match(/role:\s*:system/)
      
      # Check that it uses valid roles
      expect(template_content).to match(/assistant:|user:/)
    end
    
    it 'demonstrates auto-naming with a comment' do
      # Should have a comment about auto-generated name
      expect(template_content).to match(/# prompt_name.*(auto|generated)/i)
    end
    
    it 'can be executed with FastMcp::Prompt' do
      # Create a working test with actual FastMcp classes
      Dir.mktmpdir do |dir|
        test_file = File.join(dir, 'test_prompt.rb')
        
        test_code = <<~RUBY
          require '#{File.expand_path('../../lib/fast_mcp', __dir__)}'
          
          class ApplicationPrompt < FastMcp::Prompt
          end
          
          #{template_content}
          
          # Test instantiation
          prompt = SamplePrompt.new
          
          # Test auto-generated name
          if SamplePrompt.prompt_name != "sample"
            raise "Expected auto-generated name 'sample', got '\#{SamplePrompt.prompt_name}'"
          end
          
          # Test calling with required argument
          result = prompt.call(input: "test input")
          unless result.is_a?(Array) && result.all? { |msg| msg[:role] && msg[:content] }
            raise "Invalid prompt result structure"
          end
          
          # Test calling with optional argument
          result_with_context = prompt.call(input: "test", context: "additional context")
          unless result_with_context.is_a?(Array)
            raise "Invalid prompt result with context"
          end
          
          puts "All tests passed!"
        RUBY
        
        File.write(test_file, test_code)
        
        # Execute the test
        output = `ruby #{test_file} 2>&1`
        success = $?.success?
        
        expect(success).to be(true), "Template execution failed:\n#{output}"
        expect(output).to include("All tests passed!")
      end
    end
  end
  
  describe 'application_prompt.rb template' do
    let(:template_path) { File.join(template_dir, 'application_prompt.rb') }
    let(:template_content) { File.read(template_path) }
    
    it 'exists' do
      expect(File.exist?(template_path)).to be true
    end
    
    it 'has valid Ruby syntax' do
      # Mock ActionPrompt::Base for syntax checking
      test_code = <<~RUBY
        module ActionPrompt
          class Base; end
        end
        #{template_content}
      RUBY
      
      expect { RubyVM::InstructionSequence.compile(test_code) }.not_to raise_error
    end
    
    it 'inherits from ActionPrompt::Base' do
      expect(template_content).to include('class ApplicationPrompt < ActionPrompt::Base')
    end
    
    it 'includes helpful comments' do
      expect(template_content).to include('ActionPrompt::Base is an alias for FastMcp::Prompt')
    end
  end
end