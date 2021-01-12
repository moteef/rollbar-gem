require 'rollbar'
require 'rollbar/notifier'
require 'rollbar/file_notifier'
require 'spec_helper'

describe Rollbar::FileNotifier do
  describe '#write_item' do
    subject(:write_item) { file_notifier.write_item(item) }
    let(:file_notifier) { described_class.new(notifier) }
    let(:notifier) { Rollbar::Notifier.new }
    let(:payload) { { :foo => :bar } }
    let(:item) { Rollbar::Item.build_with(payload) }
    let(:logger) { double(Logger).as_null_object }
    let(:filepath) { 'test.rollbar' }

    before { notifier.configuration.logger = logger }
    after do
      file_notifier.instance_variable_set(:@file, nil)
      file_notifier.instance_variable_get(:@rotater_thread).kill
    end

    context 'when configured to write' do
      before { notifier.configuration.write_to_file = true }

      let(:dummy_file) { double(File).as_null_object }

      it 'writes to the file' do
        allow(File).to receive(:open).with(nil, 'a').and_return(dummy_file)

        write_item

        expect(dummy_file).to have_received(:puts).with(payload.to_json)
      end
    end

    context 'when configured to write with process file without rename' do
      before do
        notifier.configuration.write_to_file = true
        notifier.configuration.files_processed_enabled = true
        file_notifier.instance_variable_set(:@update_file_time, Time.now)
      end

      let(:dummy_file) { double(File, :size => 0).as_null_object }

      it 'writes to the file' do
        allow(File).to receive(:open).with(nil, 'a').and_return(dummy_file)
        allow(File).to receive(:rename).with(dummy_file, String).and_return(0)

        write_item

        expect(dummy_file).to have_received(:puts).with(payload.to_json)
        expect(File).not_to have_received(:rename).with(dummy_file, String)
      end
    end

    context 'when configured to write with process file and file birthtime is already greater than default value' do
      before do
        notifier.configuration.write_to_file = true
        notifier.configuration.files_processed_enabled = true
        notifier.configuration.filepath = filepath
        file_notifier.instance_variable_set(:@update_file_time, Time.now - (notifier.configuration.files_processed_duration + 1).seconds)
      end

      let(:dummy_file) do
        double(
          File, :size => 0
        ).as_null_object
      end

      it 'writes to the file and rename' do
        allow(File).to receive(:open).with('test.rollbar', 'a').and_return(dummy_file)
        allow(File).to receive(:rename).with('test.rollbar', String).and_return(0)

        write_item

        expect(dummy_file).to have_received(:puts).with(payload.to_json)
      end
    end

    context 'when configured to write with process file and large file size' do
      before do
        notifier.configuration.write_to_file = true
        notifier.configuration.files_processed_enabled = true
        notifier.configuration.filepath = filepath
        file_notifier.instance_variable_set(:@update_file_time, Time.now)
      end

      let(:dummy_file) do
        double(File, :size => notifier.configuration.files_processed_size + 1).as_null_object
      end

      it 'writes to the file and rename' do
        allow(File).to receive(:open).with(filepath, 'a').and_return(dummy_file)
        allow(File).to receive(:rename).with('test.rollbar', String).and_return(0)

        write_item

        expect(dummy_file).to have_received(:puts).with(payload.to_json)
      end
    end

    context 'when configured to write with process file and file birthtime is greater than default value but no item is appended to the file' do
      before do
        notifier.configuration.write_to_file = true
        notifier.configuration.files_processed_enabled = true
        notifier.configuration.filepath = filepath
        file_notifier.instance_variable_set(:@file, dummy_file)
        file_notifier.instance_variable_get(:@rotater_thread).kill
        file_notifier.instance_variable_get(:@rotater_thread).join
        file_notifier.instance_variable_set(:@update_file_time, Time.now - (notifier.configuration.files_processed_duration + 1).seconds)
      end

      let(:dummy_file) do
        double(
          File, :size => 0
        ).as_null_object
      end

      it 'does not rotate the file' do
        expect(File).not_to receive(:open)
        expect(File).not_to receive(:rename)

        file_notifier.start
        sleep 1
      end
    end

    context 'when configured to write with process file and file birthtime is greater than default value and there are items in the file' do
      before do
        notifier.configuration.write_to_file = true
        notifier.configuration.files_processed_enabled = true
        notifier.configuration.filepath = filepath
        file_notifier.instance_variable_set(:@file, dummy_file)
        file_notifier.instance_variable_get(:@rotater_thread).kill
        file_notifier.instance_variable_get(:@rotater_thread).join
        file_notifier.instance_variable_set(:@update_file_time, Time.now - (notifier.configuration.files_processed_duration + 1).seconds)
      end

      let(:dummy_file) do
        double(
          File, :size => 1
        ).as_null_object
      end

      it 'rotates the file' do
        expect(File).to receive(:open).with('test.rollbar', 'a').and_return(dummy_file)
        expect(File).to receive(:rename).with('test.rollbar', String).and_return(0)

        file_notifier.start
        sleep 1
      end
    end
  end
end
