module Rollbar
  class FileNotifier
    EXTENSION_REGEXP = /.rollbar\z/.freeze

    attr_reader :configuration, :file_name, :notifier

    def initialize(notifier)
      @configuration = notifier.configuration
      @notifier = notifier
      @mutex = Mutex.new
      @file_name = if configuration.files_with_pid_name_enabled
                     configuration.filepath.gsub(EXTENSION_REGEXP, "_#{Process.pid}\\0")
                   else
                     configuration.filepath
                   end

      start
    end

    def write_item(item)
      write_to_file(item)
    end

    def start
      @rotater_thread = Thread.new do
        loop do
          begin
            update_file
          rescue StandardError => e
            notifier.log_error "[Rollbar] file rotater failed: #{e}"
          end
          sleep 3
        end
      end
    end

    def stop
      @rotater_thread.kill
      @rotater_thread.join
    end

    private

    def write_to_file(item)
      notifier.log_info '[Rollbar] Writing item to file'

      body = item.dump
      return unless body

      begin
        synchronize do
          @file ||= File.open(file_name, 'a')
          @file.puts(body)
          @file.flush
        end
        update_file

        notifier.log_info '[Rollbar] Success'
      rescue IOError => e
        notifier.log_error "[Rollbar] Error opening/writing to file: #{e}"
      end
    end

    def update_file
      synchronize do
        return if @file.nil?
        return unless configuration.files_processed_enabled

        file_size = @file.size
        return if file_size == 0

        time_now = Time.now
        @update_file_time ||= time_now
        return if configuration.files_processed_duration > time_now - @update_file_time && file_size < configuration.files_processed_size

        new_file_name = file_name.gsub(EXTENSION_REGEXP, "_processed_#{time_now.to_i}\\0")
        File.rename(file_name, new_file_name)
        @file.close
        @file = File.open(file_name, 'a')
        @update_file_time = time_now
      end
    end

    def synchronize
      @mutex.synchronize(&Proc.new)
    end
  end
end
