# Fast MCP Implementation Plan for MCP 2025-06-18 Revision

## Overview

This document outlines the detailed implementation plan for upgrading Fast MCP to support the Model Context Protocol revision 2025-06-18. The plan is organized by priority and includes specific file changes, new features, and testing requirements.

## Implementation Phases

### Phase 1: Core Protocol Updates (Breaking Changes)

**Priority**: Critical
**Timeline**: Immediate
**Backward Compatibility**: Breaking changes required

#### 1.1 Protocol Version Update

**Files to modify**:

- `lib/mcp/server.rb` (line 223)
- `lib/mcp/transports/rack_transport.rb`
- `lib/mcp/transports/authenticated_rack_transport.rb`

**Changes**:

- Update hardcoded protocol version from "2024-11-05" to "2025-06-18"
- Add `MCP-Protocol-Version` header validation for HTTP transports
- Implement version negotiation logic in initialization
- Add version compatibility checks

**Implementation details**:

```ruby
# In lib/mcp/server.rb
PROTOCOL_VERSION = "2025-06-18"

# In transports, validate header:
def valid_protocol_version?(request)
  version = request.headers['MCP-Protocol-Version']
  unless version == PROTOCOL_VERSION
    raise ProtocolVersionError, "Unsupported protocol version: #{version}"
  end
end
```

#### 1.2 Enhanced \_meta Field Support

**Files to modify**:

- `lib/mcp/server.rb` (enhance existing \_meta support around line 437)
- `lib/mcp/tool.rb`
- `lib/mcp/resource.rb`

**Changes**:

- Add comprehensive \_meta field validation
- Implement reserved namespace protection
- Add prefix validation for MCP-specific metadata
- Enhance metadata serialization/deserialization

**Implementation details**:

```ruby
# New module in lib/mcp/metadata.rb
module FastMcp
  module Metadata
    RESERVED_PREFIXES = ['mcp:', 'mcp-'].freeze

    def validate_meta_field(meta_data)
      return unless meta_data.is_a?(Hash)

      meta_data.each_key do |key|
        if RESERVED_PREFIXES.any? { |prefix| key.to_s.start_with?(prefix) }
          raise ReservedMetadataError, "Key '#{key}' uses reserved prefix"
        end
      end
    end
  end
end
```

### Phase 2: Structured Tool Output (Major Feature)

**Priority**: High
**Timeline**: Week 1-2
**Backward Compatibility**: Additive changes

#### 2.1 Tool Result Structure Enhancement

**Files to modify**:

- `lib/mcp/server.rb` (method `call_tool` around line 340-364)
- `lib/mcp/tool.rb`

**Changes**:

- Replace simple text/error response format with structured output
- Add support for multiple content types in tool results
- Implement content type validation and serialization
- Add resource link support in tool results

**New file**: `lib/mcp/tool_result.rb`

```ruby
module FastMcp
  class ToolResult
    attr_reader :content, :is_error, :meta

    def initialize(content: nil, is_error: false, meta: {})
      @content = normalize_content(content)
      @is_error = is_error
      @meta = meta
    end

    def to_mcp_response
      {
        content: @content,
        isError: @is_error,
        _meta: @meta
      }.compact
    end

    private

    def normalize_content(content)
      case content
      when String
        [{ type: 'text', text: content }]
      when Array
        content.map { |item| normalize_content_item(item) }
      when Hash
        [normalize_content_item(content)]
      else
        [{ type: 'text', text: content.to_s }]
      end
    end

    def normalize_content_item(item)
      return item if item.is_a?(Hash) && item.key?(:type)

      case item
      when String
        { type: 'text', text: item }
      when Hash
        if item.key?(:resource)
          { type: 'resource', resource: item[:resource] }
        else
          { type: 'text', text: item.to_s }
        end
      else
        { type: 'text', text: item.to_s }
      end
    end
  end
end
```

#### 2.2 Resource Links in Tool Results

**Files to modify**:

- `lib/mcp/tool_result.rb` (new file from above)
- `lib/mcp/resource.rb`

**Changes**:

- Add resource reference support in tool outputs
- Implement resource URI validation
- Add resource metadata linking

**Implementation details**:

```ruby
# In ToolResult class
def add_resource_link(uri, annotation = nil)
  resource_content = {
    type: 'resource',
    resource: {
      uri: uri,
      annotation: annotation
    }.compact
  }
  @content << resource_content
end
```

### Phase 3: Elicitation Framework (New Feature)

**Priority**: High
**Timeline**: Week 2-3
**Backward Compatibility**: Additive changes

#### 3.1 Elicitation Message Types

**New file**: `lib/mcp/elicitation.rb`

```ruby
module FastMcp
  module Elicitation
    class ElicitationRequest
      attr_reader :prompt, :context, :options

      def initialize(prompt:, context: {}, options: {})
        @prompt = prompt
        @context = context
        @options = options
      end

      def to_mcp_request
        {
          method: 'elicitation/request',
          params: {
            prompt: @prompt,
            context: @context,
            options: @options
          }.compact
        }
      end
    end

    class ElicitationResponse
      attr_reader :response, :cancelled

      def initialize(response: nil, cancelled: false)
        @response = response
        @cancelled = cancelled
      end

      def cancelled?
        @cancelled
      end
    end
  end
end
```

#### 3.2 Server Elicitation Support

**Files to modify**:

- `lib/mcp/server.rb`
- `lib/mcp/tool.rb`

**Changes**:

- Add elicitation request/response handling
- Implement elicitation context management
- Add elicitation hooks in tool execution

**Implementation details**:

```ruby
# In Server class
def request_elicitation(prompt, context: {}, options: {})
  return nil unless @transport.supports_elicitation?

  elicitation_request = Elicitation::ElicitationRequest.new(
    prompt: prompt,
    context: context,
    options: options
  )

  @transport.send_elicitation_request(elicitation_request)
end

# In Tool class
def elicit_user_input(prompt, context: {})
  return nil unless server&.supports_elicitation?

  server.request_elicitation(prompt, context: context)
end
```

### Phase 4: OAuth Resource Server Framework

**Priority**: Medium
**Timeline**: Week 3-4
**Backward Compatibility**: Additive changes

#### 4.1 OAuth Resource Server Classification

**New file**: `lib/mcp/oauth/resource_server.rb`

```ruby
module FastMcp
  module OAuth
    class ResourceServer
      attr_reader :authorization_server, :resource_indicators

      def initialize(authorization_server:, resource_indicators: [])
        @authorization_server = authorization_server
        @resource_indicators = resource_indicators
      end

      def protected_resource_metadata
        {
          authorization_server: @authorization_server,
          resource_indicators: @resource_indicators
        }
      end

      def validate_resource_indicator(indicator)
        return true if @resource_indicators.empty?
        @resource_indicators.include?(indicator)
      end
    end
  end
end
```

#### 4.2 Resource Indicators Support (RFC 8707)

**Files to modify**:

- `lib/mcp/transports/authenticated_rack_transport.rb`
- `lib/mcp/oauth/resource_server.rb`

**Changes**:

- Add RFC 8707 Resource Indicators validation
- Implement resource indicator middleware
- Add token validation with resource indicators

### Phase 5: Enhanced Features and Refinements

**Priority**: Low
**Timeline**: Week 4-5
**Backward Compatibility**: Additive changes

#### 5.1 Structured Logging Enhancement

**Files to modify**:

- `lib/mcp/logger.rb`
- `lib/mcp/server.rb`

**Changes**:

- Add structured logging with severity levels
- Implement client-controlled logging verbosity
- Add MCP-specific log formatting

#### 5.2 Context Field Support

**Files to modify**:

- `lib/mcp/server.rb`
- Message handling methods

**Changes**:

- Add `context` field to completion requests
- Add `title` field for human-friendly display names
- Enhance request/response context handling

## Testing Strategy

### Phase 1 Testing

- [x] Protocol version negotiation tests
- [ ] \_meta field validation tests
- [ ] Backward compatibility tests
- [ ] MCP Inspector validation

### Phase 2 Testing

- [ ] Structured tool output tests
- [ ] Resource link functionality tests
- [ ] Content type validation tests
- [ ] Multi-format response tests

### Phase 3 Testing

- [ ] Elicitation request/response flow tests
- [ ] Interactive tool execution tests
- [ ] Context management tests
- [ ] Cancellation handling tests

### Phase 4 Testing

- [ ] OAuth Resource Server tests
- [ ] Resource Indicators validation tests
- [ ] Authorization flow tests
- [ ] Token validation tests

### Phase 5 Testing

- [ ] Structured logging tests
- [ ] Context field handling tests
- [ ] Integration tests with MCP clients
- [ ] Performance benchmarks

## Migration Guide

### Breaking Changes

1. **Protocol Version**: Update client configurations to use "2025-06-18"
2. **Tool Results**: Update tool implementations to return structured results
3. **HTTP Headers**: Ensure MCP-Protocol-Version header is sent

### Backward Compatibility

- Provide feature flags for gradual migration
- Maintain legacy response format support during transition
- Add deprecation warnings for old patterns

## Documentation Updates

### Files to update

- [ ] `README.md` - Update examples and features
- [ ] `CLAUDE.md` - Add new protocol features
- [ ] `docs/` - Create documentation for new features
- [ ] Changelog - Document breaking changes

### New documentation needed

- [ ] Elicitation usage guide
- [ ] OAuth configuration guide
- [ ] Migration guide from 2024-11-05
- [ ] Structured tool output examples

## Implementation Checklist

### Phase 1 (Critical)

- [ ] Update protocol version constant
- [ ] Add MCP-Protocol-Version header validation
- [ ] Enhance \_meta field support
- [ ] Add version negotiation logic
- [ ] Update all transport classes

### Phase 2 (High Priority)

- [ ] Create ToolResult class
- [ ] Update tool execution pipeline
- [ ] Add resource link support
- [ ] Implement content type validation
- [ ] Update examples and tests

### Phase 3 (High Priority)

- [ ] Create elicitation framework
- [ ] Add server elicitation methods
- [ ] Update transport layer for elicitation
- [ ] Add tool elicitation helpers
- [ ] Create elicitation examples

### Phase 4 (Medium Priority)

- [ ] Implement OAuth Resource Server
- [ ] Add Resource Indicators support
- [ ] Update authentication middleware
- [ ] Add protected resource metadata
- [ ] Create OAuth documentation

### Phase 5 (Low Priority)

- [ ] Enhance structured logging
- [ ] Add context field support
- [ ] Add title field support
- [ ] Performance optimizations
- [ ] Final documentation updates

## Success Criteria

1. **Compliance**: Full MCP 2025-06-18 specification compliance
2. **Backward Compatibility**: Smooth migration path for existing users
3. **Testing**: 100% test coverage for new features
4. **Documentation**: Complete documentation for all new features
5. **Performance**: No significant performance degradation
6. **Examples**: Updated examples demonstrating new capabilities

## Risk Assessment

### High Risk

- Protocol version change may break existing clients
- Structured tool output changes may require significant refactoring

### Medium Risk

- Elicitation framework complexity may impact stability
- OAuth implementation may have security implications

### Low Risk

- Enhanced logging and metadata features
- Context field additions are additive only
