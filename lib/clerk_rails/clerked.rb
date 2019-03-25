module ClerkRails
  module Clerked
    extend ActiveSupport::Concern

    included do
      @@clerk_permissions_map = {}
      @@clerk_roles_map = {}

      has_many :clerk_roles, clerk_roles_scope, class_name: "Clerk::Role", foreign_key: :scope_id

      has_many :accounts, through: :clerk_roles, source: :account do

        def with(role: nil, permission: nil)
          if (role.nil? and permission.nil?) or (not role.nil? and not permission.nil?)
            raise ArgumentError.new("Invalid argument, must supply either a role or permission")
          end

          if not role.nil?
            return where(Clerk::Role.table_name=>{name: role})
          elsif not permission.nil?
            all_roles = self.proxy_association.owner.class.roles_with_permission(permission)
            return where(Clerk::Role.table_name=>{name: all_roles})
          end
        end

      end
    end

    def has_role?(role, account)
      account.has_role?(role, self)
    end

    def roles_for(account)
      account.roles_for(self)
    end

    class_methods do
      def clerk_permissions_map
        @@clerk_permissions_map
      end
      
      def clerk_roles_map
        @@clerk_roles_map
      end

      def roles_with_permission(permission)
        @@clerk_roles_map[permission] ||= begin 
          roles_with_permission = []

          clerk_permissions_map.keys.each do |key|
            if clerk_permissions_map[key].include?(permission)
              roles_with_permission << key
            end
          end

          roles_with_permission
        end 
      end

      def clerk_roles_scope
        class_name = self.name
        ->{ where(scope_class: class_name) }
      end
    end
  end
end
