# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - Unreleased
### Added
- Security enhancement: Added DNS rebinding protection by validating Origin headers
- Added configuration options for allowed origins in rack middleware
- Allow to change the SSE and Messages route [#23 @pedrofurtado](https://github.com/yjacquin/fast-mcp/pull/23)
- Fix invalid return value when processing notifications/initialized request [#31 @abMatGit](https://github.com/yjacquin/fast-mcp/pull/31)


## [1.0.0] - 2025-03-30

### Added
- Rails integration improvements via enhanced Railtie support
- Automatic tool and resource registration in Rails applications
- Extended Rails autoload paths for tools and resources directories
- Sample generator templates for resources and tools
- MCP Client configuration documentation as reported by [#8 @sivag-csod](https://github.com/yjacquin/fast-mcp/issues/8)
- Example Ruby on Rails app in the documentation
- `FastMcp.server` now exposes the MCP server to apps that may need it to access resources
- Automated Github Releases through Github Workflow

### Fixed
- Fixed bug with Rack middlewares not being initialized properly.
- Fixed bug with STDIO logging preventing a proper connection with clients [# 11 @cs3b](https://github.com/yjacquin/fast-mcp/issues/11)
- Fixed Rails SSE streaming detection and handling
- Improved error handling in client reconnection scenarios
- Namespace consistency correction (FastMCP -> FastMcp) throughout the codebase

### Improved
- ⚠️ [Breaking] Resource content declaration changes
  - Now resources implement `content` over `default_content`
  - `content` is dynamically called when calling a resource, this implies we can declare dynamic resource contents like:
  ```ruby
  class HighestScoringUsersResource < FastMcp::Resource
  ...
    def content
      User.order(score: :desc).last(5).map(&:as_json)
    end
  end
  ```
- More robust SSE connection lifecycle management
- Optimized test suite with faster execution times
- Better logging for debugging connection issues
- Documentation had outdated examples

## [0.1.0] - 2025-03-12

### Added

- Initial release of the Fast MCP library
- FastMcp::Tool class with multiple definition styles
- FastMcp::Server class with STDIO transport and HTTP / SSE transport
- Rack Integration with authenticated and standard middleware options
- Resource management with subscription capabilities
- Binary resource support
- Examples with STDIO Transport, HTTP & SSE, Rack app
- Initialize lifecycle with capabilities 
- Comprehensive test suite with RSpec
