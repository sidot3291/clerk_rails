# We're not including this in clerk-rails/app/helpers because it is injected
# into ActionController::Base via initializes/add_application_helpers and cannot be in the autoload path
# https://stackoverflow.com/questions/29636334/a-copy-of-xxx-has-been-removed-from-the-module-tree-but-is-still-active
module ClerkRails
  module Helpers
    module View
    end

    module Controller
      def authenticate_account!
        if account_signed_in?
          if !current_account.verified_email_address
            redirect_to verify_email_address_url and return
          end
        else
          redirect_to sign_in_url and return
        end
      end
    end

    module ViewAndController
      def account_signed_in?
        !current_account.nil?
      end

      def current_account
        @clerk_current_account ||= begin
          if cookies[:clerk_session] || cookies[:__session]
            Clerk::SessionToken.find_account(
              cookie: cookies[:clerk_session] || cookies[:__session]
            )
          else
            nil
          end
        end
      end     
    end
  end
end
