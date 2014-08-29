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

                @updating = Mutex.new
            end


            attr_reader :thread, :settings, :instance
            attr_reader :status, :stattrak, :logger


            # Should always be called on the module thread
            def stop
                return if @instance.nil?
                begin
                    if @instance.respond_to? :on_unload, true
                        @instance.__send__(:on_unload)
                    end
                rescue => e
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
                    update_running_status(false)
                end
            end

            def start
                return true unless @instance.nil?
                config = self
                @instance = @klass.new
                @instance.instance_eval { @__config__ = config }
                if @instance.respond_to? :on_load, true
                    begin
                        @instance.__send__(:on_load)
                    rescue => e
                        @logger.print_error(e, 'error in module load callback')
                    end
                end
                update_running_status(true)
                true # for REST API
            rescue => e
                @logger.print_error(e, 'module failed to start')
                false
            end

            def reloaded
                if @instance.respond_to? :on_update, true
                    @thread.schedule do
                        begin
                            @instance.__send__(:on_update)
                        rescue => e
                            @logger.print_error(e, 'error in module update callback')
                        end
                    end
                end
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

            # Called from Core::Mixin on any thread
            #
            # Settings updates are done on the thread pool
            # We have to replace the structure as other threads may be
            # reading from the old structure and the settings hash is not
            # thread safe
            def define_setting(name, value)
                defer = thread.defer
                thread.schedule do
                    defer.resolve(thread.work(proc {
                        mod = Orchestrator::Module.find(@settings.id)
                        mod.settings[name] = value
                        mod.save!
                        mod
                    }))
                end
                defer.promise.then do |db_model|
                    @settings = db_model
                    value # Don't leak direct access to the database model
                end
            end


            # override the default inspect method
            # This provides relevant information and won't blow the stack on an error
            def inspect
                "#<#{self.class}:0x#{self.__id__.to_s(16)} @thread=#{@thread.inspect} running=#{!@instance.nil?} managing=#{@klass.to_s} id=#{@settings.id}>"
            end


            protected


            def update_connected_status(connected)
                id = settings.id

                # Access the database in a non-blocking fashion
                thread.work(proc {
                    @updating.synchronize {
                        model = ::Orchestrator::Module.find_by_id id

                        if model && model.connected != connected
                            model.connected = connected
                            model.save!
                            model
                        else
                            nil
                        end
                    }
                }).then(proc { |model|
                    # Update the model if it was updated
                    if model
                        @settings = model
                    end
                }, proc { |e|
                    # report any errors updating the model
                    @logger.print_error(e, 'error updating connected state in database model')
                })
            end

            def update_running_status(running)
                id = settings.id

                # Access the database in a non-blocking fashion
                thread.work(proc {
                    @updating.synchronize {
                        model = ::Orchestrator::Module.find_by_id id

                        if model && model.running != running
                            model.running = running
                            model.connected = false if !running
                            model.save!
                            model
                        else
                            nil
                        end
                    }
                }).then(proc { |model|
                    # Update the model if it was updated
                    if model
                        @settings = model
                    end
                }, proc { |e|
                    # report any errors updating the model
                    @logger.print_error(e, 'error updating running state in database model')
                })
            end
        end
    end
end
