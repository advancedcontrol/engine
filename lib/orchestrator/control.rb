require 'set'
require 'logger'


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
        #

        def initialize
            # critical sections
            @critical = ::Mutex.new
            @loaded = ::ThreadSafe::Cache.new
            @zones = ::ThreadSafe::Cache.new
            @loader = DependencyManager.instance
            @loop = ::Libuv::Loop.default
            @exceptions = method(:log_unhandled_exception)

            @ready = false

            if Rails.env.production?
                logger = ::Logger.new(::Rails.root.join('log/control.log').to_s, 10, 4194304)
            else
                logger = ::Logger.new(STDOUT)
            end
            logger.formatter = proc { |severity, datetime, progname, msg|
                "#{datetime.strftime("%d/%m/%Y @ %I:%M%p")} #{severity}: #{progname} - #{msg}\n"
            }
            @logger = ::ActiveSupport::TaggedLogging.new(logger)
        end


        attr_reader :logger, :loop, :ready, :zones, :threads


        # Start the control reactor
        def mount
            return @server.loaded if @server

            @critical.synchronize {
                return if @server   # Protect against multiple mounts

                # Cache all the zones in the system
                ::Orchestrator::Zone.all.each do |zone|
                    @zones[zone.id] = zone
                end

                @server = ::SpiderGazelle::Spider.instance
                @server.loaded.then do
                    # Share threads with SpiderGazelle (one per core)
                    if @server.mode == :thread
                        @threads = @server.threads
                    else    # We are either running no_ipc or process (unsupported for control)
                        @threads = Set.new

                        cpus = ::Libuv.cpu_count || 1
                        cpus.times &method(:start_thread)

                        @loop.signal :INT, method(:kill_workers)
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

        # Starts a module running
        def start(mod_id)
            defer = @loop.defer

            mod = loaded? mod_id
            if mod
                mod.thread.schedule do
                    mod.start
                    defer.resolve(true)
                end
            else
                err = Error::ModuleNotFound.new "unable to start module '#{mod_id}', not found"
                defer.reject(err)
                @logger.warn err.message
            end

            defer.promise
        end

        # Stops a module running
        def stop(mod_id)
            defer = @loop.defer

            mod = loaded? mod_id
            if mod
                mod.thread.schedule do
                    mod.stop
                    defer.resolve(true)
                end
            else
                err = Error::ModuleNotFound.new "unable to stop module '#{mod_id}', not found"
                defer.reject(err)
                @logger.warn err.message
            end

            defer.promise
        end

        # Stop the module gracefully
        # Then remove it from @loaded
        def unload(mod_id)
            stop(mod_id).then(proc {
                @loaded.delete(mod_id.to_sym)
                true # promise response
            })
        end

        # Unload then
        # Get a fresh version of the settings from the database
        # load the module
        def update(mod_id)
            unload(mod_id).then(proc {
                # Grab database model in the thread pool
                res = @loop.work do
                    ::Orchestrator::Module.find(mod_id)
                end

                # Load the module if model found
                res.then(proc { |config|
                    load(config)    # Promise chaining to here
                })
            })
        end

        def reload(dep_id)
            @loop.work do
                reload_dep(dep_id)
            end
        end

        def notify_ready
            # Clear the system cache (in case it has been populated at all)
            System.clear_cache
            @ready = true
        end

        def log_unhandled_exception(*args)
            msg = ''
            err = args[-1]
            if err && err.respond_to?(:backtrace)
                msg << "exception: #{err.message} (#{args[0..-2]})"
                msg << "\n#{err.backtrace.join("\n")}" if err.respond_to?(:backtrace) && err.backtrace
            else
                msg << "unhandled exception: #{args}"
            end
            @logger.error msg
            ::Libuv::Q.reject(@loop, msg)
        end


        protected


        # This will always be called on the thread reactor here
        def start_module(thread, klass, settings)
            # Initialize the connection / logic / service handler here
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
            loading = []
            wait = nil

            modules = ::Orchestrator::Module.all
            modules.each do |mod|
                if mod.role < 3
                    loading << load(mod)  # modules are streamed in
                else
                    if wait.nil?
                        wait = ::Libuv::Q.finally(@loop, *loading)
                        loading.clear

                        # Clear here in case rest api calls have built the cache
                        System.clear_cache
                    end

                    loading << mod
                end
            end

            # In case there were no logic modules
            if wait.nil?
                wait = ::Libuv::Q.finally(@loop, *loading)
                loading.clear
            end

            # Mark system as ready
            wait.finally do
                continue_loading(loading)
            end
        end

        # Load all the logic modules after the device modules are complete
        def continue_loading(modules)
            loading = []

            modules.each do |mod|
                loading << load(mod)  # grab the load promises
            end

            # Once load is complete we'll accept websockets
            ::Libuv::Q.finally(@loop, *loading).finally method(:notify_ready)
        end



        ##
        # Methods called when we manage the threads:
        def start_thread(num)
            thread = Libuv::Loop.new
            @threads << thread
            Thread.new do
                thread.run do |promise|
                    promise.progress @exceptions

                    thread.async do
                        p 'noop'
                    end
                end
            end
        end

        def kill_workers(*args)
            @threads.each do |thread|
                thread.stop
            end
            @loop.stop
        end
    end
end
