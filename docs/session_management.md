# Session Management Guide

## Overview

The StreamableHTTP transport includes advanced session management capabilities for handling persistent connections, especially for Server-Sent Events (SSE). Sessions provide connection resumability, state tracking, and improved client experience.

## Session Architecture

### Session Lifecycle

1. **Creation**: New session created on first SSE connection
2. **Registration**: Session ID provided to client
3. **Usage**: Client includes session ID in subsequent requests
4. **Maintenance**: Server tracks active sessions and connection state
5. **Expiration**: Sessions timeout after configured period
6. **Cleanup**: Expired sessions automatically removed

### Session Components

- **Session ID**: Cryptographically secure unique identifier
- **Connection State**: Active SSE connections per session
- **Metadata**: Client information, timestamps, connection count
- **Security Context**: Authentication and authorization data

## Session ID Generation

### Security Requirements

Session IDs must be:
- **Globally unique** across all servers
- **Cryptographically secure** (minimum 128 bits entropy)
- **Visible ASCII characters** only
- **URL-safe** for use in headers and query parameters

### Implementation

```ruby
# Automatic session ID generation
class SessionManager
  def generate_session_id
    # 32-character alphanumeric string (192 bits entropy)
    SecureRandom.alphanumeric(32).upcase
    # Example: "A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6"
  end
  
  def validate_session_id(session_id)
    return false if session_id.nil? || session_id.empty?
    return false unless session_id.length == 32
    return false unless session_id.match?(/\A[A-Z0-9]+\z/)
    true
  end
end
```

### Custom Session ID Generation

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  session_id_generator: lambda do
    # Custom generation logic
    prefix = 'MCP'
    timestamp = Time.now.to_i.to_s(36).upcase
    random = SecureRandom.hex(12).upcase
    "#{prefix}#{timestamp}#{random}"
  end
)
```

## Session Configuration

### Basic Configuration

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  # Session timeouts
  session_timeout: 1800,          # 30 minutes default
  idle_timeout: 300,              # 5 minutes idle timeout
  
  # Connection limits
  max_sessions_per_client: 5,     # Per IP address
  max_connections_per_session: 3, # Per session
  
  # Cleanup intervals
  session_cleanup_interval: 300,  # Every 5 minutes
  session_gc_threshold: 1000      # GC when > 1000 expired sessions
)
```

### Advanced Configuration

```ruby
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  # Session storage
  session_store: CustomSessionStore.new,
  session_serializer: JSON,
  
  # Security
  session_id_entropy: 256,        # Bits of entropy
  session_validation: :strict,    # Validation level
  
  # Monitoring
  session_metrics: true,          # Enable session metrics
  session_logger: Logger.new('log/sessions.log')
)
```

## Client Session Usage

### Establishing a Session

```javascript
// 1. Connect to SSE endpoint to get session ID
const eventSource = new EventSource('http://localhost:3001/mcp', {
  headers: {
    'Accept': 'text/event-stream',
    'MCP-Protocol-Version': '2025-06-18'
  }
});

let sessionId = null;

eventSource.addEventListener('session', function(event) {
  const data = JSON.parse(event.data);
  sessionId = data.session_id;
  console.log('Session established:', sessionId);
});

eventSource.addEventListener('endpoint', function(event) {
  const endpoint = event.data;
  console.log('MCP endpoint:', endpoint);
});
```

### Using Session ID in Requests

```javascript
// Include session ID in subsequent JSON-RPC requests
async function makeRequest(method, params = {}) {
  const response = await fetch('http://localhost:3001/mcp', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'MCP-Protocol-Version': '2025-06-18',
      'X-Session-ID': sessionId  // Include session ID
    },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: method,
      params: params,
      id: Date.now()
    })
  });
  
  return response.json();
}

// Example usage
const tools = await makeRequest('tools/list');
console.log('Available tools:', tools);
```

### Session Resumption

```javascript
// Resume existing session by providing stored session ID
const resumeSession = (storedSessionId) => {
  const eventSource = new EventSource(`http://localhost:3001/mcp?session_id=${storedSessionId}`, {
    headers: {
      'Accept': 'text/event-stream',
      'MCP-Protocol-Version': '2025-06-18'
    }
  });
  
  eventSource.addEventListener('session-resumed', function(event) {
    const data = JSON.parse(event.data);
    console.log('Session resumed:', data.session_id);
    sessionId = data.session_id;
  });
  
  eventSource.addEventListener('session-expired', function(event) {
    console.log('Session expired, creating new session');
    // Start new session
    establishNewSession();
  });
};
```

## Server-Side Session Management

### Session Storage

#### In-Memory Storage (Default)

```ruby
# Default in-memory storage
class InMemorySessionStore
  def initialize
    @sessions = Concurrent::Hash.new
    @sessions_mutex = Mutex.new
  end
  
  def store(session_id, session_data)
    @sessions_mutex.synchronize do
      @sessions[session_id] = {
        data: session_data,
        created_at: Time.now,
        last_accessed: Time.now
      }
    end
  end
  
  def retrieve(session_id)
    @sessions_mutex.synchronize do
      session = @sessions[session_id]
      return nil unless session
      
      session[:last_accessed] = Time.now
      session[:data]
    end
  end
  
  def delete(session_id)
    @sessions_mutex.synchronize do
      @sessions.delete(session_id)
    end
  end
end
```

#### Redis Storage

```ruby
# Redis-based session storage for production
class RedisSessionStore
  def initialize(redis_client = Redis.new)
    @redis = redis_client
    @namespace = 'mcp:sessions'
  end
  
  def store(session_id, session_data)
    key = "#{@namespace}:#{session_id}"
    @redis.setex(key, 1800, JSON.generate(session_data))  # 30 min TTL
  end
  
  def retrieve(session_id)
    key = "#{@namespace}:#{session_id}"
    data = @redis.get(key)
    return nil unless data
    
    # Refresh TTL on access
    @redis.expire(key, 1800)
    JSON.parse(data)
  rescue JSON::ParserError
    nil
  end
  
  def delete(session_id)
    key = "#{@namespace}:#{session_id}"
    @redis.del(key)
  end
  
  def cleanup_expired
    # Redis handles TTL automatically
  end
end

# Configure transport to use Redis
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  session_store: RedisSessionStore.new
)
```

#### Database Storage

```ruby
# Database-backed session storage
class DatabaseSessionStore
  def store(session_id, session_data)
    Session.create!(
      session_id: session_id,
      data: session_data.to_json,
      expires_at: 30.minutes.from_now
    )
  rescue ActiveRecord::RecordNotUnique
    # Session already exists, update it
    session = Session.find_by(session_id: session_id)
    session.update!(
      data: session_data.to_json,
      expires_at: 30.minutes.from_now
    )
  end
  
  def retrieve(session_id)
    session = Session.find_by(session_id: session_id)
    return nil unless session
    return nil if session.expires_at < Time.current
    
    # Update last accessed
    session.touch
    JSON.parse(session.data)
  rescue JSON::ParserError
    nil
  end
  
  def delete(session_id)
    Session.where(session_id: session_id).delete_all
  end
  
  def cleanup_expired
    Session.where('expires_at < ?', Time.current).delete_all
  end
end
```

### Session Middleware

Create custom session handling middleware:

```ruby
class SessionMiddleware
  def initialize(app, options = {})
    @app = app
    @session_store = options[:session_store] || InMemorySessionStore.new
    @session_timeout = options[:session_timeout] || 1800
  end
  
  def call(env)
    request = Rack::Request.new(env)
    session_id = extract_session_id(request)
    
    if session_id
      session_data = @session_store.retrieve(session_id)
      env['mcp.session'] = session_data if session_data
      env['mcp.session_id'] = session_id
    end
    
    status, headers, body = @app.call(env)
    
    # Update session if modified
    if env['mcp.session'] && env['mcp.session_modified']
      @session_store.store(session_id, env['mcp.session'])
    end
    
    [status, headers, body]
  end
  
  private
  
  def extract_session_id(request)
    # Try multiple sources for session ID
    request.params['session_id'] ||
      request.get_header('HTTP_X_SESSION_ID') ||
      request.get_header('HTTP_LAST_EVENT_ID')
  end
end
```

## Session Events

### SSE Session Events

The server sends specific SSE events for session management:

```javascript
eventSource.addEventListener('session', function(event) {
  // New session created
  const data = JSON.parse(event.data);
  console.log('Session ID:', data.session_id);
  console.log('Expires at:', data.expires_at);
});

eventSource.addEventListener('session-resumed', function(event) {
  // Existing session resumed
  const data = JSON.parse(event.data);
  console.log('Resumed session:', data.session_id);
});

eventSource.addEventListener('session-expired', function(event) {
  // Session expired, need to create new one
  console.log('Session expired');
  // Reconnect to establish new session
  reconnect();
});

eventSource.addEventListener('session-warning', function(event) {
  // Session expiring soon
  const data = JSON.parse(event.data);
  console.log('Session expires in:', data.expires_in_seconds);
  // Could refresh session or warn user
});
```

### Custom Session Events

```ruby
# Send custom session events
class SessionEventManager
  def initialize(transport)
    @transport = transport
  end
  
  def notify_session_warning(session_id, expires_in)
    message = {
      event: 'session-warning',
      data: {
        session_id: session_id,
        expires_in_seconds: expires_in,
        message: 'Session will expire soon'
      }
    }
    
    @transport.send_session_message(session_id, message)
  end
  
  def notify_session_limit_reached(session_id)
    message = {
      event: 'session-limit',
      data: {
        session_id: session_id,
        message: 'Maximum connections per session reached'
      }
    }
    
    @transport.send_session_message(session_id, message)
  end
end
```

## Session Security

### Authentication Integration

Sessions can store authentication context:

```ruby
class AuthenticatedSessionTransport < FastMcp::Transports::StreamableHttpTransport
  def setup_sse_connection(session_id, io, env)
    super
    
    # Store authentication info in session
    if env['mcp.authenticated_user']
      session_data = {
        user_id: env['mcp.authenticated_user'].id,
        scopes: env['mcp.oauth_scopes'],
        authenticated_at: Time.now.iso8601
      }
      
      @session_store.store(session_id, session_data)
    end
  end
  
  def process_json_rpc_request(request, server)
    session_id = extract_session_id(request)
    
    if session_id
      session_data = @session_store.retrieve(session_id)
      if session_data
        # Add authentication context to request
        request.env['mcp.session_user_id'] = session_data['user_id']
        request.env['mcp.session_scopes'] = session_data['scopes']
      end
    end
    
    super
  end
end
```

### Session Hijacking Prevention

```ruby
class SecureSessionTransport < FastMcp::Transports::StreamableHttpTransport
  def validate_session_security(session_id, request)
    session_data = @session_store.retrieve(session_id)
    return false unless session_data
    
    # Validate IP address consistency
    if session_data['ip_address'] && session_data['ip_address'] != request.ip
      @logger.warn("Session #{session_id}: IP address mismatch")
      return false
    end
    
    # Validate User-Agent consistency
    if session_data['user_agent'] && session_data['user_agent'] != request.user_agent
      @logger.warn("Session #{session_id}: User-Agent mismatch")
      return false
    end
    
    true
  end
  
  def setup_sse_connection(session_id, io, env)
    request = Rack::Request.new(env)
    
    # Store security fingerprint
    session_data = @session_store.retrieve(session_id) || {}
    session_data.merge!(
      ip_address: request.ip,
      user_agent: request.user_agent,
      created_at: Time.now.iso8601
    )
    @session_store.store(session_id, session_data)
    
    super
  end
end
```

## Session Monitoring

### Metrics Collection

```ruby
class SessionMetrics
  def self.record_session_created(session_id)
    StatsD.increment('mcp.session.created')
    StatsD.gauge('mcp.session.active_count', active_session_count)
  end
  
  def self.record_session_expired(session_id, duration)
    StatsD.increment('mcp.session.expired')
    StatsD.timing('mcp.session.duration', duration)
  end
  
  def self.record_connection_established(session_id)
    StatsD.increment('mcp.session.connection.established')
  end
  
  def self.record_connection_closed(session_id, reason)
    StatsD.increment('mcp.session.connection.closed', tags: ["reason:#{reason}"])
  end
end
```

### Session Analytics

```ruby
# Session analytics dashboard
class SessionAnalytics
  def self.session_stats(timeframe = 1.hour)
    {
      total_sessions: Session.where('created_at > ?', timeframe.ago).count,
      active_sessions: Session.where('last_accessed > ?', 5.minutes.ago).count,
      average_duration: Session.where('created_at > ?', timeframe.ago)
                              .average('EXTRACT(EPOCH FROM (expires_at - created_at))'),
      peak_concurrent: get_peak_concurrent_sessions(timeframe),
      connection_patterns: get_connection_patterns(timeframe)
    }
  end
  
  def self.get_peak_concurrent_sessions(timeframe)
    # Query for peak concurrent sessions in timeframe
    Session.where('created_at > ?', timeframe.ago)
           .group_by_hour(:created_at)
           .maximum(:concurrent_count) || 0
  end
end
```

## Troubleshooting

### Common Session Issues

#### 1. Session Not Found

**Symptoms**: Client gets "session not found" errors
**Causes**: Session expired, server restart, storage issues
**Solutions**:
```javascript
// Handle session not found
eventSource.addEventListener('error', function(event) {
  if (event.data && event.data.includes('session_not_found')) {
    // Create new session
    reconnectWithNewSession();
  }
});
```

#### 2. Session Expired

**Symptoms**: SSE connection drops, authentication fails
**Causes**: Long idle periods, server-side timeout
**Solutions**:
```ruby
# Extend session timeout for active users
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  session_timeout: 3600,  # 1 hour
  idle_timeout: 600,      # 10 minutes
  session_refresh_threshold: 300  # Refresh when < 5 min remaining
)
```

#### 3. Multiple Sessions

**Symptoms**: Duplicate sessions, memory usage
**Causes**: Client creating multiple sessions
**Solutions**:
```ruby
# Limit sessions per client
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  max_sessions_per_client: 1,  # Only one session per IP
  session_replacement_policy: :replace_oldest
)
```

### Debug Session Issues

```ruby
# Enable session debugging
transport = FastMcp::Transports::StreamableHttpTransport.new(
  app, server,
  session_debug: true,
  session_logger: Logger.new($stdout, level: Logger::DEBUG)
)

# Manual session inspection
def inspect_session(session_id)
  session_data = @session_store.retrieve(session_id)
  puts "Session #{session_id}:"
  puts "  Data: #{session_data.inspect}"
  puts "  Connections: #{@sse_clients.count { |_, client| client[:session_id] == session_id }}"
  puts "  Created: #{session_data['created_at']}"
  puts "  Last accessed: #{session_data['last_accessed']}"
end
```

## Best Practices

### Client-Side
1. **Store session ID persistently** (localStorage/sessionStorage)
2. **Handle session expiration gracefully**
3. **Implement automatic reconnection**
4. **Monitor connection health**
5. **Clean up resources on disconnect**

### Server-Side
1. **Use appropriate session storage** (Redis for production)
2. **Configure reasonable timeouts**
3. **Monitor session metrics**
4. **Implement session security measures**
5. **Clean up expired sessions regularly**

### Security
1. **Validate session ownership**
2. **Implement rate limiting per session**
3. **Log session security events**
4. **Use secure session ID generation**
5. **Rotate session IDs on authentication changes**

This comprehensive guide covers all aspects of session management in the StreamableHTTP transport, ensuring robust and secure session handling for your MCP applications.