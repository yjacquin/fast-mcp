# frozen_string_literal: true

# Matcher for default OK responses (non-JSON-RPC)
# Used for testing plain text responses from non-MCP endpoints
RSpec::Matchers.define :be_default_ok_response do
  match do |actual|
    @actual = actual
    
    status_matches? && content_type_matches? && body_matches?
  end
  
  failure_message do
    messages = ["expected a default OK response"]
    
    unless status_matches?
      messages << "  Status: expected 200, got #{@actual.status}"
    end
    
    unless content_type_matches?
      messages << "  Content-Type: expected 'text/plain', got '#{@actual.headers['Content-Type']}'"
    end
    
    unless body_matches?
      messages << "  Body: expected 'OK', got #{@actual.body.inspect}"
    end
    
    messages.join("\n")
  end
  
  failure_message_when_negated do
    "expected not to be a default OK response (status: 200, content-type: text/plain, body: 'OK')"
  end
  
  description do
    "be a default OK response (200 OK with text/plain content)"
  end
  
  private
  
  def status_matches?
    @actual.status == 200
  end
  
  def content_type_matches?
    @actual.headers['Content-Type'] == 'text/plain'
  end
  
  def body_matches?
    @actual.body == 'OK'
  end
end
