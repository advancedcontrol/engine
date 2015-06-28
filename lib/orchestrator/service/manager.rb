module Orchestrator
    module Service
        class Manager < ::Orchestrator::Core::ModuleManager
            def initialize(*args)
                super(*args)

                # Do we want to start here?
                # Should be ok.
                @thread.next_tick method(:start)
            end

            attr_reader :processor, :connection

            def start
                @processor = Orchestrator::Device::Processor.new(self)

                super # Calls on load (allows setting of tls certs)

                @connection = TransportHttp.new(self, @processor)
                @processor.transport = @connection
            end

            def stop
                super
                @processor.terminate
                @processor = nil
                @connection.terminate
                @connection = nil
            end

            def apply_config
                @processor.config = @klass.__default_config(@instance) if @klass.respond_to? :__default_config
                @processor.send_options(@klass.__default_opts(@instance)) if @klass.respond_to? :__default_opts
            end

            # NOTE:: Same as Device::Manager:-------
            # TODO:: Need to have a guess about when a device may be off line

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
                end
            end
        end
    end
end
