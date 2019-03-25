module ClerkRails
  module Api
    class Connection
      def initialize(url, auth_token)
        @c = Faraday.new(:url => url) do |conn|
          conn.authorization :Bearer, auth_token
          conn.headers['Content-Type'] = 'application/json'
          conn.adapter Faraday.default_adapter
        end
      end

      def post(path, fields, &block)
        ClerkRails::Api::Response.new(@c.post(path, fields.to_json, &block))
      end

      def patch(path, fields, &block)
        ClerkRails::Api::Response.new(@c.patch(path, fields.to_json, &block))
      end

      def delete(path, fields, &block)
        ClerkRails::Api::Response.new(@c.delete(path, fields.to_json, &block))
      end

      def get(*args, &block)
        ClerkRails::Api::Response.new(@c.get(*args, &block))
      end
    end

    class Response
      def initialize(faraday_response)
        @res = faraday_response
      end

      def data
        JSON.parse(@res.body, symbolize_names: true)
      end

      def method_missing(m, *args, &block)
        @res.send(m, *args, &block)
      end
    end
  end
end