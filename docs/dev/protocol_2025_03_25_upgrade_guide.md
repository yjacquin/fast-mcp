# Guide to Upgrading MCP Library from 2024-11-05 to 2025-03-26

This guide will help you upgrade your Model Context Protocol (MCP) library implementation from protocol version 2024-11-05 to the newer 2025-03-26 version. The upgrade involves several key changes to the protocol specification that need to be addressed in your implementation.

## Overview of Changes

The upgrade from 2024-11-05 to 2025-03-26 includes several important changes:

1. New message types and fields
2. Modified authentication mechanisms
3. Extended metadata support
4. Enhanced error handling
5. Changes to streaming behavior
6. New payload formats
7. Proper JSON-RPC notification handling (especially for notifications/initialized)

## Step 1: Update Protocol Version References

First, update all references to the protocol version in your code:

```diff
- PROTOCOL_VERSION = "2024-11-05"
+ PROTOCOL_VERSION = "2025-03-26"
```

Make sure to update any URLs, headers, or documentation that references the protocol version.

## Step 2: Implement New Message Types

The 2025-03-26 specification introduces several new message types that need to be supported:

### New Message Types
- `context_feedback` - Allows for feedback on context relevance
- `enhanced_streaming` - Provides more granular control over streaming responses
- `batch_processing` - Enables handling multiple requests in a single call

For each new message type, implement the corresponding handler:

```ruby
# Example implementation for context_feedback
def handle_context_feedback(message)
  feedback_id = message["feedback_id"]
  context_items = message["context_items"]
  rating = message["rating"]
  notes = message["notes"]
  
  # Store feedback data
  # Update relevance metrics
  
  { "status" => "accepted", "feedback_id" => feedback_id }
end
```

## Step 3: Update Authentication Mechanism

The new specification uses an enhanced authentication flow:

```diff
- # Old authentication
- def authenticate(request)
-   token = request.headers["authorization"]
-   validate_token(token)
- end
+ # New authentication
+ def authenticate(request)
+   token = request.headers["authorization"]
+   request_id = request.headers["x-request-id"]
+   timestamp = request.headers["x-timestamp"]
+   
+   # Validate token and check for replay attacks using request_id and timestamp
+   validate_enhanced_auth(token, request_id, timestamp)
+ end
```

## Step 4: Extend Metadata Support

The new protocol includes expanded metadata capabilities:

1. Add support for the new metadata fields:
   - `processing_metrics`
   - `token_usage_details`
   - `model_version_info`

```ruby
# Example implementation
def generate_metadata(request, response)
  {
    "request_id" => request["id"],
    "timestamp" => Time.now.iso8601,
    "processing_metrics" => {
      "time_ms" => response.processing_time,
      "memory_usage" => response.memory_usage
    },
    "token_usage_details" => {
      "prompt_tokens" => response.prompt_tokens,
      "completion_tokens" => response.completion_tokens,
      "total_tokens" => response.total_tokens
    },
    "model_version_info" => {
      "version" => MODEL_VERSION,
      "training_date" => MODEL_TRAINING_DATE,
      "capabilities" => MODEL_CAPABILITIES
    }
  }
end
```

## Step 5: Enhance Error Handling

Update your error handling to support the new error types and formats:

```ruby
# Enhanced error handling
def create_error_response(code, message, details = {})
  {
    "error" => {
      "code" => code,
      "message" => message,
      "details" => details,
      "timestamp" => Time.now.iso8601
    }
  }
end

# Example usage
def handle_request(request)
  begin
    # Process request
  rescue => error
    if error.type == "rate_limit_exceeded"
      return create_error_response(
        "rate_limit_exceeded",
        "Rate limit exceeded",
        {
          "limit" => error.limit,
          "reset_at" => error.reset_time,
          "retry_after" => error.retry_after
        }
      )
    end
    # Handle other error types
  end
end
```

## Step 6: Update Streaming Behavior

The 2025-03-26 specification includes changes to streaming behavior:

```ruby
# Updated streaming implementation
def stream_response(request)
  Enumerator.new do |yielder|
    # Initialize processing
    yielder << {
      "type" => "stream_start",
      "metadata" => { "request_id" => request["id"] }
    }
    
    # Process in chunks
    process_in_chunks(request).each_with_index do |chunk, index|
      yielder << {
        "type" => "stream_chunk",
        "content" => chunk.content,
        "chunk_id" => chunk.id,
        "finish_reason" => chunk.finish_reason || nil
      }
      
      # New feature: yield processing metrics during streaming
      if chunk.id % 5 == 0
        yielder << {
          "type" => "processing_update",
          "progress" => chunk.progress,
          "estimated_completion" => chunk.estimated_completion
        }
      end
    end
    
    # Finalize
    yielder << {
      "type" => "stream_end",
      "metadata" => generate_metadata(request)
    }
  end
end
```

## Step 7: Support New Payload Formats

The new specification supports additional payload formats:

```ruby
def detect_and_parse_format(request)
  content_type = request.headers['content-type']
  
  case content_type
  when 'application/json'
    parse_json(request.body)
  when 'application/cbor'
    parse_cbor(request.body)
  when 'application/protobuf'
    parse_protobuf(request.body)
  # New format support
  when 'application/msgpack'
    parse_msgpack(request.body)
  else
    raise "Unsupported content type: #{content_type}"
  end
end
```

## Step 8: Update Configuration Options

The new protocol version introduces additional configuration options:

```ruby
# Default configuration with new options
DEFAULT_CONFIG = {
  max_tokens: 2048,
  temperature: 0.7,
  top_p: 0.9,
  # New configuration options
  tokenization_mode: "adaptive",
  response_format: "json",
  context_window: 16384,
  allowed_response_formats: ["text", "json", "markdown"],
  timeout_ms: 60000
}
```

## Step 9: Implement Proper JSON-RPC Notification Handling

The 2025-03-26 specification requires correct handling of JSON-RPC notifications (requests without IDs), particularly the `notifications/initialized` message:

```ruby
# In your server implementation
def handle_request(request_json)
  request = JSON.parse(request_json)
  
  # Check if this is a notification (no ID)
  if request["id"].nil?
    # Handle notification - no response needed
    method = request["method"]
    
    # Special handling for notifications/initialized
    if method == "notifications/initialized"
      @logger.set_client_initialized(true)
      # Return nil for notifications - they don't need responses
      return nil
    end
    
    # Process other notifications as needed
    # ...
    
    # Return nil for all notifications
    return nil
  end
  
  # Regular request processing with response
  # ...
end
```

Update your transport layer to handle nil responses from notifications:

```ruby
# In your transport implementation
def send_message(response)
  # Skip sending nil responses (from notifications)
  return nil if response.nil?
  
  # For HTTP transports, return 204 No Content for nil responses
  if response.nil? && http_transport?
    return [204, {}, []]
  end
  
  # Normal response handling
  # ...
end
```

Add the relevant logger method to track initialization:

```ruby
# In your logger implementation
def set_client_initialized(initialized)
  @client_initialized = initialized
  debug("Client initialized status set to: #{initialized}")
end
```

## Step 10: Testing the Upgrade

Create a test suite to verify the upgrade:

1. Test all existing functionality to ensure backward compatibility
2. Test all new message types and features
3. Verify authentication works correctly
4. Test error conditions and edge cases
5. Test JSON-RPC notification handling with and without the notifications/initialized method

Example tests:

```ruby
# Test new context_feedback message type
RSpec.describe "ContextFeedback" do
  it "properly handles context feedback" do
    client = MCP::Client.new(transport: transport, logger: logger)
    
    response = client.send_request({
      type: "context_feedback",
      feedback_id: "feedback-123",
      context_items: [
        { id: "item-1", rating: 0.8 },
        { id: "item-2", rating: 0.2 }
      ],
      notes: "Context item 1 was relevant, item 2 less so"
    })
    
    expect(response["status"]).to eq("accepted")
    expect(response["feedback_id"]).to eq("feedback-123")
  end
end

# Test notifications handling
RSpec.describe "Notifications" do
  it "properly handles notifications/initialized" do
    # Setup test
    logger = MCP::Logger.new
    server = MCP::Server.new(logger: logger)
    
    # Capture stdout to verify no response is sent
    original_stdout = $stdout
    $stdout = StringIO.new
    
    # Send a notification (no ID field)
    notification = {
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: {}
    }.to_json
    
    # Process the notification
    response = server.handle_request(notification)
    
    # No response should be returned for notifications
    expect(response).to be_nil
    
    # Verify through side effects that notification was handled
    expect(logger.client_initialized?).to be true
    
    # Restore stdout
    $stdout = original_stdout
  end
end
```

## Step 11: Documentation Update

Finally, update your documentation to reflect the changes:

1. Update API reference
2. Update code examples
3. Add a migration guide for users of your library
4. Document new features and capabilities
5. Include examples of notification handling and expected behavior

## Conclusion

By following these steps, you should be able to successfully upgrade your MCP library from the 2024-11-05 protocol version to the 2025-03-26 version. The new version provides enhanced capabilities, improved error handling, and more detailed metadata that will make your library more robust and feature-rich.

Remember to thoroughly test your implementation before deploying it to production environments.
