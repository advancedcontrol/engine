
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
                    promise = write(data)
                    reset_timeout
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
                elsif @retries < 2
                    @write_queue << cmd
                    reconnect
                else
                    cmd[:defer].reject(Error::CommandFailure.new "transmit aborted as disconnected")
                end
                # discards data when officially disconnected
            end

            def on_connect(transport)
                @connected = true
                @changing_state = false

                if @connecting
                    @connecting.cancel
                    @connecting = nil
                end

                if @terminated
                    close_connection(:after_writing)
                else
                    begin
                        use_tls(@config) if @tls
                    rescue Exception => e
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
                @delaying = false if @delaying
                @connected = false
                @changing_state = false

                if @connecting
                    @connecting.cancel
                    @connecting = nil
                end

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
                @activity.cancel if @activity
                close_connection(:after_writing) if @transport.connected
            end

            def disconnect
                @connected = false
                close_connection(:after_writing)
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

            def reconnect
                return if @changing_state || @connected
                @changing_state = true
                super
            end

            def init_connection
                # Write pending directly
                queue = @write_queue
                @write_queue = []
                while queue.length > 0
                    transmit(queue.shift)
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
    end
end
