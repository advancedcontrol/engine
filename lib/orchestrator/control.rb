
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
            @server = SpiderGazelle::Spider.instance
            @server.loaded.then do
                # Share threads with SpiderGazelle (one per core)
                @threads = @server.threads
                Thread.new &method(:boot)
            end
        end


        # Load the modules on the loop references in round robin
        def load(mod)
            # TODO (this method should be thread safe)
            # Not going to run on a reactor thread
        end


        protected


        # Grab the modules from the database and load them
        def boot
            modules = ::Orchestrator::Module.all
            modules.each &method(:load)  # modules are streamed in
        end
    end
end
