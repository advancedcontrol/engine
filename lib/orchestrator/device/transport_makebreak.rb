
module Orchestrator
    module Device
        class MakebreakConnection < ::UV::OutboundConnection
            def post_init(manager, processor, tls)
                @manager = manager
                @processor = processor
                @config = @processor.config
                @tls = tls

                @connected = false
                @changing_state = true


                @activity = nil     # Activity timer
                @connecting = nil   # Connection timer
                @retries = 2        # Connection retries
                @write_queue = []

                @timeout = method(:timeout)
                @reset_timeout = method(:reset_timeout)
            end

            def transmit(cmd)
                return if @terminated

                data = cmd[:data]

                if @connected
                    write(data)
                    reset_timeout
                elsif @retries < 2
                    @write_queue << data
                    reconnect
                end
                # discards data when officially disconnected
            end

            def on_connect(transport)
                @connected = true
                @changing_state = false

                if @terminated
                    close_connection(:after_writing)
                else
                    begin
                        use_tls(@config) if @tls
                    rescue Exception => e
                        @manager.logger.print_error(e, 'error starting tls')
                    end

                    # Write pending directly
                    while @write_queue.length > 0
                        write(@write_queue.shift)
                    end

                    # Notify module
                    if @retries > 1
                        @processor.queue.online
                        @processor.connected
                    end
                    @retries = 0

                    # Start inactivity timeout
                    reset_timeout
                end
            end

            def on_close
                @connected = false
                @changing_state = false

                # Prevent re-connect if terminated
                unless @terminated
                    @retries += 1

                    @activity.cancel if @activity
                    @activity = nil

                    if @retries == 1
                        if @write_queue.length > 0
                            # We reconnect here as there are pending writes
                            reconnect
                        end
                    else # retries > 1
                        @write_queue.clear

                        variation = 1 + rand(2000)
                        @connecting = @manager.get_scheduler.in(3000 + variation) do
                            @connecting = nil
                            reconnect
                        end

                        # we mark the queue as offline if more than 1 reconnect fails
                        if @retries == 2
                            @processor.disconnected
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
                @connecting.cancel if @connecting
                @activity.cancel if @activity
                close_connection(:after_writing) if @transport.connected
            end


            protected


            def timeout(*args)
                @activity = nil
                disconnect
            end

            def reset_timeout
                return if @terminated

                if @activity
                    @activity.cancel
                    @activity = nil
                end

                timeout = @config[:inactivity_timeout] || 0
                if timeout > 0
                    @activity = @manager.get_scheduler.in(timeout, @timeout)
                else # Wait for until queue complete
                    waiting = @processor.queue.waiting
                    if waiting
                        if waiting[:makebreak_set].nil?
                            waiting[:defer].promise.finally @reset_timeout
                            waiting[:makebreak_set] = true
                        end
                    elsif @processor.queue.length == 0
                        disconnect
                    end
                end
            end

            def disconnect
                @connected = false
                @changing_state = true
                close_connection(:after_writing)
            end

            def reconnect
                return if @changing_state || @connected
                @changing_state = true
                super
            end
        end
    end
end
