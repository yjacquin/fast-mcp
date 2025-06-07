module TestBaseAdapterHelper
  def self.included(base)
    base.class_eval do
      def self.read_only
        true
      end

      def self.read_only?
        @read_only_hint.nil? ? read_only : @read_only_hint
      end

      def self.read_only_hint=(value)
        @read_only_hint = value
      end
    end
  end
end
