module Orchestrator
    module Logic
        class Manager < ::Orchestrator::Core::ModuleManager
            def initialize(*args)
                super(*args)

                # Do we want to start here?
                # Should be ok.
                @thread.next_tick method(:start)
            end

            # Access to other modules in the same control system
            def system(user = nil)
                ::Orchestrator::Core::SystemProxy.new(@thread, @settings.control_system_id, nil, user)
            end
        end
    end
end
