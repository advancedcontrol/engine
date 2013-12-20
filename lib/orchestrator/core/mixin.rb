module Orchestrator
    module Core
        module Mixin
            def schedule
                @__config__.schedule
            end

            def systems(name)
                # TODO:: need to be able to look up systems via name or id
            end
        end
    end
end
