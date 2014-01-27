module Orchestrator
    module Device
        module Mixin
            include ::Orchestrator::Core::Mixin

            def send(data, options = {}, &blk)
                options[:data] = data
                options[:defer] = @__config__.thread.defer
                options[:on_receive] = blk if blk     # on command success
                @__config__.thread.schedule do
                    @__config__.processor.queue_command(options)
                end
                options[:defer].promise
            end

            def disconnect
                @__config__.thread.schedule do
                    @__config__.connection.disconnect
                end
            end

            def config(options)
                @__config__.thread.schedule do
                    @__config__.processor.config = options
                end
            end

            def defaults(options)
                @__config__.thread.schedule do
                    @__config__.processor.send_options(options)
                end
            end
        end
    end
end
