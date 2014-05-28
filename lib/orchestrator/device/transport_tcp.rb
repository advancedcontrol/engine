
module Orchestrator
    module Device
        class TcpConnection < ::UV::OutboundConnection
            def post_init(manager, processor, tls)
                @manager = manager
                @processor = processor
                @config = @processor.config
                @tls = tls

                # Delay retry by default if connection fails on load
                @retries = 1        # Connection retries
                @connecting = nil   # Connection timer

                # Last retry shouldn't break any thresholds
                @last_retry = @processor.thread.now - 50000
            end

            def transmit(cmd)
                return if @terminated
                promise = write(cmd[:data])
                if cmd[:wait]
                    promise.catch do |err|
                        if @processor.queue.waiting == cmd
                            # Fail fast
                            @processor.thread.next_tick do
                                @processor.__send__(:resp_failure, err)
                            end
                        else
                            cmd[:defer].reject(err)
                        end
                    end
                end
            end

            def on_connect(transport)
                if @terminated
                    close_connection(:after_writing)
                else
                    begin
                        use_tls(@config) if @tls
                    rescue => e
                        @manager.logger.print_error(e, 'error starting tls')
                    end

                    if @config[:wait_ready]
                        @delaying = ''
                    else
                        init_connection
                    end
                end
            end

            def on_close
                unless @terminated
                    # Clear the connection delay if in use
                    @delaying = false if @delaying
                    @retries += 1
                    the_time = @processor.thread.now
                    boundry = @last_retry + @config[:thrashing_threshold]

                    # ensure we are not thrashing (rapid connect then disconnect)
                    # This equals a disconnect and requires a warning
                    if @retries == 1 && boundry >= the_time
                        @retries += 1
                        @manager.logger.warn('possible connection thrashing. Disconnecting')
                    end

                    if @retries == 1
                        @last_retry = the_time
                        @processor.disconnected
                        reconnect
                    else
                        variation = 1 + rand(2000)
                        @connecting = @manager.get_scheduler.in(3000 + variation) do
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
                if @delaying
                    @delaying << data
                    result = @delaying.split(@config[:wait_ready], 2)
                    if result.length > 1
                        @delaying = false
                        init_connection
                        rem = result[-1]
                        @processor.buffer(rem) unless rem.empty?
                    end
                else
                    @processor.buffer(data)
                end
            end

            def terminate
                @terminated = true
                @connecting.cancel if @connecting
                close_connection(:after_writing) if @transport.connected
            end

            def disconnect
                # Shutdown quickly
                close_connection
            end


            protected


            def init_connection
                # Enable keep alive every 30 seconds
                keepalive(30)

                # We only have to mark a queue online if more than 1 retry was required
                if @retries > 1
                    @processor.queue.online
                end
                @retries = 0
                @processor.connected
            end
        end
    end
end
