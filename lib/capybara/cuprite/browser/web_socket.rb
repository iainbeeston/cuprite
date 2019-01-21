# frozen_string_literal: true

require "json"
require "socket"
require "forwardable"
require "websocket/driver"
require 'concurrent-edge'

module Capybara::Cuprite
  class Browser
    class WebSocket
      extend Forwardable

      attr_reader :url, :channel

      def initialize(url, logger)
        @url      = url
        @logger   = logger
        uri       = URI.parse(@url)
        @sock     = TCPSocket.new(uri.host, uri.port)
        @driver   = ::WebSocket::Driver.client(self)
        @channel  = Concurrent::Channel.new
        @alive    = true

        @driver.on(:message, &method(:on_message))

        Concurrent::Channel.go_loop do
          return false unless @alive

          begin
            data = @sock.read_nonblock(512)
            @driver.parse(data) if data
          rescue EOFError, Errno::ECONNRESET
            @alive = false
          rescue IO::WaitReadable
            sleep 0.1
          end
          true
        end

        @driver.start
      end

      def send_message(data)
        json = data.to_json
        @driver.text(json)
        @logger&.puts("\n\n>>> #{json}")
      end

      def on_message(event)
        data = JSON.parse(event.data)
        Concurrent::Channel.go do
          @channel << data
        end
        @logger&.puts("    <<< #{event.data}\n")
      end

      def write(data)
        @sock.write(data)
      end

      def close
        @driver.close
        @alive = false
      end
    end
  end
end
