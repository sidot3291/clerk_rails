module ClerkRails
  module Tunnel
    def self.data_dir
      Rails.root.join(".clerk")
    end

    def self.crt_path
      data_dir.join("dev.crt")
    end

    def self.key_path
      data_dir.join("dev.key")
    end

    def self.ngrok_path
      data_dir.join("clerk_#{executable_type}")
    end

    def self.ngrok_zip_path
      data_dir.join("clerk_#{executable_type}.zip")
    end

    def self.crt_ready?
      File.exist? key_path and File.exist? crt_path
    end

    def self.ngrok_ready?
      File.exist? ngrok_path
    end

    def self.setup_ngrok!
      ngrok_paths = {
        darwin_amd64: "/c/4VmDzA7iaHb/ngrok-stable-darwin-amd64.zip",
        darwin_386: "/c/4VmDzA7iaHb/ngrok-stable-darwin-386.zip",
        windows_amd64: "/c/4VmDzA7iaHb/ngrok-stable-windows-amd64.zip",
        windows_386: "/c/4VmDzA7iaHb/ngrok-stable-windows-386.zip",
        freebsd_amd64: "/c/4VmDzA7iaHb/ngrok-stable-freebsd-amd64.zip",
        freebsd_386: "/c/4VmDzA7iaHb/ngrok-stable-freebsd-386.zip",
        linux_amd64: "/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip",
        linux_386: "/c/4VmDzA7iaHb/ngrok-stable-linux-386.zip",
        linux_arm: "/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip",
        linux_arm64: "/a/nmkK3DkqZEB/ngrok-2.2.8-linux-arm64.zip",
      }

      puts "=> [Clerk] Downloading tunnel executable."
      require 'zip'
      http = Net::HTTP.new("bin.equinox.io", 443)
      http.use_ssl = true
      resp = http.get(ngrok_paths[executable_type])
      open(ngrok_zip_path, "wb") do |file|
        file.write(resp.body)
      end

      puts "=> [Clerk] Unzipping tunnel executable."
      Zip::File.open(ngrok_zip_path) do |zipfile|
        zipfile.each do |file|
          if file.name == "ngrok"
            zipfile.extract(file, ngrok_path)
          end
        end
      end

      File.delete(ngrok_zip_path) 

      puts "=> [Clerk] Setup done."
    end

    def self.save_tunnel_cert_locally!(certificate, certificate_key)
      Dir.mkdir(data_dir) unless Dir.exist? data_dir
      File.write(crt_path, certificate)
      File.write(key_path, certificate_key)
    end

    def self.start!(certificate:, certificate_key:, authorization:)
      save_tunnel_cert_locally!(certificate, certificate_key)

      setup_ngrok! unless ngrok_ready?

      # Ngrok currently does not send an X-Forwarded-Proto header with requests,
      # which causes Rack to interpret them as HTTP instead of HTTPS.  This patches
      # Rack so it treats everthing as HTTPS
      self.patch_rack_requests

      # Ngrok only worked properly if the host was specified as 127.0.0.1, but
      # the default was 0.0.0.0.  This changes the host to 127.0.0.1
      server = ObjectSpace.each_object(Rails::Server).first
      server_options = server.instance_variable_get(:@options).dup
      if !server.send(:use_puma?)
        raise "Sorry, Clerk currently only supports Rails using the Puma server."
      elsif server_options[:user_supplied_options].include? :Host
        raise "Sorry, Clerk cannot boot with a custom host: #{server_options[:Host]}"
      else
        server_options[:user_supplied_options] << :Host
        server_options[:Host] = "127.0.0.1"
        server.instance_variable_set(:@options, server_options)
      end

      require 'ngrok/tunnel'
      self.patch_ngrok_gem
      puts "=> Booting https://#{ENV["CLERK_APP_SUBDOMAIN"]}.#{ENV["CLERK_HOST"]} with Clerk"
      options = {
        addr: server_options[:Port],
        authtoken: authorization,
        hostname: "#{ENV["CLERK_APP_SUBDOMAIN"]}.#{ENV["CLERK_HOST"]}",
        region: "us",
        crt: Rails.root.join(".clerk/dev.crt"),
        key: Rails.root.join(".clerk/dev.key")
      }
      Ngrok::Tunnel.start(options)
    end

    private

      def self.executable_type
        @@executable_type ||= begin
          platform = begin
            case RbConfig::CONFIG['host_os'].downcase
            when /linux/
              "linux"
            when /darwin/
              "darwin"
            when /bsd/
              "freebsd"
            when /mingw|mswin/
              "windows"
            else
              "linux"
            end
          end

          cpu = begin
            case RbConfig::CONFIG['host_cpu'].downcase
            when /amd64|x86_64/
              "amd64"
            when /^arm/
              RbConfig::CONFIG['host_cpu'].include?("64") ? "arm64" : "arm"
            else
              "386"
            end
          end

          executable_type = :"#{platform}_#{cpu}" 
        end
      end

      # This configured puma to terminate TLS, but since Puma's TLS terminator has a bug we moved termination to ngrok
      # https://github.com/puma/puma/issues/1670
      # def self.configure_puma_options
      #   server = ObjectSpace.each_object(Rails::Server).first
      #   server_options = server.instance_variable_get(:@options).dup
      #   if !server.send(:use_puma?)
      #     raise "Sorry, Clerk cannot boot with a custom host: #{server_options[:Host]}"
      #   elsif server_options[:user_supplied_options].include? :Host
      #     raise "Sorry, Clerk currently only supports Rails using the Puma server."
      #   else
      #     server_options[:user_supplied_options] << :Host
      #     server_options[:Host] = "ssl://127.0.0.1:#{server_options[:Port]}?key=.clerk/dev.key&cert=.clerk/dev.crt"
      #     server.instance_variable_set(:@options, server_options)
      #   end
      # end

      def self.patch_rack_requests
        ::ActionDispatch::Request.class_eval do
          def scheme
            "https"
          end
        end
      end

      def self.patch_ngrok_gem
        # The ngrok-tunnel gem supports launching ngrok's HTTP tunnels, but Clerk uses TLS.
        # This 
        ::Ngrok::Tunnel.class_eval do
          def self.start(params = {})
            init(params)

            if stopped?
              @params[:log] = (@params[:log]) ? File.open(@params[:log], 'w+') : Tempfile.new('ngrok')
              @pid = spawn("exec #{ClerkRails::Tunnel.ngrok_path} tls " + ngrok_exec_params)
              at_exit { Ngrok::Tunnel.stop }
              fetch_urls
            end

            @status = :running
            @ngrok_url.gsub("tls", "https")
          end  

          private

            def self.ngrok_exec_params
              exec_params = "-log=stdout -log-level=debug "
              exec_params << "-region=#{@params[:region]} " if @params[:region]
              exec_params << "-host-header=#{@params[:host_header]} " if @params[:host_header]
              exec_params << "-authtoken=#{@params[:authtoken]} " if @params[:authtoken]
              exec_params << "-subdomain=#{@params[:subdomain]} " if @params[:subdomain]
              exec_params << "-hostname=#{@params[:hostname]} " if @params[:hostname]
              exec_params << "-crt=#{@params[:crt]} " if @params[:crt]
              exec_params << "-key=#{@params[:key]} " if @params[:key]
              exec_params << "-inspect=#{@params[:inspect]} " if @params.has_key? :inspect
              exec_params << "-config=#{@params[:config]} #{@params[:addr]} > #{@params[:log].path}"
            end          

            def self.fetch_urls
              @params[:timeout].times do
                log_content = @params[:log].read

                result = log_content.scan(/URL:(.+)\sProto:(tls)\s/)
                if !result.empty?
                  result = Hash[*result.flatten].invert
                  @ngrok_url = result['tls']
                  return @ngrok_url if @ngrok_url
                end

                error = log_content.scan(/msg="command failed" err="([^"]+)"/).flatten
                unless error.empty?
                  self.stop
                  raise Ngrok::Error, error.first
                end

                sleep 1
                @params[:log].rewind
              end
              self.stop
              raise Ngrok::FetchUrlError, "Unable to fetch external url"
            end          
        end
      end
  end
end