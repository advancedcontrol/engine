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
            @nodes = ::ThreadSafe::Cache.new
            @loader = DependencyManager.instance
            @loop = ::Libuv::Loop.default
            @exceptions = method(:log_unhandled_exception)

            @ready = false
            @ready_defer = @loop.defer
            @ready_promise = @ready_defer.promise
            @ready_promise.then do
                @ready = true
            end

            if Rails.env.production?
                logger = ::Logger.new(::Rails.root.join('log/control.log').to_s, 10, 4194304)
            else
                logger = ::Logger.new(STDOUT)
            end
            logger.formatter = proc { |severity, datetime, progname, msg|
                "#{datetime.strftime("%d/%m/%Y @ %I:%M%p")} #{severity}: #{msg}\n"
            }
            @logger = ::ActiveSupport::TaggedLogging.new(logger)
        end


        attr_reader :logger, :loop, :ready, :ready_promise, :zones, :nodes, :threads, :selector


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
                        @threads = @server.threads
                    else    # We are either running no_ipc or process (unsupported for control)
                        @threads = []

                        cpus = ::Libuv.cpu_count || 1
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
        def load(id, do_proxy = true)
            mod_id = id.to_sym
            defer = @loop.defer

            mod = @loaded[mod_id]
            if mod
                defer.resolve(mod)
            else
                # Grab database model in the thread pool
                res = @loop.work do
                    tries = 0
                    begin
                        ::Orchestrator::Module.find_by_id(mod_id)
                    rescue => e
                        tries += 1
                        sleep 0.2
                        retry if tries < 3
                        raise e
                    end
                end

                # Load the module if model found
                res.then do |config|
                    if config
                        edge = @nodes[config.edge_id.to_sym]
                        result = edge.update(config)

                        if do_proxy && result
                            result.then do |mod|
                                remote = mod.remote_node
                                remote.load(mod_id) if remote
                            end
                        end
                    end
                end
            end

            defer.promise
        end

        # Checks if a module with the ID specified is loaded
        def loaded?(mod_id)
            @loaded[mod_id.to_sym]
        end

        def get_node(edge_id)
            @nodes[edge_id.to_sym]
        end

        # Starts a module running
        def start(mod_id, do_proxy = true)
            defer = @loop.defer

            mod = loaded? mod_id
            if mod
                if do_proxy
                    remote = mod.remote_node
                    if remote
                        @loop.schedule do
                            remote.stop mod_id
                        end
                    end
                end

                mod.thread.schedule do
                    mod.start
                    defer.resolve(mod)
                end
            else
                err = Error::ModuleNotFound.new "unable to start module '#{mod_id}', not found"
                defer.reject(err)
                @logger.warn err.message
            end

            defer.promise
        end

        # Stops a module running
        def stop(mod_id, do_proxy = true)
            defer = @loop.defer

            mod = loaded? mod_id
            if mod
                if do_proxy
                    remote = mod.remote_node
                    if remote
                        @loop.schedule do
                            remote.stop mod_id
                        end
                    end
                end

                mod.thread.schedule do
                    mod.stop
                    defer.resolve(mod)
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
        def unload(mod_id, do_proxy = true)
            mod = mod_id.to_sym

            stop(mod, false).then(proc { |mod_man|
                if do_proxy
                    mod_man.remote_node do |remote|
                        remote.unload mod
                    end
                end

                mod_man.local_node.unload(mod)
                mod_man # promise response
            })
        end

        # Unload then
        # Get a fresh version of the settings from the database
        # load the module
        def update(mod_id, do_proxy = true)
            defer = @loop.defer

            unload(mod_id, do_proxy).finally do
                defer.resolve load(mod_id, do_proxy)
            end

            defer.promise
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


        # Grab the modules from the database and load them
        def load_all
            loading = []

            nodes = ::Orchestrator::EdgeControl.all
            nodes.each do |node|
                loading << node.boot(@loaded)
                @nodes[node.id.to_sym] = node
            end

            # Once load is complete we'll accept websockets
            @loop.finally(*loading).finally do
                # Determine if we are the master node (either single master or load balanced masters)
                this_node   = @nodes[Remote::NodeId]
                master_node = @nodes[this_node.node_master_id]
                connect_to_master(this_node, master_node) if master_node

                if master_node.nil? || this_node.is_failover_host || (master_node && master_node.is_failover_host)
                    start_server

                    # Save a statistics snapshot every 5min on the master server
                    @loop.scheduler.every(300_000, method(:log_stats))
                end

                @ready_defer.resolve(true)
            end
        end


        def log_stats(*_)
            @loop.work do
                begin
                    Orchestrator::Stats.new.save
                rescue => e
                    @logger.warn "exception saving statistics #{e.message}"
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

                    thread.signal :INT do
                        thread.stop
                    end
                end
            end
        end

        def kill_workers(*args)
            @loop.stop
        end


        # Edge node connections
        def start_server
            @node_server = Remote::Master.new
        end

        def connect_to_master(this_node, master)
            @connection = ::UV.connect master.host, Remote::SERVER_PORT, Remote::Edge, this_node, master
        end
    end
end
