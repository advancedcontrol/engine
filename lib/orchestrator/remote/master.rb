require 'uv-rays'
require 'json'
require 'set'


module Orchestrator
    module Remote
        SERVER_PORT = 17400

        Connection = Struct.new(:tokeniser, :parser, :node_id, :timeout, :io, :poll) do
            def validated?
                !!self.node_id
            end
        end

        ParserSettings = {
            indicator: "\x02",
            delimiter: "\x03"
        }

        class Master

            def initialize
                @thread = ::Libuv::Loop.default
                @logger = ::SpiderGazelle::Logger.instance
                @ctrl = ::Orchestrator::Control.instance
                @dep_man = ::Orchestrator::DependencyManager.instance

                @connections = {}

                @tokenise = method(:tokenise)
                @node = @ctrl.nodes[NodeId]

                start_server
            end


            attr_reader :thread

            
            protected


            def start_server
                # Bind the socket
                @tcp = @thread.tcp
                @tcp.bind '0.0.0.0'.freeze, SERVER_PORT, @new_connection
                @tcp.listen 64 # smallish backlog is all we need

                # Delegate errors
                @tcp.catch @bind_error
                @tcp

                @logger.info "Node server on tcp://0.0.0.0:#{SERVER_PORT}"
            end

            def new_connection(client)
                # Build the connection object
                connection = Connection.new
                @connections[client.object_id] = connection

                connection.timeout = @thread.scheduler.in(15000) do
                    # Shutdown connection if validation doesn't occur within 15 seconds
                    client.close
                end
                connection.tokeniser = ::UV::BufferedTokenizer.new(ParserSettings)
                connection.io = client


                connection.poll = @thread.scheduler.every(60000) do
                    client.write "\x02ping\x03".freeze
                end


                # Hook up the connection callbacks
                client.enable_nodelay
                client.catch do |error|
                    @logger.print_error(error, "Node connection error")
                end

                client.finally do
                    @connections.delete client.object_id
                    connection.poll.cancel

                    if connection.validated?
                        edge = @ctrl.nodes[connection.node_id]

                        # We may not have noticed the disconnect
                        edge.node_disconnected if edge.proxy == connection.parser
                    else
                        connection.timeout.cancel
                    end
                end

                client.progress @tokenise

                # This is an encrypted connection
                client.start_tls(server: true)
                client.start_read
            end

            def tokenise(data, client)
                connection = @connections[client.object_id]
                connection.tokeniser.extract(data).each do |msg|
                    process connection, msg
                end
            end


            DECODE_OPTIONS = {
                symbolize_names: true
            }.freeze

            def process(connection, msg)
                # Connection Maintenance
                return if msg[0] == 'p'.freeze

                if connection.validated?
                    begin
                        connection.parser.process ::JSON.parse(msg, DECODE_OPTIONS)
                    rescue => e
                        # TODO:: Log the error here
                    end
                else
                    # Will send an auth message: node_id password
                    node_str, pass = msg.split(' '.freeze)
                    node_id = node_str.to_sym
                    edge = @ctrl.nodes[node_id]
                    if edge.password == pass
                        connection.timeout.cancel
                        connection.timeout = nil
                        connection.node_id = node_id
                        connection.parser = Proxy.new(@ctrl, @dep_man, connection.io)

                        connection.io.write "\x02hello #{@node.password}\x03"
                        edge.node_connected connection.parser
                    else
                        ip, _ = transport.peername
                        client.close
                        @logger.warn "Connection from #{ip} was closed due to bad credentials"
                    end
                end
            end
        end
    end
end
