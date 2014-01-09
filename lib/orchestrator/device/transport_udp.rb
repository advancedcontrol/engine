module Orchestrator
    module Device
        class UdpConnection
            def initialize(manager, processor)
                @manager = manager
                @loop = manager.thread
                @processor = processor

                settings = manager.settings
                @ip = settings.ip
                @port = settings.port
                @on_read = method(:on_read)

                # One per loop unless port specified
                @udp_server = @loop.udp_service
                @udp_server.attach(@ip, @port, @on_read)

                @loop.next_tick do
                    # Call connected (we only need to do this once)
                    @processor.connected
                end
            end

            def write(data)
                @udp_server.send(@ip, @port, data)
            end

            def on_read(data)
                # We schedule as UDP server may be on a different thread
                @loop.schedule do
                    @processor.buffer(data)
                end
            end

            def terminate
                #@processor.disconnected   # Disconnect should never be called
                @udp_server.detach(@ip, @port)
            end
        end
    end
end
