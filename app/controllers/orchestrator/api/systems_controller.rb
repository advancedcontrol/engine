
module Orchestrator
    module Api
        class SystemsController < ApiController
            respond_to :json
            # TODO:: check_authenticated should be in ApiController
            #before_action :check_authenticated, only: [:create, :update, :destroy]
            before_action :check_authorization, only: [:show, :update, :destroy, :start, :stop]


            def index
                # TODO:: Elastic search filter
            end

            def show
                respond_with @cs
            end

            def update
                @cs.update_attributes(safe_params)
                save_and_respond(@cs) do
                   # delete system cache on success
                   System.expire(@cs.id)
                end
            end

            def create
                cs = ControlSystem.new(safe_params)
                save_and_respond cs
            end

            def destroy
                @cs.delete
                System.expire(@cs.id)
                render :nothing => true
            end


            ##
            # Additional Functions:
            ##

            def start
                # Start all modules in the system
                @cs.modules.each do |mod_id|
                    load_and_start mod_id
                end
                render :nothing => true
            end

            def stop
                # Stop all modules in the system
                # TODO:: should only stop modules that are not shared
                @cs.modules.each do |mod_id|
                    mod = control.loaded? mod_id
                    if mod
                        mod.thread.next_tick do
                            mod.stop
                        end
                    end
                end
                render :nothing => true
            end

            def request
                # Run a function in a system module (async request)
            end

            def status
                # Status defined as a system module
                sys = System.get(id)
                if sys
                    para = safe_status
                    index = para[:index]
                    mod = sys.get(para[:module].to_sym, index.nil? ? 0 : index.to_sym)
                    if mod
                        render json: mod.status[para[:status].to_sym]
                    else
                        render json: nil
                    end
                else
                    render nothing: true, status: :not_found
                end
            end


            protected


            def safe_params
                params.require(:control_system).permit(
                    :name, :description, :disabled,
                    {zones: []}, {modules: []},
                    {settings: []}
                )
            end

            def safe_status
                params.permit(:module, :index, :status)
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @cs = ControlSystem.find(id)

                # Does the current user have permission to perform the current action?
            end

            def load_and_start(mod_id)
                mod = control.loaded? mod_id
                if mod
                    mod.thread.next_tick do
                        mod.start
                    end
                else # attempt to load module
                    config = ::Orchestrator::Module.find(mod_id)
                    control.load(config).then(
                        proc { |mod|
                            mod.thread.next_tick do
                                mod.start
                            end
                        }
                    )
                end
            end
        end
    end
end
