# frozen_string_literal: true

# Matcher specifically for JSON-RPC error responses
# Provides focused testing for error codes, messages, and IDs
# Use this when testing error conditions for clearer intent and better error messages
RSpec::Matchers.define :be_json_rpc_error do
  match do |actual|
    @actual = actual
    @expected_status = @expected_status || 200
    
    status_matches? && content_type_matches? && body_matches_error?
  end
  
  chain :with_error_code do |code|
    @expected_code = code
  end
  
  chain :with_message do |message|
    @expected_message = message
  end
  
  chain :with_id do |id|
    @expected_id = id
  end
  
  chain :with_status do |status|
    @expected_status = status
  end
  
  failure_message do
    messages = ["expected a JSON-RPC error response"]
    
    unless status_matches?
      messages << "  Status: expected #{@expected_status}, got #{@actual.status}"
    end
    
    unless content_type_matches?
      messages << "  Content-Type: expected 'application/json', got '#{@actual.headers['Content-Type']}'"
    end
    
    if content_type_matches? && !body_matches_error?
      actual_body = parse_actual_body
      
      if actual_body.is_a?(Hash) && actual_body['error']
        error = actual_body['error']
        messages << format_error_diff(error)
        
        if @expected_id && actual_body['id'] != @expected_id
          messages << "  ID: expected #{@expected_id.inspect}, got #{actual_body['id'].inspect}"
        end
      else
        messages << "  Body: expected JSON-RPC error, but got #{actual_body.inspect}"
      end
    end
    
    messages.join("\n")
  end
  
  failure_message_when_negated do
    desc = "expected not to be a JSON-RPC error"
    desc += " with code #{@expected_code}" if @expected_code
    desc += " and message '#{@expected_message}'" if @expected_message
    desc
  end
  
  description do
    desc = "be a JSON-RPC error"
    desc += " with code #{@expected_code}" if @expected_code
    desc += " and message '#{@expected_message}'" if @expected_message
    desc += " (status: #{@expected_status})" if @expected_status != 200
    desc
  end
  
  private
  
  def status_matches?
    @actual.status == @expected_status
  end
  
  def content_type_matches?
    @actual.headers['Content-Type'] == 'application/json'
  end
  
  def body_matches_error?
    actual_body = parse_actual_body
    return false unless actual_body.is_a?(Hash)
    return false unless actual_body['jsonrpc'] == '2.0'
    return false unless actual_body['error'].is_a?(Hash)
    
    error = actual_body['error']
    
    # Check code if provided
    if @expected_code
      return false unless error['code'] == @expected_code
    end
    
    # Check message if provided
    if @expected_message
      return false unless error['message'] == @expected_message
    end
    
    # Check id if provided
    if @expected_id
      return false unless actual_body['id'] == @expected_id
    end
    
    true
  end
  
  def parse_actual_body
    return nil if @actual.body.empty?
    JSON.parse(@actual.body)
  rescue JSON::ParserError => e
    { 'json_parse_error' => e.message, 'raw_body' => @actual.body }
  end
  
  def format_error_diff(actual_error)
    messages = []
    
    if @expected_code && actual_error['code'] != @expected_code
      messages << "  Error code: expected #{@expected_code}, got #{actual_error['code']}"
    elsif @expected_code.nil? && actual_error['code']
      messages << "  Error code: #{actual_error['code']}"
    end
    
    if @expected_message && actual_error['message'] != @expected_message
      messages << "  Error message: expected '#{@expected_message}', got '#{actual_error['message']}'"
    elsif !@expected_message && actual_error['message']
      messages << "  Error message: '#{actual_error['message']}'"
    end
    
    messages.join("\n")
  end
end
