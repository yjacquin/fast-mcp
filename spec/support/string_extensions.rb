# frozen_string_literal: true

# Add constantize method to String class if not already defined
unless String.method_defined?(:constantize)
  class String
    def constantize
      # This is a simplified version of constantize for testing
      # In real use, this would look up the actual constant
      # But for tests we just need it to work with mocks
      Object.const_get(self) rescue nil
    end

    def blank?
      empty? || nil?
    end

    def underscore
      self
    end
  end
end

# Add blank? to NilClass if not already defined
unless NilClass.method_defined?(:blank?)
  class NilClass
    def blank?
      true
    end
  end
end
