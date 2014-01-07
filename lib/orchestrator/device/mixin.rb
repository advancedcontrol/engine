module Orchestrator
    module Device
        module Mixin
            include ::Orchestrator::Core::Mixin

            def send(data, options = {})
                options[:data] = data
                @__config__.processor.queue_command(options)
            end

            def config(options)
                @__config__.processor.config(options)
            end

            def defaults(options)
                @__config__.processor.send_options(options)
            end
        end
    end
end
