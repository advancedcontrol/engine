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
                    socket = hijacked.socket
                    begin
                        ws = ::SpiderGazelle::Websocket.new(socket, hijacked.env)
                        fixed_device = params.has_key?(:fixed_device)
                        ip, port = socket.peername
                        WebsocketManager.new(ip, ws, user, fixed_device)
                        ws.start
                    rescue => e
                        socket.close

                        msg = String.new
                        msg << "Error starting websocket"
                        msg << "\n#{e.message}\n"
                        msg << e.backtrace.join("\n") if e.respond_to?(:backtrace) && e.backtrace
                        logger.error msg
                    end
                end

                throw :async     # to prevent rails from complaining
            else
                head :method_not_allowed
            end
        end
    end
end
