# frozen_string_literal: true

require "English"
require "faraday"

module HubStep
  module Faraday
    # Faraday middleware for wrapping a request in a span.
    #
    # tracer = HubStep::Tracer.new
    # Faraday.new do |b|
    #   b.request(:hubstep, tracer)
    #   b.adapter(:typhoeus)
    # end
    class Middleware < ::Faraday::Middleware
      def initialize(app, tracer)
        super(app)
        @tracer = tracer
      end

      def call(request_env)
        # We pass `finish: false` so that the span won't have its end time
        # recorded until #on_complete runs (which could be after #call returns
        # if the request is asynchronous).
        @tracer.span("faraday", finish: false) do |span|
          begin
            span.configure { record_request(span, request_env) }
            @app.call(request_env).on_complete do |response_env|
              span.configure do
                record_response(span, response_env)
                span.finish if span.end_micros.nil?
              end
            end
          ensure
            span.configure { record_exception(span, $ERROR_INFO) }
          end
        end
      end

      private

      def record_request(span, request_env)
        method = request_env[:method].to_s.upcase
        span.operation_name = "Faraday #{method}"
        span.set_tag("component", "faraday")
        span.set_tag("http.url", request_env[:url])
        span.set_tag("http.method", method)
      end

      def record_response(span, response_env)
        span.set_tag("http.status_code", response_env[:status])
      end

      def record_exception(span, exception)
        return unless exception

        # The on_complete block may not be called if an exception is
        # thrown while processing the request, so we need to finish the
        # span here.
        @tracer.record_exception(span, exception)
        span.finish if span.end_micros.nil?
      end
    end
  end
end

Faraday::Request.register_middleware hubstep: HubStep::Faraday::Middleware
