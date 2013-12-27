
module Orchestrator
    module Api
        class ZonesController < ApiController
            respond_to :json
            # TODO:: check_authenticated should be in ApiController
            #before_action :check_authenticated, only: [:create, :update, :destroy]
            before_action :check_authorization, only: [:show, :update, :destroy]


            def index
                # TODO:: Elastic search filter
            end

            def show
                respond_with @zone
            end

            def update
                @zone.update_attributes(safe_params)
                save_and_respond @zone
            end

            def create
                zone = Zone.new(safe_params)
                save_and_respond zone
            end

            def destroy
                @zone.delete
                head :ok
            end


            protected


            def safe_params
                params.require(:zone).permit(
                    :name, :description,
                    {settings: []}, {groups: []}
                )
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @zone = Zone.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
