require 'spider-gazelle/upgrades/websocket'


module Orchestrator
    class PersistenceController < ActionController::Metal
        include ActionController::Head

        def self.start(hijacked)
            puts 'Websocket connected!'

            ws = ::SpiderGazelle::Websocket.new(hijacked.socket, hijacked.env)

            ws.progress do |data|
                puts "recieved #{data}"
            end
            ws.start
            ws.text('test send')
            ws.then(proc { |e|
                puts "closed with #{e.inspect}"
            }, proc { |e|
                puts "failed with #{e[:code]}: #{e[:reason]}"
            })
        end


        START_WS = self.method(:start)
        HEADERS = {
            'Content-Length' => '0'
        }.freeze


        def websocket
            hijack = request.env['rack.hijack']
            if hijack
                promise = hijack.call
                # TODO:: update env with any authentication information
                promise.then START_WS

                head :ok     # to prevent rails from complaining 
            else
                head :method_not_allowed, HEADERS.dup
            end
        end
    end
end
