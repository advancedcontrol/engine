require 'set'
require 'json'


module Orchestrator

    class Master
        def initialize(thread)
            @thread = thread

            @accept_connection = method :accept_connection
            @new_connection =    method :new_connection
            @bind_error =        method :bind_error

            @shutdown = true
            @edge_nodes = ::ThreadSafe::Cache.new # id => connection
            @requests   = {} # req_id => defer
            @req_map    = {} # connection => ::Set.new (req_id)

            @signal_bind   = @thread.async method(:bind_actual)
            @signal_unbind = @thread.async method(:unbind_actual)

            @request_id = 0
        end


        attr_reader :thread


        # ping
        # pong
        # exec
        # bind
        # unbind
        # notify
        # status
        # success
        # failure


        def request(edge_id, details)
            defer = @thread.defer

            # Lookup node
            connection = online? id
            if connection
                @thread.schedule do
                    if connection.connected
                        @request_id += 1
                        @requests[@request_id] = defer
                        @req_map[connection] ||= ::Set.new
                        @req_map[connection] << @request_id
                        
                        # Send the request
                        connection.write(::JSON.fast_generate({
                            id: @request_id,

                        })).catch do |reason|
                            on_failure(defer, edge_id, details)
                        end
                    else
                        on_failure(defer, edge_id, details)
                    end
                end
            else
                on_failure(defer, edge_id, details)
            end

            defer.promise
        end

        def online?(id)
            edge = @edge_nodes[id]
            edge && edge.connected ? edge : false
        end

        def unbind
            @signal_unbind.call
        end

        def bind
            @signal_bind.call
        end

        
        protected


        def on_failure(defer, edge_id, details)
            # Failed...
            # Are we loading this device locally or remotely?
            # Do we wait a small amount of time before trying again?
            # When should we fail the request?
        end


        # These are async methods.. They could be called more than once
        def unbind_actual(*args)
            return if @shutdown
            @shutdown = true

            @tcp.close unless @tcp.nil?
            @tcp = nil
        end

        def bind_actual(*args)
            return unless @shutdown
            @shutdown = false

            # Bind the socket
            @tcp = @thread.tcp
            @tcp.bind '0.0.0.0', 17838, @new_connection
            @tcp.listen 100 # smallish backlog is all we need

            # Delegate errors
            @tcp.catch @bind_error
            @tcp
        end


        # There is a new connection pending. We accept it
        def new_connection(server)
            server.accept @accept_connection
        end

        # Once the connection is accepted we disable Nagles Algorithm
        # This improves performance as we are using vectored or scatter/gather IO
        # Then the spider delegates to the gazelle loops
        def accept_connection(client)
            client.enable_nodelay
            # TODO:: auth client and then signal the interested parties
        end

        # Called when binding is closed due to an error
        def bind_error(err)
            return if @shutdown

            # TODO:: log the error

            # Attempt to recover!
            @thread.scheduler.in(1000) do
                bind
            end
        end

        def process_request(defer, node, request)

        end
    end
end
