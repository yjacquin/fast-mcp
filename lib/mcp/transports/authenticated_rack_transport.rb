# frozen_string_literal: true

require_relative 'rack_transport'

module FastMcp
  module Transports
    class AuthenticatedRackTransport < RackTransport
      def initialize(app, server, options = {})
        super

        @auth_enabled = options[:authenticate] || false
        @auth_options = options[:auth_options] || {}
        @auth_strategy = @auth_options[:auth_strategy] || :token
        @auth_exempt_paths = @auth_options[:auth_exempt_paths] || []
      end

      def call(env)
        request = Rack::Request.new(env)

        return super if auth_disabled? || exempt_from_auth?(request.path)

        if authenticate_request(request)
          super
        else
          unauthorized_response(request)
        end
      end

      private

      def auth_disabled?
        !@auth_enabled
      end

      def exempt_from_auth?(path)
        @auth_exempt_paths.any? { |exempt_path| path.start_with?(exempt_path) }
      end

      def authenticate_request(request)
        case @auth_strategy
        when :proc, Proc
          authenticate_proc(request)
        when :http_basic
          authenticate_http_basic(request)
        else
          authenticate_token(request)
        end
      end

      def authenticate_http_basic(request)
        auth = Rack::Auth::Basic::Request.new(request.env)
        user = @auth_options[:auth_user] || ENV.fetch('MCP_AUTH_USER')
        password = @auth_options[:auth_password] || ENV.fetch('MCP_AUTH_PASSWORD')
        auth.provided? && auth.credentials == [user, password]
      end

      def authenticate_token(request)
        auth_token = @auth_options[:auth_token] || ENV.fetch('MCP_AUTH_TOKEN')
        header_token = request.get_header("HTTP_#{header_name}")
        header_token&.gsub(/^Bearer\s+/i, '') == auth_token
      end

      def header_name
        header = @auth_options[:auth_header] || ENV.fetch('MCP_AUTH_HEADER', 'Authorization')
        header.gsub('^HTTP_', '').upcase.gsub('-', '_')
      end

      def authenticate_proc(request)
        auth_proc = @auth_strategy.is_a?(Proc) ? @auth_strategy : @auth_options[:auth_proc]
        auth_proc.call(request)
      end

      def unauthorized_response(request)
        headers = { 'Content-Type' => 'application/json' }

        headers['WWW-Authenticate'] = 'Basic realm="Fast MCP API"' if @auth_strategy == :http_basic

        body = JSON.generate(
          {
            jsonrpc: '2.0',
            error: {
              code: -32_000,
              message: 'Unauthorized: Invalid or missing authentication credentials'
            },
            id: extract_request_id(request)
          }
        )

        [401, headers, [body]]
      end

      def extract_request_id(request)
        return nil unless request.post?

        begin
          body = request.body.read
          request.body.rewind
          JSON.parse(body)['id']
        rescue StandardError
          nil
        end
      end
    end
  end
end
