module Orchestrator
    module Logic
        class Manager
            def initialize(thread, klass, settings)
                @thread = thread        # Libuv Loop
                @settings = settings    # Database model
                @klass = klass
                
                # Bit of a hack - should make testing pretty easy though
                config = self
                @instance = @klass.new
                @instance.instance_eval { @__config__ = config }
            end


            attr_reader :thread


            def stop
                begin
                    @instance.on_unload
                ensure
                    @scheduler.clear if @scheduler
                end
            end

            def start
                @instance.on_load
            end

            def reloaded
                @instance.on_update
            end

            def schedule
                @scheduler ||= ScheduleProxy.new(@thread)
            end
        end
    end
end
