require 'set'


module Orchestrator
    class Proxy
        COMMANDS = Set.new([:exec, :bind, :unbind, :debug, :ignore])
        
        def initialize(thread)
            @thread = thread

            @accept_connection = method :accept_connection
            @new_connection =    method :new_connection
            @bind_error =        method :bind_error

            @shutdown = true
            @edge_nodes = ::ThreadSafe::Cache.new # id => connection
            @req_map    = {} # connection => ::Set.new (defers)
            @req_map    = {}

            @signal_bind   = @thread.async method(:bind_actual)
            @signal_unbind = @thread.async method(:unbind_actual)
        end
    end
end
