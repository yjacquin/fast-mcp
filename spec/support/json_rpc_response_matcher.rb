# frozen_string_literal: true

# Matcher for general JSON-RPC 2.0 responses (success or error)
# Validates that responses follow the JSON-RPC 2.0 specification:
# - Must be valid JSON with Content-Type: application/json
# - Must be a Hash containing 'jsonrpc' => '2.0'
# - Empty body is allowed for success responses
# For error-specific tests, prefer the be_json_rpc_error matcher
RSpec::Matchers.define :be_json_rpc_response do
  match do |actual|
    @actual = actual
    @expected_status = expected_status
    @expected_body = @chained_body || ''
    
    status_matches? && content_type_matches? && body_matches?
  end
  
  chain :with_status do |status|
    @expected_status = status
  end
  
  chain :with_body do |body|
    @chained_body = body
  end
  
  failure_message do
    messages = ["expected a JSON-RPC response"]
    
    unless status_matches?
      messages << "  Status: expected #{@expected_status}, got #{@actual.status}"
    end
    
    unless content_type_matches?
      messages << "  Content-Type: expected 'application/json', got '#{@actual.headers['Content-Type']}'"
    end
    
    unless body_matches?
      if @expected_body.nil? || @expected_body == ''
        messages << "  Body: expected empty, got #{@actual.body.inspect}"
      else
        actual_body = parse_actual_body
        if !actual_body.is_a?(Hash)
          messages << "  Body: expected valid JSON-RPC response, got #{actual_body.inspect}"
        elsif actual_body['jsonrpc'] != '2.0'
          messages << "  Body: expected JSON-RPC version 2.0, got #{actual_body['jsonrpc'].inspect}"
        else
          messages << format_body_diff(actual_body)
        end
      end
    end
    
    messages.join("\n")
  end
  
  failure_message_when_negated do
    desc = "expected not to be a JSON-RPC response"
    desc += " with status #{@expected_status}" if @expected_status != 200
    desc += " and body #{@expected_body.inspect}" unless @expected_body.nil? || @expected_body == ''
    desc
  end
  
  description do
    desc = "be a JSON-RPC response"
    desc += " with status #{@expected_status}" if @expected_status != 200
    desc += " with body #{format_expected_body}" unless @expected_body.nil? || @expected_body == ''
    desc
  end
  
  private
  
  def expected_status
    @expected_status || 200
  end
  
  def status_matches?
    @actual.status == expected_status
  end
  
  def content_type_matches?
    @actual.headers['Content-Type'] == 'application/json'
  end
  
  def body_matches?
    if @expected_body.nil? || @expected_body == ''
      @actual.body.empty?
    else
      actual_body = parse_actual_body
      return false unless actual_body.is_a?(Hash)
      return false unless actual_body['jsonrpc'] == '2.0'
      actual_body == @expected_body
    end
  end
  
  def parse_actual_body
    return nil if @actual.body.empty?
    JSON.parse(@actual.body)
  rescue JSON::ParserError => e
    { 'json_parse_error' => e.message, 'raw_body' => @actual.body }
  end
  
  def format_body_diff(actual_body)
    "  Body: expected #{@expected_body.inspect}\n        but got #{actual_body.inspect}"
  end
  
  def format_expected_body
    @expected_body.inspect
  end
end
