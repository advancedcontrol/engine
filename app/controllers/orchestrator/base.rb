
module Orchestrator
    class Base < ::ActionController::Base
        layout nil
        rescue_from Couchbase::Error::NotFound, with: :entry_not_found


        before_action :doorkeeper_authorize!, except: :options
        before_filter :allow_cors  # Add headers to allow for CORS requests to the API


        # This is a preflight OPTIONS request
        def options
            render nothing: true
        end


        protected


        # Don't keep re-creating these objects for every request
        ALLOW_ORIGIN = 'Access-Control-Allow-Origin'.freeze
        ALLOW_METHODS = 'Access-Control-Allow-Methods'.freeze
        ALLOW_HEADERS = 'Access-Control-Allow-Headers'.freeze
        MAX_AGE = 'Access-Control-Max-Age'.freeze
        ANY_ORIGIN = '*'.freeze
        ANY_METHOD = 'GET, POST, PUT, DELETE, OPTIONS, PATCH'.freeze
        COMMON_HEADERS = 'Origin, Accept, Content-Type, X-Requested-With, Authorization, X-Frame-Options'.freeze
        ONE_DAY = '1728000'.freeze

        def allow_cors(headerHash = headers)
            headerHash[ALLOW_ORIGIN] = ANY_ORIGIN
            headerHash[ALLOW_METHODS] = ANY_METHOD
            headerHash[ALLOW_HEADERS] = COMMON_HEADERS
            headerHash[MAX_AGE] = ONE_DAY
        end
        
    
        # Couchbase catch all
        def entry_not_found(err)
            logger.warn err.message
            logger.warn err.backtrace.join("\n") if err.respond_to?(:backtrace) && err.backtrace
            render nothing: true, status: :not_found  # 404
        end

        # Helper for extracting the id from the request
        def id
            return @id if @id
            params.require(:id)
            @id = params.permit(:id)[:id]
        end

        # Used to save and respond to all model requests
        def save_and_respond(model)
            yield if model.save && block_given?
            respond_with :api, model
        end

        # Checking if the user is an administrator
        def check_admin
            user = current_user
            user && user.sys_admin
        end

        # Checking if the user is support personnel
        def check_support
            user = current_user
            user && (user.support || user.sys_admin)
        end

        # current user using doorkeeper
        def current_user
            @current_user ||= User.find(doorkeeper_token.resource_owner_id) if doorkeeper_token
        end
    end
end
