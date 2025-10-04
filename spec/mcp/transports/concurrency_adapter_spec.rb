# frozen_string_literal: true

RSpec.describe FastMcp::Transports::ConcurrencyAdapter do
  describe '.create' do
    context 'when async_enabled is false' do
      it 'returns a ThreadedAdapter' do
        adapter = described_class.create(async_enabled: false)
        expect(adapter).to be_a(FastMcp::Transports::ThreadedAdapter)
      end
    end

    context 'when async_enabled is true' do
      it 'returns an AsyncAdapter' do
        adapter = described_class.create(async_enabled: true)
        expect(adapter).to be_a(FastMcp::Transports::AsyncAdapter)
      end
    end
  end

  describe '#synchronize' do
    it 'raises NotImplementedError on base class' do
      adapter = described_class.new
      expect { adapter.synchronize { 'test' } }.to raise_error(NotImplementedError)
    end
  end

  describe '#async_task' do
    it 'raises NotImplementedError on base class' do
      adapter = described_class.new
      expect { adapter.async_task { 'test' } }.to raise_error(NotImplementedError)
    end
  end

  describe '#sleep' do
    it 'raises NotImplementedError on base class' do
      adapter = described_class.new
      expect { adapter.sleep(1) }.to raise_error(NotImplementedError)
    end
  end

  describe '#create_hash' do
    it 'raises NotImplementedError on base class' do
      adapter = described_class.new
      expect { adapter.create_hash }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe FastMcp::Transports::ThreadedAdapter do
  let(:adapter) { described_class.new }

  describe '#synchronize' do
    it 'provides thread-safe synchronization' do
      counter = 0
      threads = 10.times.map do
        Thread.new do
          10.times do
            adapter.synchronize { counter += 1 }
          end
        end
      end
      threads.each(&:join)
      expect(counter).to eq(100)
    end

    it 'executes the block' do
      result = adapter.synchronize { 'executed' }
      expect(result).to eq('executed')
    end
  end

  describe '#async_task' do
    it 'returns a Thread' do
      task = adapter.async_task { sleep 0.01 }
      expect(task).to be_a(Thread)
      task.join
    end

    it 'executes the block in a new thread' do
      executed = false
      task = adapter.async_task { executed = true }
      task.join
      expect(executed).to be(true)
    end
  end

  describe '#sleep' do
    it 'sleeps for the specified duration' do
      start_time = Time.now
      adapter.sleep(0.1)
      end_time = Time.now
      expect(end_time - start_time).to be >= 0.1
    end
  end

  describe '#create_hash' do
    it 'returns a Concurrent::Hash' do
      hash = adapter.create_hash
      expect(hash).to be_a(Concurrent::Hash)
    end
  end
end

RSpec.describe FastMcp::Transports::AsyncAdapter do
  let(:adapter) { described_class.new }

  describe '#synchronize' do
    it 'provides fiber-safe synchronization' do
      result = nil
      adapter.synchronize { result = 'executed' }
      expect(result).to eq('executed')
    end

    it 'allows sequential access' do
      results = []
      adapter.synchronize { results << 1 }
      adapter.synchronize { results << 2 }
      expect(results).to eq([1, 2])
    end
  end

  describe '#async_task' do
    it 'creates an async task' do
      executed = false
      task = adapter.async_task { executed = true }
      expect(task).to be_a(Async::Task)
      task.wait
      expect(executed).to be(true)
    end

    it 'executes the block asynchronously' do
      result = nil
      task = adapter.async_task { result = 'async' }
      task.wait
      expect(result).to eq('async')
    end
  end

  describe '#sleep' do
    it 'sleeps for the specified duration' do
      start_time = Time.now
      adapter.sleep(0.1)
      end_time = Time.now
      expect(end_time - start_time).to be >= 0.1
    end
  end

  describe '#create_hash' do
    it 'returns a regular Hash' do
      hash = adapter.create_hash
      expect(hash).to be_a(Hash)
      expect(hash).not_to be_a(Concurrent::Hash)
    end
  end
end
