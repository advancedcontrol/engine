
module Orchestrator
    module Api
        class SystemsController < ApiController
            respond_to :json
            # TODO:: check_authenticated should be in ApiController
            #before_action :check_authenticated, only: [:create, :update, :destroy]
            before_action :check_authorization, only: [:show, :update, :destroy]


            def index
                # TODO:: Elastic search filter
            end

            def show
                respond_with @cs
            end

            def update
                @cs.update_attributes(safe_params)
                save_and_respond @cs
            end

            def create
                cs = ControlSystem.new(safe_params)
                save_and_respond cs
            end

            def destroy
                @cs.delete
                head :ok
            end


            protected


            def safe_params
                params.require(:control_system).permit(
                    :name, :description, :disabled,
                    {zones: []}, {modules: []},
                    {settings: []}
                )
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @cs = ControlSystem.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
