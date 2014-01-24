require 'spider-gazelle/upgrades/websocket'


module Orchestrator
    class PersistenceController < ActionController::Metal
        include ActionController::Rendering


        def self.start(hijacked)
            ws = ::SpiderGazelle::Websocket.new(hijacked.socket, hijacked.env)
            WebsocketManager.new(ws)
            ws.start
        end

        START_WS = self.method(:start)
        CONTROL = Control.instance


        def websocket
            hijack = request.env['rack.hijack']
            if hijack && CONTROL.ready
                promise = hijack.call
                # TODO:: grab user for authorization checks in the web socket
                promise.then START_WS

                throw :async     # to prevent rails from complaining 
            else
                render nothing: true, status: :method_not_allowed
            end
        end
    end
end
