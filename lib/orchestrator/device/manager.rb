module Orchestrator
    module Device
        class Manager < ::Orchestrator::Core::ModuleManager
            def initialize(*args)
                super(*args)

                # Do we want to start here?
                # Should be ok.
                @thread.next_tick method(:start) if @settings.running
            end

            attr_reader :processor, :connection

            def start
                return true unless @processor.nil?
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
                true # for REST API
            end

            def stop
                super
                @processor.terminate unless @processor.nil?
                @processor = nil
                @connection.terminate unless @connection.nil?
                @connection = nil
            end

            def apply_config
                cfg = @klass.__default_config(@instance) if @klass.respond_to? :__default_config
                opts = @klass.__default_opts(@instance)  if @klass.respond_to? :__default_opts

                if @processor
                    @processor.config = cfg
                    @processor.send_options(opts)
                end
            end

            def notify_connected
                if @instance.respond_to? :connected, true
                    begin
                        @instance.__send__(:connected)
                    rescue => e
                        @logger.print_error(e, 'error in module connected callback')
                    end
                end

                update_connected_status(true)
            end

            def notify_disconnected
                if @instance.respond_to? :disconnected, true
                    begin
                        @instance.__send__(:disconnected)
                    rescue => e
                        @logger.print_error(e, 'error in module disconnected callback')
                    end
                end

                update_connected_status(false)
            end

            def notify_received(data, resolve, command = nil)
                begin
                    blk = command.nil? ? nil : command[:on_receive]
                    if blk.respond_to? :call
                        blk.call(data, resolve, command)
                    elsif @instance.respond_to? :received, true
                        @instance.__send__(:received, data, resolve, command)
                    else
                        @logger.warn('no received function provided')
                        :abort
                    end
                rescue => e
                    @logger.print_error(e, 'error in received callback')
                    return :abort
                end
            end
        end
    end
end
