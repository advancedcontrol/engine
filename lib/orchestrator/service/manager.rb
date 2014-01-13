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
                @processor = nil
                @connection.terminate
                @connection = nil
            end

            # NOTE:: Same as Device::Manager:-------

            def notify_connected
                if @instance.respond_to? :connected, true
                    begin
                        @instance.__send__(:connected)
                    rescue Exception => e
                        @logger.print_error(e, 'error in module connected callback')
                    end
                end
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
                rescue Exception => e
                    @logger.print_error(e, 'error in received callback')
                end
            end
        end
    end
end
