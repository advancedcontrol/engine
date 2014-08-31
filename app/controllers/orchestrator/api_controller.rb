
module Orchestrator
    class ApiController < ::AcaEngineBase
        layout nil
        rescue_from Couchbase::Error::NotFound, with: :entry_not_found


        # Add headers to allow for CORS requests to the API
        before_filter :allow_cors


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

        def allow_cors
            headers[ALLOW_ORIGIN] = ANY_ORIGIN
            headers[ALLOW_METHODS] = ANY_METHOD
            headers[ALLOW_HEADERS] = COMMON_HEADERS
            headers[MAX_AGE] = ONE_DAY
        end
        
    
        # Couchbase catch all
        def entry_not_found
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

        # Access to the control system controller
        def control
            @@__control__ ||= ::Orchestrator::Control.instance
        end
    end
end
