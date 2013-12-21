module Orchestrator
    module Core
        module Mixin
            def schedule
                @__config__.schedule
            end

            def systems(name)
                # TODO:: need to be able to look up systems via name or id
            end

            def task(callback = nil, &block)
                @__config__.thread.work(callback, &block)
            end

            def status
                # TODO:: need to be able to save status variables
            end

            def subscribe(mod, status = nil, &callback)
                # TODO:: need a subscription service
            end

            def unsubscribe(subscription)
                
            end
        end
    end
end
