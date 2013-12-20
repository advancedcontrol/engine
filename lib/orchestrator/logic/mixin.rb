module Orchestrator
    module Logic
        module Mixin
            include ::Orchestrator::Core::Mixin

            def system
                @__config__.system
            end
        end
    end
end
