module Orchestrator
    module Core
        class ModuleManager
            def initialize(thread, klass, settings)
                @thread = thread        # Libuv Loop
                @settings = settings    # Database model
                @klass = klass
                
                # Bit of a hack - should make testing pretty easy though
                config = self
                @instance = @klass.new
                @instance.instance_eval { @__config__ = config }
                @status = {}
                @stattrak = @thread.observer
            end


            attr_reader :thread, :settings, :instance
            attr_reader :status, :stattrak


            def stop
                begin
                    @instance.on_unload
                ensure
                    @scheduler.clear if @scheduler
                end
            end

            def start
                @instance.on_load
            end

            def reloaded
                @instance.on_update
            end

            # This is called from Core::Mixin on the thread pool as the DB query will be blocking
            # NOTE:: Couchbase does support non-blocking gets although I think this is simpler
            #
            # @return [::Orchestrator::Core::SystemProxy]
            # @raise [Couchbase::Error::NotFound] if unable to find the system in the DB
            def get_system(name)
                id = ::Orchestrator::ControlSystem.bucket.get("sysname-#{name}")
                ::Orchestrator::Core::SystemProxy.new(@thread, id.to_sym)
            end

            # Called from Core::Mixin
            def trak(name, value)
                unless @status[name] == value
                    @status[name] = value
                    @stattrak.update(@settings.id.to_sym, name, value)
                end
            end

            # Subscribe to status updates from status in the same module
            # Called from Core::Mixin
            def subscribe(status, callback)
                raise 'callback required' unless callback.respond_to? :call
                @stattrak.subscribe({
                    callback: callback,
                    status: status.to_sym,
                    mod_id: @settings.id.to_sym
                })
            end
        end
    end
end
