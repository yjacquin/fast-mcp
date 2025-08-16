# frozen_string_literal: true

module FastMcp
  module Metadata
    # Reserved prefixes that cannot be used in user-defined metadata keys
    RESERVED_PREFIXES = ['mcp:', 'mcp-'].freeze

    # Error raised when attempting to use a reserved metadata key
    class ReservedMetadataError < StandardError; end

    # Error raised when metadata validation fails
    class InvalidMetadataError < StandardError; end

    # Validates metadata fields to ensure they don't use reserved prefixes
    # and conform to the expected structure
    #
    # @param meta_data [Hash, nil] The metadata to validate
    # @raise [ReservedMetadataError] if a reserved prefix is used
    # @raise [InvalidMetadataError] if metadata structure is invalid
    # @return [void]
    def validate_meta_field(meta_data)
      return if meta_data.nil?

      raise InvalidMetadataError, "Metadata must be a Hash, got #{meta_data.class}" unless meta_data.is_a?(Hash)

      meta_data.each_key do |key|
        key_str = key.to_s
        if RESERVED_PREFIXES.any? { |prefix| key_str.start_with?(prefix) }
          raise ReservedMetadataError, "Key '#{key}' uses reserved prefix"
        end

        # Validate key format (should be string-like and not empty)
        raise InvalidMetadataError, 'Metadata keys cannot be empty' if key_str.empty?
      end
    end

    # Sanitizes metadata by removing any reserved keys and validating structure
    #
    # @param meta_data [Hash, nil] The metadata to sanitize
    # @return [Hash] The sanitized metadata
    def sanitize_meta_field(meta_data)
      return {} if meta_data.nil? || !meta_data.is_a?(Hash)

      sanitized = {}
      meta_data.each do |key, value|
        key_str = key.to_s
        next if RESERVED_PREFIXES.any? { |prefix| key_str.start_with?(prefix) }
        next if key_str.empty?

        sanitized[key] = value
      end

      sanitized
    end

    # Merges metadata from multiple sources, with later sources taking precedence
    # Validates that no reserved prefixes are used in the final result
    #
    # @param meta_data_sources [Array<Hash>] Array of metadata hashes to merge
    # @return [Hash] The merged and validated metadata
    def merge_meta_fields(*meta_data_sources)
      merged = {}

      meta_data_sources.compact.each do |meta_data|
        next unless meta_data.is_a?(Hash)

        sanitized = sanitize_meta_field(meta_data)
        merged.merge!(sanitized)
      end

      merged
    end

    # Checks if a metadata key uses a reserved prefix
    #
    # @param key [String, Symbol] The key to check
    # @return [Boolean] true if the key uses a reserved prefix
    def reserved_key?(key)
      key_str = key.to_s
      RESERVED_PREFIXES.any? { |prefix| key_str.start_with?(prefix) }
    end

    # Formats metadata for JSON serialization, ensuring proper structure
    #
    # @param meta_data [Hash, nil] The metadata to format
    # @return [Hash, nil] The formatted metadata, or nil if empty
    def format_meta_field(meta_data)
      return nil if meta_data.nil? || meta_data.empty?

      formatted = sanitize_meta_field(meta_data)
      formatted.empty? ? nil : formatted
    end
  end
end
