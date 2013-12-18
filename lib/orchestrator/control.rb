require 'set'


module Orchestrator
    class Control
        include Singleton

        #
        #
        # 1. Load the modules allocated to this node
        # 2. Allocate modules to CPUs
        #    * Modules load dependencies as required
        #    * Logics are streamed in after devices and services
        #
        # Logic modules will fetch their system when they interact with other modules.
        #  Devices and services do not have a system associated with them
        # This makes systems very loosely coupled to the modules
        #  which should make distributing the system slightly simpler
        #
        # TODO:: we should have a general broadcast service
        #

        def initialize
            # critical sections
            @critical = ::Mutex.new
            @loaded = ::ThreadSafe::Cache.new
            @loader = DependencyLoader.instance
            @loop = ::Libuv::Loop.default

            # Don't auto-load if running in the console
            if not defined?(Rails::Console)
                mount
                @server.loaded.then method(:boot)
            end
        end

        # Start the control reactor
        def mount
            return if @server

            @critical.synchronize {
                return if @server   # Protect against multiple mounts
                @server = ::SpiderGazelle::Spider.instance
                @server.loaded.then do
                    # Share threads with SpiderGazelle (one per core)
                    if @server.mode == :thread
                        @threads = @server.threads
                    else    # We are either running no_ipc or process (unsupported for control)
                        @threads = Set.new
                        @exceptions = method(:log_unhandled_exception)

                        cpus = ::Libuv.cpu_count || 1
                        cpus.times &method(:start_thread)
                    end
                end
                @selector = @threads.cycle
            }
        end

        # Boot the control system, running all defined modules
        def boot(*args)
            # Only boot if running as a server
            Thread.new &method(:load_all)
        end

        # Load the modules on the loop references in round robin
        # This method is thread safe.
        def load(mod_settings)
            defer = @loop.defer
            mod = @loaded[mod_id.to_sym]
            if mod
                defer.resolve(mod)
            else
                defer.resolve(
                    @loader.load(mod_settings.dependency.class_name).then(proc { |klass|
                        # We will always be on the default loop here
                        thread = @selector.next

                        # We'll resolve the promise if the module loads on the deferred thread
                        defer = @loop.defer
                        thread.schedule do
                            defer.resolve(start_module(thread, klass, mod_settings))
                        end
                        defer.promise
                    })
                )
            end
            defer.promise
        end

        # Checks if a module with the ID specified is loaded
        def loaded?(mod_id)
            @loaded[mod_id.to_sym]
        end

        def update(mod_id)
            # Stop the module gracefully
            # Remove it from @loaded
            # Get a fresh version of the settings from the database
            # load the module
        end

        def stop(mod_id)

        end


        protected


        # This will always be called on the thread reactor here
        def start_module(thread, klass, settings)
            # TODO:: 
            # Initialize the connection / logic / service handler here
            # We need a special case for UDP devices
            defer = thread.defer

            case settings.dependency.role
            when :device
                if settings.udp
                    # Load UDP device here
                else
                    # Load TCP device here
                end
            when :service
                # Load HTTP client here
            else
                # Load logic module here
            end

            defer.promise
        end


        # Grab the modules from the database and load them
        def load_all
            modules = ::Orchestrator::Module.all
            modules.each &method(:load)  # modules are streamed in
        end




        ##
        # Methods called when we manage the threads:
        def start_thread
            thread = Libuv::Loop.new
            @threads << thread
            Thread.new do
                thread.run do |promise|
                    promise.progress @exceptions
                end
            end
        end

        # TODO:: Should use spider gazelle exception handler here
        def log_unhandled_exception(*args)
            p "unhandled exception #{args}"
        end
    end
end
