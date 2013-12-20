module Orchestrator
    module Logic
        class Manager < ::Orchestrator::Core::ModuleManager
            def initialize(*args)
                super(*args)

                start
            end

            def system
                @system ||= ::Orchestrator::Core::SystemProxy.new(@thread, @settings.control_system_id)
            end
        end
    end
end
