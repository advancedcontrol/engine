
module Orchestrator
    module Device
        class TcpConnection < ::UV::OutboundConnection
            include Device::Connection


            # Config:
            # * update_status: mark device as connected or disconnected
            # * tokenize: use to break stream into tokens (see ::UV::BufferedTokenizer options)
            # * 


            def post_init(processor, settings, config)
                @processor = processor
                @config = config
                @tls = @settings.tls
            end

            def on_connect(transport)
                use_tls(@config) if @tls
                @processor.connected
            end

            def on_close
                @processor.disconnected
            end

            def on_read(data, *args)
                @processor.buffer(data)
            end
        end
    end
end
