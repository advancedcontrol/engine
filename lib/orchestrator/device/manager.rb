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
                @connection = if @settings.udp
                    UdpConnection.new(self, @processor)
                elsif @settings.makebreak
                    ::UV.connect(@settings.ip, @settings.port, MakebreakConnection, self, @processor, @settings.tls)
                else
                    ::UV.connect(@settings.ip, @settings.port, TcpConnection, self, @processor, @settings.tls)
                end

                @processor.transport = @connection
            end

            def stop
                super
                @processor.terminate
                @processor = nil
                @connection.terminate
                @connection = nil
            end

            def notify_connected
                if @instance.respond_to? :connected, true
                    begin
                        @instance.__send__(:connected)
                    rescue => e
                        @logger.print_error(e, 'error in module connected callback')
                    end
                end
            end

            def notify_disconnected
                if @instance.respond_to? :disconnected, true
                    begin
                        @instance.__send__(:disconnected)
                    rescue => e
                        @logger.print_error(e, 'error in module disconnected callback')
                    end
                end
            end

            def notify_received(data, resolve, command = nil)
                @thread.next_tick do
                    begin
                        blk = command.nil? ? nil : command[:on_receive]
                        resp = if blk.respond_to? :call
                            blk.call(data, resolve, command)
                        elsif @instance.respond_to? :received, true
                            @instance.__send__(:received, data, resolve, command)
                        else
                            @logger.warn('no received function provided')
                            :abort
                        end
                        resolve.call(resp)
                    rescue => e
                        resolve.call(:abort)
                        @logger.print_error(e, 'error in received callback')
                    end
                end
            end
        end
    end
end
