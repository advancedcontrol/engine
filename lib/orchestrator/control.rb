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
            @ready_defer = @loop.defer
            @ready_promise = @ready_defer.promise
            @ready_promise.then do
                @ready = true
            end

            # We keep track of unloaded modules so we can optimise loading them again
            @unloaded = Set.new

            if Rails.env.production? && ENV['ORC_NO_BOOT'].nil?
                logger = ::Logger.new(::Rails.root.join('log/control.log').to_s, 10, 4194304)
            else
                logger = ::Logger.new(STDOUT)
            end
            logger.formatter = proc { |severity, datetime, progname, msg|
                "#{datetime.strftime("%d/%m/%Y @ %I:%M%p")} #{severity}: #{msg}\n"
            }
            @logger = ::ActiveSupport::TaggedLogging.new(logger)
        end


        attr_reader :logger, :loop, :ready, :ready_promise, :zones, :threads


        # Start the control reactor
        def mount
            return @server.loaded if @server
            promise = nil

            @critical.synchronize {
                return if @server   # Protect against multiple mounts

                # Cache all the zones in the system
                ::Orchestrator::Zone.all.each do |zone|
                    @zones[zone.id] = zone
                end

                @server = ::SpiderGazelle::Spider.instance
                promise = @server.loaded.then do
                    # Share threads with SpiderGazelle (one per core)
                    if @server.in_mode? :thread
                        start_watchdog
                        @threads = @server.threads
                        @threads.each do |thread|
                            thread.schedule do
                                attach_watchdog(thread)
                            end
                        end
                    else    # We are either running no_ipc or process (unsupported for control)
                        @threads = Set.new

                        cpus = ::Libuv.cpu_count || 1
                        start_watchdog
                        cpus.times &method(:start_thread)

                        @loop.signal :INT, method(:kill_workers)
                    end

                    @selector = @threads.cycle
                end
            }

            return promise
        end

        # Boot the control system, running all defined modules
        def boot(*args)
            # Only boot if running as a server
            Thread.new &method(:load_all)
        end

        # Load a zone that might have been missed or added manually
        # The database etc
        # This function is thread safe
        def load_zone(zone_id)
            defer = @loop.defer
            @loop.schedule do   
                @loop.work do
                    @critical.synchronize {
                        zone = @zones[zone.id]
                        defer.resolve(zone) if zone

                        tries = 0
                        begin
                            zone = ::Orchestrator::Zone.find(zone_id)
                            @zones[zone.id] = zone
                            defer.resolve(zone)
                        rescue Couchbase::Error::NotFound => e
                            defer.reject(zone_id)
                        rescue => e
                            if tries <= 2
                                sleep 1
                                tries += 1
                                retry
                            else
                                defer.reject(e)
                            end
                        end
                    }
                end
            end
            defer.promise
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

                            # Transfer any existing observers over to the new thread
                            if @ready && @unloaded.include?(mod_id)
                                @unloaded.delete(mod_id)
                                
                                @threads.each do |thr|
                                    thr.observer.move(mod_id, thread)
                                end
                            end

                            # Return the manager
                            mod_manager
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
            mod = mod_id.to_sym
            stop(mod).then(proc {
                @unloaded << mod
                @loaded.delete(mod)
                true # promise response
            })
        end

        # Unload then
        # Get a fresh version of the settings from the database
        # load the module
        def update(mod_id)
            mod = loaded?(mod_id)
            running = mod && mod.running

            unload(mod_id).then(proc {
                # Grab database model in the thread pool
                res = @loop.work do
                    ::Orchestrator::Module.find(mod_id)
                end

                # Load the module if model found
                res.then(proc { |config|
                    # Promise chaining to here
                    promise = load(config)

                    if running
                        promise.then(proc { |mod_man|
                            mod.thread.schedule do
                                mod.start
                            end
                        })
                    end

                    promise
                })
            })
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

        def load_triggers_for(system)
            return if loaded?(system.id)

            thread = @selector.next
            thread.schedule do
                mod = Triggers::Manager.new(thread, ::Orchestrator::Triggers::Module, system)
                @loaded[system.id.to_sym] = mod  # NOTE:: Threadsafe
                mod.start
            end
        end


        protected


        def notify_ready
            # Clear the system cache (in case it has been populated at all)
            System.clear_cache
            @ready_defer.resolve(true)

            # these are invisible to the system - never make it into the system cache
            @loop.work do
                load_all_triggers 
            end

            # Save a statistics snapshot every 5min
            stats_method = method(:log_stats)
            @loop.scheduler.every(300_000) do
                @loop.work stats_method
            end
        end


        def log_stats(*args)
            Orchestrator::Stats.new.save
        rescue => e
            @logger.warn "exception saving statistics #{e.message}"
        end


        # These run like regular modules
        # This function is always run from the thread pool
        # Batch loads the system triggers on to the main thread
        def load_all_triggers
            defer = @loop.defer
            begin
                systems = ControlSystem.all.to_a
                @loop.schedule do
                    systems.each do |sys|
                        load_triggers_for sys
                    end
                    defer.resolve true
                end
            rescue => e
                @logger.warn "exception starting triggers #{e.message}"
                sleep 1  # Give it a bit of time
                retry
            end
            defer.promise
        end

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
            ::Libuv::Q.finally(@loop, *loading).finally do
                load_all_triggers.then do
                    notify_ready
                end
            end
        end



        ##
        # Methods called when we manage the threads:
        def start_thread(num)
            thread = Libuv::Loop.new
            @threads << thread

            Thread.new do
                thread.run do |promise|
                    promise.progress @exceptions

                    attach_watchdog thread
                end
            end
        end

        def attach_watchdog(thread)
            @watchdog.schedule do
                @last_seen[thread] = @watchdog.now
            end

            thread.scheduler.every 1000 do
                @watchdog.schedule do
                    @last_seen[thread] = @watchdog.now
                end
            end
        end

        # Monitors threads to make sure they continue to checkin
        # If a thread is hung then we log what it happening
        # If it still doesn't checked in then we raise an exception
        # If it still doesn't checkin then we shutdown
        def start_watchdog
            thread = Libuv::Loop.new
            @last_seen = {}
            @watching = {}

            Thread.new do
                thread.run do |promise|
                    promise.progress @exceptions

                    thread.scheduler.every 2000 do
                        check_threads
                    end
                end
            end
            @watchdog = thread
        end

        def check_threads
            now = @watchdog.now

            @threads.each do |thread|
                difference = now - (@last_seen[thread] || 0)
                thr_actual = nil

                if difference > 2000
                    # we want to start logging
                    thr_actual = thread.reactor_thread
                    
                    if difference > 4000
                        if @watching[thread]
                            thr_actual = @watching.delete thread
                            thr_actual.set_trace_func nil
                        end

                        @logger.warn "WATCHDOG PERFORMING CPR"
                        thr_actual.raise Error::WatchdogResuscitation.new("thread failed to checkin, performing CPR")

                        # Kill the process if the system is unresponsive
                        if difference > 6000
                            @logger.fatal "SYSTEM UNRESPONSIVE - FORCING SHUTDOWN"
                            kill_workers
                            exit!
                        end
                    else
                        if @watching[thread].nil?
                            @logger.warn "WATCHDOG ACTIVATED"

                            @watching[thread] = thr_actual

                            thr_actual.set_trace_func proc { |event, file, line, id, binding, classname|
                                watchdog_trace(event, file, line, id, binding, classname)
                            }
                        end
                    end

                elsif @watching[thread]
                    thr_actual = @watching.delete thread
                    thr_actual.set_trace_func nil
                end
            end
        end

        TraceEvents = ['line', 'call', 'return', 'raise']
        def watchdog_trace(event, file, line, id, binding, classname)
            if TraceEvents.include?(event)
                @logger.info "tracing #{event} from line #{line} in #{file}"
            end
        end
        # =================
        # END WATCHDOG CODE
        # =================


        def kill_workers(*args)
            @threads.each do |thread|
                thread.stop
            end
            @watchdog.stop if @watchdog
            @loop.stop
        end
    end
end
