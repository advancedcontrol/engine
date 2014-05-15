
module Orchestrator
    module Api
        class SystemsController < ApiController
            respond_to :json
            #doorkeeper_for :all
            before_action :check_authorization, only: [:show, :update, :destroy, :start, :stop]


            @@elastic ||= Elastic.new('sys')


            def index
                query = @@elastic.query(params)
                results = @@elastic.search(query)

                # TODO:: Filter by zone-id
                # Requires some experimentation

                # Find by id doesn't raise errors
                respond_with ControlSystem.find_by_id(results) || results
            end

            def show
                respond_with @cs
            end

            def update
                @cs.update_attributes(safe_params)
                save_and_respond(@cs) # save deletes the system cache
            end

            def create
                cs = ControlSystem.new(safe_params)
                save_and_respond cs
            end

            def destroy
                @cs.delete # expires the cache in after callback
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
                # Stop all modules in the system (shared or not)
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

            def exec
                # Run a function in a system module (async request)
                params.require(:module)
                params.require(:method)
                sys = System.get(id)
                if sys
                    para = params.permit(:module, :index, :method, {args: []}).tap do |whitelist|
                        whitelist[:args] = params[:args]
                    end
                    index = para[:index]
                    mod = sys.get(para[:module].to_sym, index.nil? ? 0 : (index.to_i - 1))
                    if mod
                        req = Core::RequestProxy.new(mod.thread, mod)
                        args = para[:args] || []
                        result = req.send(para[:method].to_sym, *args)
                        result.then(proc { |res|
                            output = ''
                            begin
                                output = ::JSON.generate([res])
                            rescue Exception => e
                                # respond with nil if object cannot be converted
                                # TODO:: need a better way of dealing with this
                                # ALSO in websocket manager
                            end
                            env['async.callback'].call([200, {
                                'Content-Length' => output.bytesize,
                                'Content-Type' => 'application/json'
                            }, [output]])
                        }, proc { |err|
                            output = err.message
                            env['async.callback'].call([500, {
                                'Content-Length' => output.bytesize,
                                'Content-Type' => 'text/plain'
                            }, [output]])
                        })
                        throw :async
                    else
                        render nothing: true, status: :not_found
                    end
                else
                    render nothing: true, status: :not_found
                end
            end

            def status
                # Status defined as a system module
                params.require(:module)
                params.require(:lookup)
                sys = System.get(id)
                if sys
                    para = params.permit(:module, :index, :lookup)
                    index = para[:index]
                    mod = sys.get(para[:module].to_sym, index.nil? ? 0 : (index.to_i - 1))
                    if mod
                        render json: mod.status[para[:lookup].to_sym]
                    else
                        render nothing: true, status: :not_found
                    end
                else
                    render nothing: true, status: :not_found
                end
            end


            protected


            def safe_params
                params.require(:control_system).permit(
                    :name, :description, :disabled,
                    {
                        zones: [],
                        modules: [],
                        settings: []
                    }
                )
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
