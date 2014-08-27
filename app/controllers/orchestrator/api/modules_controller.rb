require 'set'


module Orchestrator
    module Api
        class ModulesController < ApiController
            respond_to :json
            #doorkeeper_for :all
            before_action :check_authorization, only: [:show, :update, :destroy]


            @@elastic ||= Elastic.new(::Orchestrator::Module)


            def index
                filters = params.permit(:system_id, :dependency_id, :connected)

                # if a system id is present we query the database directly
                if filters[:system_id]
                    cs = ControlSystem.find(filters[:system_id])

                    results = ::Orchestrator::Module.find_by_id(cs.modules) || [];
                    render json: {
                        total: results.length,
                        results: results
                    }
                else # we use elastic search
                    query = @@elastic.query(params)

                    if filters[:dependency_id]
                        query.filter({
                            dependency_id: [filters[:dependency_id]]
                        })
                    end

                    if filters[:connected]
                        connected = filters[:connected] == 'true'
                        query.filter({
                            connected: [false]
                        })
                    end

                    results = @@elastic.search(query)

                    # Find by id doesn't raise errors
                    respond_with results, {
                        include: {
                            dependency: {only: [:name, :description, :module_name]},
                            control_system: {only: [:name]}
                        }
                    }
                end
            end

            def show
                respond_with @mod
            end

            def update
                para = safe_params
                @mod.update_attributes(para)
                save_and_respond(@mod) do
                    # Update the running module if anything other than settings is updated
                    if para.keys.size > 2 || para[:settings].nil?
                        control.update(id)
                    end

                    # If custom name is changed we need to expire any system caches
                    if para[:custom_name]
                        ::Orchestrator::ControlSystem.using_module(id).each do |sys|
                            sys.expire_cache
                        end
                    end
                end
            end

            def create
                mod = ::Orchestrator::Module.new(safe_params)
                save_and_respond mod
            end

            def destroy
                control.unload(id)
                @mod.delete
                render nothing: true
            end


            ##
            # Additional Functions:
            ##

            def start
                # It is possible that module class load can fail
                mod = control.loaded? id
                if mod
                    start_module(mod)
                else # attempt to load module
                    config = ::Orchestrator::Module.find(mod_id)
                    control.load(config).then(
                        proc { |mod|
                            start_module mod
                        },
                        proc { # Load failed
                            env['async.callback'].call([500, {'Content-Length' => 0}, []])
                        }
                    )
                end
                throw :async
            end

            def stop
                # Stop will always succeed
                lookup_module do |mod|
                    mod.thread.next_tick do
                        mod.stop
                    end
                    render nothing: true
                end
            end

            def status
                lookup_module do |mod|
                    render json: mod.status[params.permit(:lookup)[:lookup].to_sym]
                end
            end


            protected


            MOD_PARAMS = [
                :dependency_id, :control_system_id,
                :ip, :tls, :udp, :port, :makebreak,
                :uri, :custom_name
            ]
            def safe_params
                settings = params[:settings]
                {
                    settings: settings.is_a?(::Hash) ? settings : {}
                }.merge(params.permit(MOD_PARAMS))
            end

            def lookup_module
                mod = control.loaded? id
                if mod
                    yield mod
                else
                    render nothing: true, status: :not_found
                end
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @mod = ::Orchestrator::Module.find(id)

                # Does the current user have permission to perform the current action?
            end

            def start_module(mod)
                mod.thread.next_tick do
                    if mod.start
                        env['async.callback'].call([200, {'Content-Length' => 0}, []])
                    else
                        env['async.callback'].call([500, {'Content-Length' => 0}, []])
                    end
                end
            end
        end
    end
end
