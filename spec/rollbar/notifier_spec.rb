require 'rollbar'
require 'rollbar/notifier'
require 'spec_helper'

describe Rollbar::Notifier do
  describe '#scope' do
    let(:new_scope) do
      { 'foo' => 'bar' }
    end
    let(:new_config) do
      { 'environment' => 'foo' }
    end

    it 'creates a new notifier with merged scope and configuration' do
      new_notifier = subject.scope(new_scope, new_config)

      expect(new_notifier).not_to be(subject)
      expect(subject.configuration.environment).to be_eql(nil)
      expect(new_notifier.configuration.environment).to be_eql('foo')
      expect(new_notifier.scope_object['foo']).to be_eql('bar')
      expect(new_notifier.configuration).not_to be(subject.configuration)
      expect(new_notifier.scope_object).not_to be(subject.scope_object)
    end
  end

  describe '#scope!' do
    let(:new_scope) do
      { 'foo' => 'bar' }
    end
    let(:new_config) do
      { 'environment' => 'foo' }
    end

    it 'mutates the notifier with a merged scope and configuration' do
      result = subject.scope!(new_scope, new_config)

      expect(result).to be(subject)
      expect(subject.configuration.environment).to be_eql('foo')
      expect(subject.scope_object['foo']).to be_eql('bar')
      expect(subject.configuration).to be(subject.configuration)
      expect(subject.scope_object).to be(subject.scope_object)
    end
  end

  describe '#process_item' do
    subject(:process_item) { notifier.process_item(item) }
    let(:notifier) { described_class.new }
    let(:payload) { { :foo => :bar } }
    let(:item) { Rollbar::Item.build_with(payload) }
    let(:logger) { double(Logger).as_null_object }
    let(:filepath) { 'test.rollbar' }
    let(:file_notifier) { instance_double(::Rollbar::FileNotifier) }

    before do
      notifier.configuration.logger = logger
      allow(described_class).to receive(:file_notifier).and_return(file_notifier)
    end

    context 'when configured to write to file' do
      before { notifier.configuration.write_to_file = true }

      it 'writes to the file' do
        expect(file_notifier).to receive(:write_item).with(item)

        process_item
      end
    end

    context 'when configured not to write' do
      before do
        notifier.configuration.write_to_file = false

        expect(File).not_to receive(:open)
        expect(file_notifier).not_to receive(:write_item)
        allow(Net::HTTP).to receive(:new).and_return(dummy_http)
        allow(::Rollbar).to receive(:log_error)
      end

      let(:dummy_http) { double(Net::HTTP).as_null_object }

      it 'does not write to the file' do
        process_item
      end

      it 'attempts to send via HTTP' do
        process_item

        expect(dummy_http).to have_received(:request)
      end

      context 'a socket error occurs' do
        before { allow(dummy_http).to receive(:request).and_raise(SocketError) }

        it 'passes the message on' do
          expect { process_item }.to raise_error(SocketError)
        end

        context 'the item has come via failsafe' do
          let(:exception) { SocketError.new('original exception') }
          let(:payload) { notifier.send_failsafe('the failure', exception) }

          it 'does not pass the message on' do
            expect { process_item }.to_not raise_error
          end
        end
      end
    end
  end

  describe '#send_failsafe' do
    subject(:send_failsafe) { described_class.new.send_failsafe(message, exception) }
    let(:message) { 'testing failsafe' }
    let(:exception) { StandardError.new }

    it 'sets a flag on the payload so we know the payload has come through this way' do
      expect(send_failsafe['data']).to include(:failsafe => true)
    end
  end

  if RUBY_PLATFORM == 'java'
    describe '#extract_arguments' do
      # See https://docs.oracle.com/javase/8/docs/api/java/lang/Throwable.html
      # for more background
      it 'extracts java.lang.Exception' do
        begin
          raise java.lang.Exception, 'Hello'
        rescue StandardError => e
          _message, exception, _extra = Rollbar::Notifier.new.send(:extract_arguments, [e])
          expect(exception).to eq(e)
        end
      end

      it 'extracts java.lang.Error' do
        begin
          raise java.lang.AssertionError.new('Hello') # rubocop:disable Style/RaiseArgs
        rescue java.lang.Error => e
          _message, exception, _extra = Rollbar::Notifier.new.send(:extract_arguments, [e])
          expect(exception).to eq(e)
        end
      end
    end
  end
end
