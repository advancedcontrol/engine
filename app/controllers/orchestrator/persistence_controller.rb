require 'spider-gazelle/upgrades/websocket'


module Orchestrator
    class PersistenceController < ActionController::Metal
        include ActionController::Head


        def self.start(hijacked)
            ws = ::SpiderGazelle::Websocket.new(hijacked.socket, hijacked.env)
            WebsocketManager.new(ws)
            ws.start
        end


        START_WS = self.method(:start)
        HEADERS = {
            'Content-Length' => '0'
        }.freeze


        def websocket
            hijack = request.env['rack.hijack']
            if hijack
                promise = hijack.call
                # TODO:: grab user for authorization checks in the web socket
                promise.then START_WS

                head :ok     # to prevent rails from complaining 
            else
                head :method_not_allowed, HEADERS.dup
            end
        end
    end
end
