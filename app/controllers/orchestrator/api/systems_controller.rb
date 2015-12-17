
module Orchestrator
    module Api
        class SystemsController < ApiController
            respond_to :json
            # state, funcs, count and types are available to authenticated users
            before_action :check_admin,   only: [:create, :update, :destroy, :remove, :start, :stop]
            before_action :check_support, only: [:index, :exec]
            before_action :find_system,   only: [:show, :update, :destroy, :remove, :start, :stop]


            @@elastic ||= Elastic.new(ControlSystem)


            def index
                query = @@elastic.query(params)
                query.sort = NAME_SORT_ASC

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

                query.search_field :name
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
                @cs.assign_attributes(safe_params)
                save_and_respond(@cs)
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
                loaded = []

                # Start all modules in the system
                @cs.modules.each do |mod_id|
                    promise = control.start mod_id
                end

                # TODO:: This needs to be done on the remote as well
                # Clear the system cache once the modules are loaded
                # This ensures the cache is accurate
                control.loop.finally(*loaded).then do
                    # Might as well trigger update behaviour.
                    # Ensures logic modules that interact with other logic modules
                    # are accurately informed
                    @cs.expire_cache   # :no_update
                end

                render :nothing => true
            end

            def stop
                # Stop all modules in the system (shared or not)
                @cs.modules.each do |mod_id|
                    control.stop mod_id
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
                        whitelist[:args] = params[:args] || []
                    end
                    index = para[:index]
                    mod = sys.get(para[:module].to_sym, index.nil? ? 0 : (index.to_i - 1))
                    if mod
                        user = current_user
                        mod.thread.schedule do
                            perform_exec(mod, para, user)
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
                sys = System.get(id)
                if sys
                    para = params.permit(:module, :index, :lookup)
                    index = para[:index]
                    mod = sys.get(para[:module].to_sym, index.nil? ? 0 : (index.to_i - 1))
                    if mod
                        if para.has_key?(:lookup)
                            render json: mod.status[para[:lookup].to_sym]
                        else
                            render json: mod.status.marshal_dump
                        end
                    else
                        render nothing: true, status: :not_found
                    end
                else
                    render nothing: true, status: :not_found
                end
            end

            # returns a list of functions available to call
            Ignore = Set.new([
                Object, Kernel, BasicObject,
                Constants, Transcoder,
                Core::Mixin, Logic::Mixin, Device::Mixin, Service::Mixin
            ])
            def funcs
                params.require(:module)
                sys = System.get(id)
                if sys
                    para = params.permit(:module, :index)
                    index = para[:index]
                    index = index.nil? ? 0 : (index.to_i - 1);

                    mod = sys.get(para[:module].to_sym, index)
                    if mod
                        klass = mod.klass

                        # Find all the public methods available for calling
                        # Including those methods from ancestor classes
                        funcs = []
                        klass.ancestors.each do |methods|
                            break if Ignore.include? methods 
                            funcs += methods.public_instance_methods(false)
                        end
                        # Remove protected methods
                        pub = funcs.select { |func| !Core::PROTECTED[func] }

                        # Provide details on the methods
                        resp = {}
                        pub.each do |pfunc|
                            meth = klass.instance_method(pfunc.to_sym)
                            resp[pfunc] = {
                                arity: meth.arity,
                                params: meth.parameters
                            }
                        end

                        render json: resp
                    else
                        render nothing: true, status: :not_found
                    end
                else
                    render nothing: true, status: :not_found
                end
            end

            # return the count of a module type in a system
            def count
                params.require(:module)
                sys = System.get(id)
                if sys
                    mod = params.permit(:module)[:module]
                    render json: {count: sys.count(mod)}
                else
                    render nothing: true, status: :not_found
                end
            end

            # return the list of a module types in a system
            def types
                sys = System.get(id)
                if sys
                    render json: sys.modules
                else
                    render nothing: true, status: :not_found
                end
            end


            protected


            # Better performance as don't need to create the object each time
            CS_PARAMS = [
                :name, :description, :support_url, :installed_ui_devices,
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
                args = {
                    modules: [],
                    zones: [],
                    settings: settings.is_a?(::Hash) ? settings : {}
                }.merge!(params.permit(CS_PARAMS))
                args[:installed_ui_devices] = args[:installed_ui_devices].to_i if args.has_key? :installed_ui_devices
                args
            end

            def find_system
                # Find will raise a 404 (not found) if there is an error
                sys = ::Orchestrator::ControlSystem.bucket.get("sysname-#{id.downcase}", {quiet: true}) || id
                @cs = ControlSystem.find(sys)
            end

            # Called on the module thread
            def perform_exec(mod, para, user)
                defer = mod.thread.defer

                req = Core::RequestProxy.new(mod.thread, mod, user)
                args = para[:args] || []
                result = req.method_missing(para[:method].to_sym, *args)

                # timeout in case message is queued
                timeout = mod.thread.scheduler.in(5000) do
                    defer.resolve('Wait time exceeded. Command may have been queued.')
                end

                result.finally do
                    timeout.cancel # if we have our answer
                    defer.resolve(result)
                end

                respHeaders = {}
                allow_cors(respHeaders)

                defer.promise.then(proc { |res|
                    output = ''
                    begin
                        output = ::JSON.generate([res])
                    rescue Exception => e
                        # respond with nil if object cannot be converted
                        # TODO:: need a better way of dealing with this
                        # ALSO in websocket manager
                    end
                    respHeaders['Content-Length'] = output.bytesize
                    respHeaders['Content-Type'] = 'application/json'
                    env['async.callback'].call([200, respHeaders, [output]])
                }, proc { |err|
                    output = err.message
                    respHeaders['Content-Length'] = output.bytesize
                    respHeaders['Content-Type'] = 'text/plain'
                    env['async.callback'].call([500, respHeaders, [output]])
                })
            end
        end
    end
end
