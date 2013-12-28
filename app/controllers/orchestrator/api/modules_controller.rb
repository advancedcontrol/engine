
module Orchestrator
    module Api
        class ModulesController < ApiController
            respond_to :json
            # TODO:: check_authenticated should be in ApiController
            #before_action :check_authenticated, only: [:create, :update, :destroy]
            before_action :check_authorization, only: [:show, :update, :destroy]


            def index
                if params[:system_id]
                    # TODO:: Should use cs.modules as the elastic search filter
                    cs = ControlSystem.find(params.permit(:system_id)[:system_id])
                    render json: ::Orchestrator::Module.find_by_id(cs.modules)
                else
                    # TODO:: Elastic search
                    render json: []
                end
            end

            def show
                respond_with @mod
            end

            def update
                @mod.update_attributes(safe_params)
                save_and_respond @mod
            end

            def create
                mod = ::Orchestrator::Module.new(safe_params)
                save_and_respond mod
            end

            def destroy
                @mod.delete
                head :ok
            end


            ##
            # Additional Functions:
            ##

            def start

            end

            def stop

            end

            def status
                ctrl = ::Orchestrator::Control.instance
                mod = ctrl.loaded? id
                if mod
                    render json: mod.status[params.permit(:status)[:status].to_sym]
                else
                    render nothing: true, status: :not_found
                end
            end


            protected


            def safe_params
                params.require(:module).permit(
                    :dependency_id, :control_system_id,
                    :ip, :tls, :udp, :port, :makebreak,
                    :uri, {settings: []}
                )
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @mod = ::Orchestrator::Module.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
