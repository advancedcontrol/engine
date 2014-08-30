
module Orchestrator
    module Api
        class SystemsController < ApiController
            respond_to :json
            #doorkeeper_for :all
            before_action :check_authorization, only: [:show, :update, :destroy, :remove, :start, :stop]


            @@elastic ||= Elastic.new(ControlSystem)


            def index
                query = @@elastic.query(params)
                query.sort = [{name: "asc"}]

                # Filter systems via zone_id
                if params.has_key? :zone_id
                    zone_id = params.permit(:zone_id)[:zone_id]
                    query.filter({
                        zones: [zone_id]
                    })
                end

                # filter via module_id
                if params.has_key? :module_id
                    module_id = params.permit(:module_id)[:module_id]
                    query.filter({
                        modules: [module_id]
                    })
                end

                respond_with @@elastic.search(query)
            end

            def show
                if params.has_key? :complete
                    respond_with @cs, {
                        methods: [:module_data, :zone_data]
                    }
                else
                    respond_with @cs
                end
            end

            def update
                @cs.update_attributes(safe_params)
                save_and_respond(@cs) # save deletes the system cache
            end

            # Removes the module from the system and deletes it if not used elsewhere
            def remove
                module_id = params.permit(:module_id)[:module_id]
                mod = ::Orchestrator::Module.find module_id

                if @cs.modules.include? module_id
                    remove = true

                    @cs.modules.delete(module_id)
                    @cs.save!

                    ControlSystem.using_module(module_id).each do |cs|
                        if cs.id != @cs.id
                            remove = false
                            break
                        end
                    end

                    mod.delete if remove
                end
                render :nothing => true
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
                        mod.thread.schedule do
                            perform_exec(mod, para)
                        end
                        throw :async
                    else
                        render nothing: true, status: :not_found
                    end
                else
                    render nothing: true, status: :not_found
                end
            end

            def state
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

            # returns a list of functions available to call
            def funcs
                params.require(:module)
                sys = System.get(id)
                if sys
                    para = params.permit(:module, :index)
                    index = para[:index]
                    index = index.nil? ? 0 : (index.to_i - 1);

                    mod = sys.get(para[:module].to_sym, index)
                    if mod
                        funcs = mod.instance.public_methods(false)
                        priv = []
                        funcs.each do |func|
                            if ::Orchestrator::Core::PROTECTED[func]
                                priv << func
                            end
                        end
                        render json: (funcs - priv)
                    else
                        render nothing: true, status: :not_found
                    end
                else
                    render nothing: true, status: :not_found
                end
            end


            protected


            # Better performance as don't need to create the object each time
            CS_PARAMS = [
                :name, :description, :support_url,
                {
                    zones: [],
                    modules: []
                }
            ]
            # We need to support an arbitrary settings hash so have to
            # work around safe params as per 
            # http://guides.rubyonrails.org/action_controller_overview.html#outside-the-scope-of-strong-parameters
            def safe_params
                settings = params[:settings]
                {
                    modules: [],
                    zones: [],
                    settings: settings.is_a?(::Hash) ? settings : {}
                }.merge(params.permit(CS_PARAMS))
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                sys = ::Orchestrator::ControlSystem.bucket.get("sysname-#{id}", {quiet: true}) || id
                @cs = ControlSystem.find(sys)

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

            # Called on the module thread
            def perform_exec(mod, para)
                defer = mod.thread.defer

                req = Core::RequestProxy.new(mod.thread, mod)
                args = para[:args] || []
                result = req.send(para[:method].to_sym, *args)

                # timeout in case message is queued
                timeout = mod.thread.scheduler.in(5000) do
                    defer.resolve('Wait time exceeded. Command may have been queued.')
                end

                result.finally do
                    timeout.cancel # if we have our answer
                    defer.resolve(result)
                end

                defer.promise.then(proc { |res|
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
            end
        end
    end
end
