# frozen_string_literal: true

require "rack"

module HubStep
  class TracerMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      HubStep.tracer.with_enabled(HubStep.tracing_enabled?) do
        trace(env) do
          @app.call(env)
        end
      end
    end

    private

    def trace(env)
      HubStep.tracer.span("request") do |span|
        span.configure do
          add_tags(span, Rack::Request.new(env))
        end

        result = yield

        span.set_tag("http.status_code", result[0].to_s)

        result
      end
    end

    def add_tags(span, request)
      tags(request).each do |key, value|
        span.set_tag(key, value)
      end
    end

    def tags(request)
      tags = {
        "span.kind" => "server",
        "http.url" => request.url,
        "http.method" => request.request_method,
      }
      if id = request_id(request)
        tags["guid:github_request_id"] = id
      end

      tags.freeze
    end

    def request_id(request)
      request.env["HTTP_X_GITHUB_REQUEST_ID"]
    end
  end
end
