
module Orchestrator
    module Api
        class DependenciesController < ApiController
            respond_to :json
            # TODO:: check_authenticated should be in ApiController
            #before_action :check_authenticated, only: [:create, :update, :destroy]
            before_action :check_authorization, only: [:show, :update, :destroy]


            def index
                # TODO:: Elastic search filter
            end

            def show
                respond_with @dep
            end

            def update
                # TODO:: limit updates to settings?
                # Must destroy and re-add to maintain state
                @dep.update_attributes(safe_params)
                save_and_respond @dep
            end

            def create
                dep = Dependency.new(safe_params)
                save_and_respond dep
            end

            def destroy
                @dep.delete
                # TODO:: delete modules that are based on this dependency
                render :nothing => true
            end


            ##
            # Additional Functions:
            ##

            def reload
                
            end


            protected


            def safe_params
                params.require(:dependency).permit(
                    :name, :description, :role,
                    :class_name, :module_name,
                    {settings: []}
                )
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @dep = Dependency.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
