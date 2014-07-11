
module Orchestrator
    module Service
        class TransportHttp
            def initialize(manager, processor)
                @manager = manager
                @settings = @manager.settings
                @processor = processor

                # Load http endpoint after module has had a chance to update the config
                config = @processor.config
                config[:tls] ||= @settings.tls
                config[:tokenize] = false
                @server = UV::HttpEndpoint.new @settings.uri, config

                @manager.thread.next_tick do
                    # Call connected (we only need to do this once)
                    # We may never be connected, this is just to signal that we are ready
                    @processor.connected
                end
            end

            def transmit(cmd)
                return if @terminated

                @server.request(cmd[:method], cmd).then(
                    proc { |result|
                        # Make sure the request information is always available
                        result[:request] = cmd
                        @processor.buffer(result)
                    },
                    proc { |failure|
                        @server.close_connection
                        @server = UV::HttpEndpoint.new @settings.uri, @processor.config

                        # Fail fast (no point waiting for the timeout)
                        if @processor.queue.waiting #== cmd
                            #@processor.__send__(:resp_failure, failure)
                            @processor.check_next
                        end
                    }
                )
            end

            def terminate
                @terminated = true
                @server.close_connection(:after_writing)
            end
        end
    end
end
