require 'securerandom'
require 'thread'


module Orchestrator
    class EdgeControl < Couchbase::Model
        design_document :edge
        include ::CouchbaseId::Generator

        LocalNodeId = ENV['ENGINE_NODE_ID'].freeze


        StartOrder = Struct.new(:device, :logic, :trigger) do
            def initialize(logger, *args)
                @logger = logger
                super *args
                self.device  ||= []
                self.logic   ||= []
                self.trigger ||= []
            end

            def add(mod_man)
                array = get_type mod_man.settings
                array << mod_man
            end

            def remove(mod_man)
                array = get_type mod_man.settings
                result = array.delete mod_man

                if result.nil?
                    @logger.warn "Slow module removal requested"

                    id = mod_man.settings.id
                    array.delete_if {|mod| mod.settings.id == id }
                end
            end

            def reverse_each
                groups = [self.trigger, self.logic, self.device]
                groups.each do |mods|
                    mods.reverse_each {|mod| yield mod }
                end
            end


            protected


            def get_type(settings)
                type = if settings.respond_to? :role
                    settings.role < 3 ? :device : :logic
                else
                    :trigger
                end
                __send__(type)
            end
        end


        # Engine requires this ENV var to be set for identifying self
        # * ENGINE_EDGE_ID (Can obtain master ID from this)
        # * ENGINE_EDGE_SLAVE = true (multiple slaves, single master, true == slave)
        #
        # Operations:
        # - Request function call
        # - Request status variable
        # - Request repo pull (optional commit specified)
        # - Push: module start / stop / reload
        # - Push: module unload / load (module may be moved to another edge)
        # - Push: module status information
        # - Push: service restart (complete an update)
        # - Push: status variable information to master
        #


        # Note::
        # During any outage, the edge node does not update the database
        # - On recovery the master node will send a list of actions that
        # - have been missed by the edge node. The edge node can process them
        # - then once processed it can request control again.



        # Optional master edge node
        # Allows for multi-master systems versus pure master-slave
        belongs_to :master, class_name: 'Orchestrator::EdgeControl'


        attribute :name
        attribute :host_origin  # Control UI's need this for secure cross domain connections
        attribute :description

        # Used to validate the connection is from a trusted edge node
        attribute :password,    default: lambda { SecureRandom.hex }

        attribute :failover,    default: true     # should the master take over if this location goes down
        attribute :timeout,     default: 20000   # Failover timeout, how long before we act on the failure? (20seconds default)
        attribute :window_start   # CRON string for recovery windows (restoring edge control after failure)
        attribute :window_length  # Time in seconds

        # Status variables
        attribute :online,          default: true
        attribute :failover_active, default: false

        attribute :settings,    default: lambda { {} }
        attribute :admins,      default: lambda { [] }

        attribute :created_at,  default: lambda { Time.now.to_i }


        def self.all
            all_edges(stale: false)
        end
        view :all_edges


        attr_reader :proxy
        def node_connected(proxy)
            @proxy = proxy
            restore_from_failover
        end

        def node_disconnected
            @proxy = nil
            failover_as_required
        end


        def host
            @host ||= self.host_origin.split('//')[-1]
            @host
        end

        def should_run_on_this_host
            @run_here ||= LocalNodeId == self.id
            @run_here
        end

        def is_failover_host
            @fail_here ||= LocalNodeId == self.master_id
            @fail_here
        end

        def host_active?
            (should_run_on_this_host && online) || (is_failover_host && failover_active)
        end

        def boot(all_systems)
            init
            defer = @thread.defer

            # Don't load anything if this host doesn't have anything to do
            # with the modules in this node
            if !(should_run_on_this_host || is_failover_host)
                defer.resolve true
                return defer.promise
            end

            @global_cache = all_systems
            @loaded = ::ThreadSafe::Cache.new
            @start_order = StartOrder.new @logger

            loading = []
            modules.each do |mod|
                loading << load(mod)
            end

            # Mark system as ready
            defer.resolve load_triggers

            # Clear the system cache
            defer.promise.then do
                @boot_complete = true
                System.clear_cache
            end

            defer.promise
        end


        # Used to transfer control to a newer instance of an edge
        def reloaded(all_systems, loaded, order)
            init

            @global_cache = all_systems
            @loaded = loaded
            @start_order = order
        end


        # Soft start and stop modules (no database updates)
        def start_modules
            wait_start(@start_order.device).then do
                wait_start(@start_order.logic).then do
                    wait_start(@start_order.trigger)
                end
            end
        end

        def stop_modules
            stopping = []

            @start_order.reverse_each do |mod_man|
                defer = @thread.defer
                stopping << defer.promise

                mod_man.thread.schedule do
                    mod_man.stop_local
                    defer.resolve(true)
                end
            end

            @thread.finally(*stopping)
        end


        # Load the modules on the thread references in round robin
        # This method is thread safe.
        def load(mod_settings)
            mod_id = mod_settings.id.to_sym
            defer = @thread.defer
            mod = @loaded[mod_id]

            if mod
                defer.resolve(mod)
            else
                defer.resolve(
                    @loader.load(mod_settings.dependency).then(proc { |klass|
                        # We will always be on the default thread here
                        thread = @control.selector.next

                        # We'll resolve the promise if the module loads on the deferred thread
                        defer = @thread.defer
                        thread.schedule do
                            defer.resolve init_manager(thread, klass, mod_settings)
                        end

                        # update the module cache
                        defer.promise.then do |mod_manager|
                            @loaded[mod_id] = mod_manager
                            @global_cache[mod_id] = mod_manager
                            @start_order.add mod_manager

                            # Transfer any existing observers over to the new thread
                            # We do this for all modules after boot is complete as
                            # Observers can exist before modules are instantiated
                            if @boot_complete
                                new_thread = thread.observer
                                @threads.each do |thr|
                                    thr.observer.move(mod_id, new_thread)
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

        # Symbol input
        def unload(mod_id)
            @global_cache.delete(mod_id)
            mod = @loaded.delete(mod_id)
            @start_order.remove(mod) if mod
        end

        # This is only called from control.
        # The module should not be running at this time
        # TODO:: Should employ some kind of locking (possible race condition here)
        def update(settings)
            # Eager load dependency data whilst not on the reactor thread
            mod_id = settings.id.to_sym

            # Start, stop, unload the module as required
            if should_run_on_this_host || is_failover_host
                return load(settings).then do |mod|
                    mod.start_local if host_active?
                    mod
                end
            end

            nil
        end

        # Returns the list of modules that should be running on this node
        def modules
            Module.on_node(self.id)
        end

        def load_triggers_for(system)
            sys_id = system.id.to_sym
            return if @loaded[sys_id]

            defer = @thread.defer

            thread = @control.selector.next
            thread.schedule do
                mod = Triggers::Manager.new(thread, Triggers::Module, system)
                @loaded[sys_id] = mod  # NOTE:: Threadsafe
                mod.start if @boot_complete && host_active?

                defer.resolve(mod)
            end

            defer.promise.then do |mod_man|
                # Keep track of the order
                @start_order.trigger << mod_man
            end

            defer.promise
        end


        protected


        # When this class is used for managing modules we need access to these classes
        def init
            @thread = ::Libuv::Loop.default
            @loader = DependencyManager.instance
            @control = Control.instance
            @logger = ::SpiderGazelle::Logger.instance
        end

        # Used to stagger the starting of different types of modules
        def wait_start(modules)
            starting = []

            modules.each do |mod_man|
                defer = @thread.defer
                starting << defer.promise
                mod_man.thread.schedule do
                    mod_man.start_local
                    defer.resolve(true)
                end
            end

            # Once load is complete we'll accept websockets
            @thread.finally(*starting)
        end

        # This will always be called on the thread reactor
        def init_manager(thread, klass, settings)
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


        def load_triggers
            defer = @thread.defer

            # these are invisible to the system - never make it into the system cache
            result = @thread.work method(:load_trig_system_info)
            result.then do |systems|
                wait_loading = []
                systems.each do |sys|
                    prom = load_triggers_for sys
                    wait_loading << prom if prom
                end

                defer.resolve(@thread.finally(wait_loading))
            end

            # TODO:: Catch trigger load failure

            defer.promise
        end

        # These run like regular modules
        # This function is always run from the thread pool
        # Batch loads the system triggers on to the main thread
        def load_trig_system_info
            begin
                systems = []
                ControlSystem.on_node(self.id).each do |cs|
                    systems << cs
                end
                systems
            rescue => e
                @logger.warn "exception starting triggers #{e.message}"
                sleep 1  # Give it a bit of time
                retry
            end
        end

        def restore_from_failover
            p "RESTORE FROM FAILOVER REQUESTED - not implemented"
        end

        def failover_as_required
            p "FAILOVER REQUESTED - not implemented"
        end
    end
end
