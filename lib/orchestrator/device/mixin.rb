module Orchestrator
    module Device
        module Mixin
            include ::Orchestrator::Core::Mixin

            def send
                @__connection__.send
            end
        end
    end
end
