require 'set'


module Orchestrator

    class Edge
        def initialize(edge_ip, thread)
            @thread = thread
            @ip = edge_ip

            reconnect
        end


        attr_reader :thread


        def exec()

        end


        protected


        def reconnect
            
        end
    end
end
