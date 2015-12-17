
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
                @last_retry = 0
            end

            def transmit(cmd)
                return ::Libuv::Q.reject(@processor.thread, :transport_terminated) if @terminated

                # This is the same as MakeBreak
                data = cmd[:data]

                if @config[:before_transmit]
                    begin
                        data = @config[:before_transmit].call(data, cmd)
                    rescue => err
                        @manager.logger.print_error(err, 'error in before_transmit callback')

                        # Don't try and send anything
                        return ::Libuv::Q.reject(@processor.thread, :before_transmit_error)
                    end
                end

                # This returns a promise
                write(data)
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
                        @processor.disconnected
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

                        if @retries == 2
                            # NOTE:: edge case if disconnected on first connect
                            @processor.disconnected if @last_retry == 0

                            # we mark the queue as offline if more than 1 reconnect fails
                            @processor.queue.offline(@config[:clear_queue_on_disconnect])
                        end
                    end
                end
            end

            def on_read(data, *args)
                if @delaying
                    # Update last retry so we don't trigger multiple
                    # calls to disconnected as connection is working
                    @last_retry += 1

                    @delaying << data
                    result = @delaying.split(@config[:wait_ready], 2)
                    if result.length > 1
                        @delaying = false
                        rem = result[-1]
                        @processor.buffer(rem) unless rem.empty?
                        init_connection
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
