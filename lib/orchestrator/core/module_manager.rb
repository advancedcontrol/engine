module Orchestrator
    module Core
        class ModuleManager
            def initialize(thread, klass, settings)
                @thread = thread        # Libuv Loop
                @settings = settings    # Database model
                @klass = klass
                
                # Bit of a hack - should make testing pretty easy though
                @status = ::ThreadSafe::Cache.new
                @stattrak = @thread.observer
                @logger = ::Orchestrator::Logger.new(@thread, @settings)
            end


            attr_reader :thread, :settings, :instance
            attr_reader :status, :stattrak, :logger


            def stop
                return if @instance.nil?
                begin
                    @instance.on_unload
                rescue Exeption => e
                    @logger.print_error(e, 'error in module unload callback')
                ensure
                    # Clean up
                    @instance = nil
                    @scheduler.clear if @scheduler
                    if @subsciptions
                        unsub = @stattrak.method(:unsubscribe)
                        @subsciptions.each &unsub
                        @subsciptions = nil
                    end
                end
            end

            def start
                return unless @instance.nil?
                config = self
                @instance = @klass.new
                @instance.instance_eval { @__config__ = config }
                begin
                    @instance.on_load
                rescue Exeption => e
                    @logger.print_error(e, 'error in module load callback')
                end
                true
            rescue Exeption => e
                @logger.print_error(e, 'module failed to start')
                false
            end

            def reloaded
                @instance.on_update
            end

            def get_scheduler
                @scheduler ||= ::Orchestrator::Core::ScheduleProxy.new(@thread)
            end

            # This is called from Core::Mixin on the thread pool as the DB query will be blocking
            # NOTE:: Couchbase does support non-blocking gets although I think this is simpler
            #
            # @return [::Orchestrator::Core::SystemProxy]
            # @raise [Couchbase::Error::NotFound] if unable to find the system in the DB
            def get_system(name)
                id = ::Orchestrator::ControlSystem.bucket.get("sysname-#{name}")
                ::Orchestrator::Core::SystemProxy.new(@thread, id.to_sym, self)
            end

            # Called from Core::Mixin - thread safe
            def trak(name, value)
                if @status[name] != value
                    @status[name] = value

                    # Allows status to be updated in workers
                    # For the most part this will run straight away
                    @thread.schedule do
                        @stattrak.update(@settings.id.to_sym, name, value)
                    end
                end
            end

            # Subscribe to status updates from status in the same module
            # Called from Core::Mixin always on the module thread
            def subscribe(status, callback)
                sub = @stattrak.subscribe({
                    on_thread: @thread,
                    callback: callback,
                    status: status.to_sym,
                    mod_id: @settings.id.to_sym,
                    mod: self
                })
                add_subscription sub
                sub
            end

            # Called from Core::Mixin always on the module thread
            def unsubscribe(sub)
                if sub.is_a? ::Libuv::Q::Promise
                    # Promise recursion?
                    sub.then method(:unsubscribe)
                else
                    @subsciptions.delete sub
                    @stattrak.unsubscribe(sub)
                end
            end

            # Called from subscribe and SystemProxy.subscribe always on the module thread
            def add_subscription(sub)
                if sub.is_a? ::Libuv::Q::Promise
                    # Promise recursion?
                    sub.then method(:add_subscription)
                else
                    @subsciptions ||= Set.new
                    @subsciptions.add sub
                end
            end

            # Called from Core::Mixin on any thread
            # For Logics: instance -> system -> zones -> dependency
            # For Device: instance -> dependency
            def setting(name)
                res = @settings.settings[name]
                if res.nil?
                    if !@settings.control_system_id.nil?
                        sys = System.get(@settings.control_system_id)
                        res = sys.settings[name]

                        # Check if zones have the setting
                        if res.nil?
                            sys.zones.each do |zone|
                                res = zone.settings[name]
                                return res unless res.nil?
                            end

                            # Fallback to the dependency
                            res = @settings.dependency.settings[name]
                        end
                    else
                        # Fallback to the dependency
                        res = @settings.dependency.settings[name]
                    end
                end
                res
            end
        end
    end
end
