module Orchestrator
    module Device
        class Manager < ::Orchestrator::Core::ModuleManager
            def initialize(*args)
                super(*args)

                # Do we want to start here?
                # Should be ok.
                @thread.next_tick method(:start)
            end

            attr_reader :processor, :connection

            def start
                @processor = Processor.new(self)

                super # Calls on load (allows setting of tls certs)

                # Load UV-Rays abstraction here
                if @settings.udp
                    # TODO
                    # Next tick call connected
                elsif @settings.makebreak
                    # TODO
                    # Next tick call connected
                    # 2 x disconnected == disconnected
                else
                    @connection = UV.connect(@settings.ip, @settings.port, TcpConnection, self, @processor, @settings.tls)
                end

                @processor.transport = @connection
            end

            def stop
                super
                @processor = nil
                @connection.terminate
                @connection = nil
            end

            def notify_connected
                if @instance.respond_to? :connected, true
                    begin
                        @instance.__send__(:connected)
                    rescue Exception => e
                        @logger.print_error(e, 'error in module connected callback')
                    end
                end
            end

            def notify_disconnected
                if @instance.respond_to? :disconnected, true
                    begin
                        @instance.__send__(:disconnected)
                    rescue Exception => e
                        @logger.print_error(e, 'error in module disconnected callback')
                    end
                end
            end

            def notify_received(data, resolve, command = nil)
                if @instance.respond_to? :received, true
                    begin
                        @instance.__send__(:received, data, resolve, command)
                    rescue Exception => e
                        @logger.print_error(e, 'error in module received callback')
                    end
                end
            end
        end
    end
end
