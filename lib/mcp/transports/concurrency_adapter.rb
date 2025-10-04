# frozen_string_literal: true

module FastMcp
  module Transports
    # Adapter that provides unified interface for both threaded and async concurrency
    # This allows the transports to work optimally with both thread-based servers (Puma)
    # and fiber-based async servers (Falcon)
    class ConcurrencyAdapter
      def self.create(async_enabled: false)
        if async_enabled
          AsyncAdapter.new
        else
          ThreadedAdapter.new
        end
      end

      # Common interface
      def synchronize(&block)
        raise NotImplementedError, 'Subclass must implement synchronize'
      end

      def async_task(&block)
        raise NotImplementedError, 'Subclass must implement async_task'
      end

      def sleep(duration)
        raise NotImplementedError, 'Subclass must implement sleep'
      end

      def create_hash
        raise NotImplementedError, 'Subclass must implement create_hash'
      end
    end

    # Thread-based implementation (current behavior)
    # Uses OS threads and mutexes for synchronization
    class ThreadedAdapter < ConcurrencyAdapter
      def initialize
        super
        @mutex = Mutex.new
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end

      def async_task(&block)
        Thread.new(&block)
      end

      def sleep(duration)
        Kernel.sleep(duration)
      end

      def create_hash
        require 'concurrent'
        Concurrent::Hash.new
      end
    end

    # Async/Fiber-based implementation
    # Uses fiber scheduler and async primitives for better concurrency
    class AsyncAdapter < ConcurrencyAdapter
      def initialize
        super
        require 'async'
        require 'async/semaphore'
        @semaphore = Async::Semaphore.new(1)
      end

      def synchronize(&block)
        @semaphore.acquire do
          block.call
        end
      end

      def async_task(&block)
        # Create async task in current reactor
        Async do |_task|
          block.call
        end
      end

      def sleep(duration)
        # Uses fiber-aware sleep (Ruby 3.0+ with fiber scheduler)
        Kernel.sleep(duration)
      end

      def create_hash
        # Regular hash is fine with fibers (single-threaded per reactor)
        {}
      end
    end
  end
end
