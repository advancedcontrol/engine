
module Orchestrator
    class ApiController < ApplicationController
        layout nil
        rescue_from Couchbase::Error::NotFound, :with => :entry_not_found


        protected
    
    
        # Couchbase catch all
        def entry_not_found
            render :nothing => true, :status => :not_found  # 404
        end

        # Helper for extracting the id from the request
        def id
            return @id if @id
            params.require(:id)
            @id = params.permit(:id)[:id]
        end

        # Used to save and respond to all model requests
        def save_and_respond(model)
            if model.save
                yield if block_given?
                respond_with :api, model
            else
                render json: model.errors, status: :bad_request
            end
        end

        # Access to the control system controller
        def control
            @@__control__ ||= ::Orchestrator::Control.instance
        end
    end
end
