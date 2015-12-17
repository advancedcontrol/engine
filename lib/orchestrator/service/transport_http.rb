
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

                # TODO:: Support multiple simultaneous requests (multiple servers)

                # Log the requests
                @manager.logger.debug {
                    "requesting #{cmd[:method]}: #{@settings.uri}#{cmd[:path]}"
                }

                request = @server.request(cmd[:method], cmd)
                request.then(
                    proc { |result|
                        # Make sure the request information is always available
                        result[:request] = cmd
                        @processor.buffer(result)

                        @manager.logger.debug {
                            msg = "success #{cmd[:method]}: #{@settings.uri}#{cmd[:path]}\n"
                            msg << "result: #{result}"
                            msg
                        }

                        nil
                    },
                    proc { |failure|
                        @manager.logger.debug {
                            msg = "failed #{cmd[:method]}: #{@settings.uri}#{cmd[:path]}\n"
                            msg << "req headers: #{cmd[:headers]}\n"
                            msg << "req body: #{cmd[:body]}\n"
                            msg << "result: #{failure}"
                            msg
                        }

                        nil
                    }
                )

                defer = @manager.thread.defer
                defer.resolve(true)
                defer.promise
            end

            def terminate
                @terminated = true
                @server.close_connection(:after_writing)
            end

            def disconnect
                @server.close_connection
            end
        end
    end
end
