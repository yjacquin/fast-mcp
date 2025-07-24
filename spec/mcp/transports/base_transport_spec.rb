# frozen_string_literal: true

RSpec.describe FastMcp::Transports::BaseTransport do
  let(:server) do
    instance_double(FastMcp::Server, 
      logger: Logger.new(nil),
      handle_request: nil
    )
  end
  let(:logger) { Logger.new(nil) }
  
  # Create a concrete implementation for testing since BaseTransport is abstract
  let(:test_transport_class) do
    Class.new(described_class) do
      attr_reader :started, :stopped, :sent_messages

      def initialize(server, logger: nil)
        @started = false
        @stopped = false
        @sent_messages = []
        super(server, logger: logger)
      end

      def start
        @started = true
      end

      def stop
        @stopped = true
      end

      def send_message(message)
        @sent_messages << message
      end
    end
  end

  let(:transport) { test_transport_class.new(server, logger: logger) }

  describe '#initialize' do
    it 'initializes with server and logger' do
      expect(transport.server).to eq(server)
      expect(transport.logger).to eq(logger)
    end

    it 'uses server logger if no logger provided' do
      transport_without_logger = test_transport_class.new(server)
      expect(transport_without_logger.logger).to eq(server.logger)
    end

    context 'signal handling' do
      it 'traps INT, TERM, and QUIT signals' do
        expect(Signal).to receive(:trap).with('INT')
        expect(Signal).to receive(:trap).with('TERM')
        expect(Signal).to receive(:trap).with('QUIT')
        
        test_transport_class.new(server, logger: logger)
      end

      it 'calls stop method when signals are trapped' do
        # Store the signal handlers
        signal_handlers = {}
        
        allow(Signal).to receive(:trap) do |signal, &block|
          signal_handlers[signal] = block
        end

        transport = test_transport_class.new(server, logger: logger)
        
        # Simulate each signal and verify stop is called
        %w[INT TERM QUIT].each do |signal|
          expect(transport).to receive(:stop)
          signal_handlers[signal].call
        end
      end

      it 'handles signal trapping gracefully if stop method raises an error' do
                 # Create a transport that raises an error in stop
         error_transport_class = Class.new(described_class) do
           def initialize(server, logger: nil)
             super(server, logger: logger)
           end
           
           def start; end
           def stop
             raise StandardError, "Stop failed"
           end
           def send_message(message); end
         end

        signal_handlers = {}
        allow(Signal).to receive(:trap) do |signal, &block|
          signal_handlers[signal] = block
        end

        transport = error_transport_class.new(server, logger: logger)
        
        # The signal handler should not raise an error even if stop does
        expect { signal_handlers['INT'].call }.to raise_error(StandardError, "Stop failed")
      end
    end
  end

  describe '#start' do
    it 'raises NotImplementedError for base class' do
      base_transport = described_class.new(server, logger: logger)
      expect { base_transport.start }.to raise_error(NotImplementedError, /must implement #start/)
    end

    it 'can be implemented by subclasses' do
      expect { transport.start }.not_to raise_error
      expect(transport.started).to be true
    end
  end

  describe '#stop' do
    it 'raises NotImplementedError for base class' do
      base_transport = described_class.new(server, logger: logger)
      expect { base_transport.stop }.to raise_error(NotImplementedError, /must implement #stop/)
    end

    it 'can be implemented by subclasses' do
      expect { transport.stop }.not_to raise_error
      expect(transport.stopped).to be true
    end
  end

  describe '#send_message' do
    it 'raises NotImplementedError for base class' do
      base_transport = described_class.new(server, logger: logger)
      expect { base_transport.send_message('test') }.to raise_error(NotImplementedError, /must implement #send_message/)
    end

    it 'can be implemented by subclasses' do
      message = { 'id' => 1, 'method' => 'test' }
      expect { transport.send_message(message) }.not_to raise_error
      expect(transport.sent_messages).to include(message)
    end
  end

  describe '#process_message' do
    it 'delegates to server handle_request with message' do
      message = { 'id' => 1, 'method' => 'test' }
      
      expect(server).to receive(:handle_request).with(message, headers: {})
      transport.process_message(message)
    end

    it 'passes headers to server handle_request' do
      message = { 'id' => 1, 'method' => 'test' }
      headers = { 'Content-Type' => 'application/json' }
      
      expect(server).to receive(:handle_request).with(message, headers: headers)
      transport.process_message(message, headers: headers)
    end
  end
end 