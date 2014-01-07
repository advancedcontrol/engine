
module Orchestrator
    module Device
        class TcpConnection < ::UV::OutboundConnection
            # Config:
            # * update_status: mark device as connected or disconnected
            # * tokenize: use to break stream into tokens (see ::UV::BufferedTokenizer options)
            # * 


            def post_init(manager, processor, tls)
                @manager = manager
                @processor = processor
                @config = @processor.config
                @tls = tls
                @retries = 0
                @connecting = nil
            end

            def on_connect(transport)
                use_tls(@config) if @tls

                # TODO:: need a slightly better way to do this
                # Like a next tick that we can cancel
                @connecting = @manager.get_scheduler.in(0.1) do
                    @connecting = nil

                    # We only have to mark a queue online if more than 1 retry was required
                    if @retries > 1
                        @processor.queue.online
                    end
                    @retries = 0
                    @processor.connected
                end
            end

            def on_close
                # Prevent re-connect if terminated
                @processor.disconnected if @retries == 0
                unless @terminated
                    @retries += 1

                    @connecting.cancel if @connecting
                    @connecting = nil

                    if @retries == 1
                        reconnect
                    else
                        @connecting = @manager.get_scheduler.in(3) do
                            @connecting = nil
                            reconnect
                        end

                        # we mark the queue as offline if more than 1 reconnect fails
                        if @retries == 2
                            @processor.queue.offline(@config[:clear_queue_on_disconnect])
                        end
                    end
                end
            end

            def on_read(data, *args)
                @processor.buffer(data)
            end

            def terminate
                @terminated = true
                close_connection(:after_writing) if @transport.connected
                @connecting.cancel if @connecting
            end
        end
    end
end
