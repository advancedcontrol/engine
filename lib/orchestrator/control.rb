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
            @loader = DependencyManager.instance
            @loop = ::Libuv::Loop.default
            @exceptions = method(:log_unhandled_exception)
        end

        # Start the control reactor
        def mount
            return @server.loaded if @server

            @critical.synchronize {
                return if @server   # Protect against multiple mounts
                @server = ::SpiderGazelle::Spider.instance
                @server.loaded.then do
                    # Share threads with SpiderGazelle (one per core)
                    if @server.mode == :thread
                        @threads = @server.threads
                    else    # We are either running no_ipc or process (unsupported for control)
                        @threads = Set.new

                        cpus = ::Libuv.cpu_count || 1
                        cpus.times &method(:start_thread)
                    end

                    @selector = @threads.cycle
                end
            }

            return @server.loaded
        end

        # Boot the control system, running all defined modules
        def boot(*args)
            # Only boot if running as a server
            Thread.new &method(:load_all)
        end

        # Load the modules on the loop references in round robin
        # This method is thread safe.
        def load(mod_settings)
            mod_id = mod_settings.id.to_sym
            defer = @loop.defer
            mod = @loaded[mod_id]

            if mod
                defer.resolve(mod)
            else
                defer.resolve(
                    @loader.load(mod_settings.dependency).then(proc { |klass|
                        # We will always be on the default loop here
                        thread = @selector.next

                        # We'll resolve the promise if the module loads on the deferred thread
                        defer = @loop.defer
                        thread.schedule do
                            defer.resolve(start_module(thread, klass, mod_settings))
                        end

                        # update the module cache
                        defer.promise.then do |mod_manager|
                            @loaded[mod_id] = mod_manager
                        end
                        defer.promise
                    }, @exceptions)
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
            case settings.dependency.role
            when :device
                Device::Manager.new(thread, klass, settings)
            when :service
                Service::Manager.new(thread, klass, settings)
            else
                Logic::Manager.new(thread, klass, settings)
            end
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
            if args[0].respond_to? :backtrace
                puts "unhandled exception: #{args[0]}\n #{args[0].backtrace}"
            else
                puts "unhandled exception: #{args}"
            end
        end
    end
end
