
module Orchestrator
    module Api
        class GroupsController < ApiController
            respond_to :json
            # TODO:: check_authenticated should be in ApiController
            #before_action :check_authenticated, only: [:create, :update, :destroy]
            before_action :check_authorization, only: [:show, :update, :destroy]


            def index
                # TODO:: Elastic search filter
            end

            def show
                respond_with @group
            end

            def update
                @group.update_attributes(safe_params)
                save_and_respond @group
            end

            def create
                group = Group.new(safe_params)
                save_and_respond group
            end

            def destroy
                @group.delete
                head :ok
            end


            protected


            def safe_params
                params.require(:group).permit(
                    :name, :description, :clearance
                )
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @group = Group.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
