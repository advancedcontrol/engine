
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
                # It is possible that module start will fail
                # TODO:: deal with case where module not loaded?
                #  Would have to be a class load fail?
                mod = lookup_module
                if mod
                    mod.thread.next_tick do
                        if mod.start
                            env['async.callback'].call([200, {'Content-Length' => 0}, []])
                        else
                            env['async.callback'].call([500, {'Content-Length' => 0}, []])
                        end
                    end
                    throw :async
                end
            end

            def stop
                # Stop will always succeed
                mod = lookup_module
                if mod
                    mod.thread.next_tick do
                        mod.stop
                    end
                    render nothing: true
                end
            end

            def status
                mod = lookup_module
                if mod
                    render json: mod.status[params.permit(:status)[:status].to_sym]
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

            def lookup_module
                mod = control.loaded? id
                if mod
                    return mod
                else
                    render nothing: true, status: :not_found
                end
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @mod = ::Orchestrator::Module.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
