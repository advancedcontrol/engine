require 'set'


module Orchestrator
    class WebsocketManager
        def initialize(ws, user = nil)
            @ws = ws
            @user = user
            @loop = ws.socket.loop

            @bindings = {}

            @ws.progress = method(:on_message)
            @ws.finally method(:on_shutdown)
        end


        DECODE_OPTIONS = {
            symbolize_keys: true
        }.freeze

        PARAMS = [:id, :cmd, :sys, :mod, :index, :name, {args: [].freeze}.freeze].freeze
        REQUIRED = Set.new([:id, :cmd, :sys, :mod, :name]).freeze

        ERRORS = {
            parse_error: 0,
            bad_request: 1,
            access_denied: 2,
            request_failed: 3,
            unknown_command: 4,

            system_not_found: 5,
            module_not_found: 6
        }.freeze


        protected


        def on_message(data, ws)
            begin
                raw_parameters = ::ActiveSupport::JSON.decode(data, DECODE_OPTIONS)
                parameters = ::ActionController::Parameters.new(raw_parameters)
                params = parameters.permit(PARAMS)
            rescue => e
                # TODO:: log error here with user information (possible hacking attempt)
                error_response(nil, ERRORS[:parse_error], e.message)
                return
            end

            if check_requirements(params)
                if security_check(params)
                    begin
                        case params[:cmd]
                        when :exec
                            exec(params)
                        when :bind
                            bind(params)
                        when :unbind
                            unbind(params)
                        else
                            # TODO:: log error here (possible probing attempt)
                            error_response(params[:id], ERRORS[:unknown_command], "unknown command: #{params[:cmd]}")
                        end
                    rescue => e
                        # TODO:: log error here - most likely an innocent failure however who knows
                        error_response(params[:id], ERRORS[:request_failed], e.message)
                    end
                else
                    # TODO:: log access attempt here (possible hacking attempt)
                    error_response(params[:id], ERRORS[:access_denied], 'required parameters were missing from the request')
                end
            else
                # TODO:: log user information here (possible probing attempt)
                error_response(params[:id], ERRORS[:bad_request], 'required parameters were missing from the request')
            end
        end

        def check_requirements(params)
            keys = Set.new(params.keys)
            REQUIRED.subset? keys
        end

        def security_check(params)
            # TODO:: fill this out
            # Should callback to config block to check user access
            # User would have had to have been authenticated to get socket access
            true
        end


        def exec(params)

        end

        def bind(params)
            sys = params[:sys]
            mod = params[:mod]
            name = params[:name]
            index_s = params[:index] || 1
            index = index_s.to_i

            lookup = :"#{sys}_#{mod}_#{index}_#{name}"


        end

        def unbind(params)
            id = params[:id]
            sys = params[:sys]
            mod = params[:mod]
            name = params[:name]
            index_s = params[:index] || 1
            index = index_s.to_i

            lookup = :"#{sys}_#{mod}_#{index}_#{name}"
            binding = @bindings.delete(lookup)
            if binding
                # TODO:: Unbind logic here
            end

            @ws.text(::ActiveSupport::JSON.encode({
                id: id,
                result: :success
            })
        end
        

        def error_response(id, code, message)
            @ws.text(::ActiveSupport::JSON.encode({
                id: id,
                result: :error,
                code: code,
                msg: message
            }))
        end

        def on_shutdown
            # TODO:: clean up bindings
            @bindings.each method(:do_unbind)
        end

        def do_unbind(binding)

        end
    end
end
