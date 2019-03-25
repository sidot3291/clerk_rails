module ClerkRails
  class Engine < ::Rails::Engine
    isolate_namespace ClerkRails
    engine_name "clerk"

    API = ClerkRails::Api::Connection.new(
      (ENV["CLERK_API_PATH"] || "https://api.clerk.dev"),
      ENV["CLERK_KEY"]
    )

    DATA = API.get('/v1/environment').data

    DATA[:environment_variables].each do |k, v|
      ENV[k.to_s] = v
    end

    config.before_configuration do 
      if defined?(Rails::Server) and Rails.env.development?
        require 'clerk_rails/tunnel'
        ClerkRails::Tunnel.start!(**DATA[:development_tunnel])
      end
    end  

    initializer 'clerk.configuration' do |app|
      # Add authentication helpers
      ::ActionController::Base.send :helper, ClerkRails::Helpers::View
      ::ActionController::Base.send :include, ClerkRails::Helpers::Controller
      ::ActionController::Base.send :helper, ClerkRails::Helpers::ViewAndController
      ::ActionController::Base.send :include, ClerkRails::Helpers::ViewAndController   

      # Add route helpers
      accounts_routes = {
        sign_out:             "/sign_out",
        sign_in:              "/",
        sign_up:              "/sign_up",
        verify_email_address: "/verify_email_address",
      }

      app.routes.append do
        accounts_routes.each do |k, v|
          direct k do
            "https://#{ENV["CLERK_ACCOUNTS_SUBDOMAIN"]}.#{ENV["CLERK_HOST"]}#{v}"
          end
        end
      end

      # Add roole management
      # Note: This isn't publicly launched
      ::ActiveRecord::Base.class_eval do
        def self.clerk(association_name, permissions: [])
          plural_role = association_name.to_s.pluralize.to_sym
          singular_role = association_name.to_s.singularize.to_sym

          roles_association = :"clerk_roles_#{association_name}"

          remote_class = self.name

          unless self.respond_to? :clerk_roles
            self.class_eval do 
              include ClerkRails::Clerked
            end
          end

          has_many roles_association, 
            ->{ where(scope_class: remote_class, name: singular_role) }, 
            class_name: "Clerk::Role", 
            foreign_key: :scope_id

          plural_role = association_name.to_s.pluralize.to_sym
          singular_role = association_name.to_s.singularize.to_sym

          account_accessor = self.name.underscore.pluralize.to_sym

          # Add clerk permissions to `self` the associated class
          self.clerk_permissions_map[singular_role] = permissions

          # Add magic methods to Clerk::Acount
          Clerk::Account.class_eval do
            define_method account_accessor do
              self.class::RolesWrapper.new(self, account_accessor)
            end

            define_method :"is_#{singular_role}?" do |*args|
              has_role?(singular_role, *args)
            end

            permissions.each do |permission|
              define_method :"can_#{permission}?" do |*args|
                has_permission?(permission, *args)
              end
            end                        
          end
          
          [
            association_name.to_sym,
            through: roles_association, 
            source: :account
          ]
        end        
      end         
    end  
  end
end
