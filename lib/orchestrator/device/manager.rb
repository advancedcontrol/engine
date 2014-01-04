module Orchestrator
    module Device
        class Manager < ::Orchestrator::Core::ModuleManager
            def initialize(*args)
                super(*args)

                #
                # Load UV-Rays abstraction here
                @connection = 

                # Do we want to start here?
                # Should be ok.
                @thread.next_tick method(:start)
            end

            # Access to other modules in the same control system
            def system
                @system ||= ::Orchestrator::Core::SystemProxy.new(@thread, @settings.control_system_id)
            end

            def notify_connected
                if @instance.respond_to? :connected
                    begin
                        @instance.connected
                    rescue Exeption => e
                        @logger.print_error(e, 'error in module connected callback')
                    end
                end
            end

            def notify_disconnected
                if @instance.respond_to? :disconnected
                    begin
                        @instance.disconnected
                    rescue Exeption => e
                        @logger.print_error(e, 'error in module disconnected callback')
                    end
                end
            end
        end
    end
end
