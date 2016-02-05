require 'spider-gazelle/upgrades/websocket'


module Orchestrator
    class PersistenceController < ApiController
        CONTROL = Control.instance


        # Supply a bearer_token param for oauth
        HIJACK = 'rack.hijack'.freeze

        def websocket
            hijack = request.env[HIJACK]
            if hijack && CONTROL.ready
                promise = hijack.call

                # grab user for authorization checks in the web socket
                user = current_user
                promise.then do |hijacked|
                    ws = ::SpiderGazelle::Websocket.new(hijacked.socket, hijacked.env)
                    fixed_device = params.has_key?(:fixed_device)
                    WebsocketManager.new(ws, user, fixed_device)
                    ws.start
                end

                throw :async     # to prevent rails from complaining
            else
                render nothing: true, status: :method_not_allowed
            end
        end
    end
end
