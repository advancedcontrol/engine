require 'set'
require 'json'


module Orchestrator
    class WebsocketManager
        def initialize(ws, user)
            @ws = ws
            @user = user
            @loop = ws.loop

            @bindings = ::ThreadSafe::Cache.new
            @stattrak = @loop.observer
            @notify_update = method(:notify_update)

            @logger = ::Orchestrator::Logger.new(@loop, user)

            @ws.progress method(:on_message)
            @ws.finally method(:on_shutdown)
            #@ws.on_open method(:on_open)
        end


        DECODE_OPTIONS = {
            symbolize_names: true
        }.freeze

        PARAMS = [:id, :cmd, :sys, :mod, :index, :name, {args: [].freeze}.freeze].freeze
        REQUIRED = [:id, :cmd, :sys, :mod, :name].freeze
        COMMANDS = Set.new([:exec, :bind, :unbind, :debug, :ignore])

        ERRORS = {
            parse_error: 0,
            bad_request: 1,
            access_denied: 2,
            request_failed: 3,
            unknown_command: 4,

            system_not_found: 5,
            module_not_found: 6,
            unexpected_failure: 7
        }.freeze


        protected


        def on_message(data, ws)
            if data == 'ping'
                @ws.text('pong')
                return
            end

            begin
                raw_parameters = ::JSON.parse(data, DECODE_OPTIONS)
                parameters = ::ActionController::Parameters.new(raw_parameters)
                params = parameters.permit(PARAMS).tap do |whitelist|
                    whitelist[:args] = parameters[:args]
                end
            rescue => e
                @logger.print_error(e, 'error parsing websocket request')
                error_response(nil, ERRORS[:parse_error], e.message)
                return
            end

            if check_requirements(params)
                # Perform the security check in a nonblocking fashion
                # (Database access is probably required)
                result = @loop.work do
                    params[:sys] = ::Orchestrator::ControlSystem.bucket.get("sysname-#{sys}", {quiet: true}) || sys
                    Rails.configuration.orchestrator.check_access.call(params[:sys], @user)
                end

                # The result should be an access level if these are implemented
                result.then do |access|
                    begin
                        cmd = params[:cmd].to_sym
                        if COMMANDS.include?(cmd)
                            self.__send__(cmd, params)
                        else
                            @logger.warn("websocket requested unknown command '#{params[:cmd]}'")
                            error_response(params[:id], ERRORS[:unknown_command], "unknown command: #{params[:cmd]}")
                        end
                    rescue => e
                        @logger.print_error(e, "websocket request failed: #{data}")
                        error_response(params[:id], ERRORS[:request_failed], e.message)
                    end
                end

                # Raise an error if access is not granted
                result.catch do |err|
                    @logger.print_error(e, 'security check failed for websocket request')
                    error_response(params[:id], ERRORS[:access_denied], e.message)
                end
            else
                # log user information here (possible probing attempt)
                reason = 'required parameters were missing from the request'
                @logger.warn(reason)
                error_response(params[:id], ERRORS[:bad_request], reason)
            end
        end

        def check_requirements(params)
            REQUIRED.each do |key|
                return false if params[key].nil?
            end
            true
        end


        def exec(params)
            id = params[:id]
            sys = params[:sys]
            mod = params[:mod].to_sym
            name = params[:name].to_sym
            index_s = params[:index] || 1
            index = index_s.to_i

            args = params[:args] || []

            @loop.work do
                do_exec(id, sys, mod, index, name, args)
            end
        end

        def do_exec(id, sys, mod, index, name, args)
            system = ::Orchestrator::System.get(sys)

            if system
                mod_man = system.get(mod, index - 1)
                if mod_man
                    req = Core::RequestProxy.new(@loop, mod_man)
                    result = req.send(name, *args)
                    result.then(proc { |res|
                        output = nil
                        begin
                            ::JSON.generate([res])
                            output = res
                        rescue => e
                            # respond with nil if object cannot be converted
                            # TODO:: need a better way of dealing with this
                            # ALSO in systems controller
                        end
                        @ws.text(::JSON.generate({
                            id: id,
                            type: :success,
                            value: output
                        }))
                    }, proc { |err|
                        # Request proxy will log the error
                        error_response(id, ERRORS[:request_failed], err.message)
                    })
                else
                    @logger.debug("websocket exec could not find module: {sys: #{sys}, mod: #{mod}, index: #{index}, name: #{name}}")
                    error_response(id, ERRORS[:module_not_found], "could not find module: #{mod}")
                end
            else
                @logger.debug("websocket exec could not find system: {sys: #{sys}, mod: #{mod}, index: #{index}, name: #{name}}")
                error_response(id, ERRORS[:system_not_found], "could not find system: #{sys}")
            end
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
            do_unbind(binding) if binding

            @ws.text(::JSON.generate({
                id: id,
                type: :success
            }))
        end

        def do_unbind(binding)
            @stattrak.unsubscribe(binding)
        end


        def bind(params)
            id = params[:id]
            sys = params[:sys]
            mod = params[:mod].to_sym
            name = params[:name].to_sym
            index_s = params[:index] || 1
            index = index_s.to_i

            # perform binding on the thread pool
            @loop.work(proc {
                check_binding(id, sys, mod, index, name)
            }).catch do |err|
                @logger.print_error(err, "websocket request failed: #{params}")
                error_response(id, ERRORS[:unexpected_failure], err.message)
            end
        end

        # Called from a worker thread
        def check_binding(id, sys, mod, index, name)
            system = ::Orchestrator::System.get(sys)

            if system
                lookup = :"#{sys}_#{mod}_#{index}_#{name}"
                binding = @bindings[lookup]

                if binding.nil?
                    try_bind(id, sys, system, mod, index, name, lookup)
                else
                    # binding already made - return success
                    @ws.text(::JSON.generate({
                        id: id,
                        type: :success,
                        meta: {
                            sys: sys,
                            mod: mod,
                            index: index,
                            name: name
                        }
                    }))
                end
            else
                @logger.debug("websocket binding could not find system: {sys: #{sys}, mod: #{mod}, index: #{index}, name: #{name}}")
                error_response(id, ERRORS[:system_not_found], "could not find system: #{sys}")
            end
        end

        def try_bind(id, sys, system, mod_name, index, name, lookup)
            options = {
                sys_id: sys,
                sys_name: system.config.name,
                mod_name: mod_name,
                index: index,
                status: name,
                callback: @notify_update,
                on_thread: @loop
            }

            # if the module exists, subscribe on the correct thread
            # use a bit of promise magic as required
            mod_man = system.get(mod_name, index - 1)
            defer = @loop.defer

            # Ensure browser sees this before the first status update
            # At this point subscription will be successful
            @bindings[lookup] = defer.promise
            @ws.text(::JSON.generate({
                id: id,
                type: :success,
                meta: {
                    sys: sys,
                    mod: mod_name,
                    index: index,
                    name: name
                }
            }))

            if mod_man
                options[:mod_id] = mod_man.settings.id.to_sym
                options[:mod] = mod_man
                thread = mod_man.thread
                thread.schedule do
                    defer.resolve (
                        thread.observer.subscribe(options)
                    )
                end
            else
                @loop.schedule do
                    defer.resolve @stattrak.subscribe(options)
                end
            end
        end

        def notify_update(update)
            output = nil
            begin
                ::JSON.generate([update.value])
                output = update.value
            rescue => e
                # respond with nil if object cannot be converted
                # TODO:: need a better way of dealing with this
            end
            @ws.text(::JSON.generate({
                type: :notify,
                value: output,
                meta: {
                    sys: update.sys_id,
                    mod: update.mod_name,
                    index: update.index,
                    name: update.status
                }
            }))
        end


        def debug(params)
            id = params[:id]
            sys = params[:sys]
            mod_s = params[:mod]
            mod = mod_s.to_sym if mod_s

            if @debug.nil?
                @debug = @loop.defer
                @inspecting = Set.new # modules
                @debug.promise.progress method(:debug_update)
            end

            # Set mod to get module level errors
            if mod && !@inspecting.include?(mod)
                mod_man = ::Orchestrator::Control.instance.loaded?(mod)
                if mod_man
                    log = mod_man.logger
                    log.add @debug
                    log.level = :debug
                    @inspecting.add mod

                    # Set sys to get errors occurring outside of the modules
                    if !@inspecting.include?(:self)
                        @logger.add @debug
                        @logger.level = :debug
                        @inspecting.add :self
                    end

                    @ws.text(::JSON.generate({
                        id: id,
                        type: :success
                    }))
                else
                    @logger.info("websocket debug could not find module: #{mod}")
                    error_response(id, ERRORS[:module_not_found], "could not find module: #{mod}")
                end
            else
                @ws.text(::JSON.generate({
                    id: id,
                    type: :success
                }))
            end
        end

        def debug_update(klass, id, level, msg)
            @ws.text(::JSON.generate({
                type: :debug,
                mod: id,
                klass: klass,
                level: level,
                msg: msg
            }))
        end


        def ignore(params)
            id = params[:id]
            sys = params[:sys]
            mod_s = params[:mod]
            mod = mod_s.to_sym if mod_s

            if @debug.nil?
                @debug = @loop.defer
                @inspecting = Set.new # modules
                @debug.promise.progress method(:debug_update)
            end

            # Remove module level errors
            if mod && @inspecting.include?(mod)
                mod_man = ::Orchestrator::Control.instance.loaded?(mod)
                if mod_man
                    mod_man.logger.delete @debug
                    @inspecting.delete mod

                    # Stop logging all together if no more modules being watched
                    if @inspecting.empty?
                        @logger.delete @debug
                        @inspecting.delete :self
                    end

                    @ws.text(::JSON.generate({
                        id: id,
                        type: :success
                    }))
                else
                    @logger.info("websocket ignore could not find module: #{mod}")
                    error_response(id, ERRORS[:module_not_found], "could not find module: #{mod}")
                end
            else
                @ws.text(::JSON.generate({
                    id: id,
                    type: :success
                }))
            end
        end


        def error_response(id, code, message)
            @ws.text(::JSON.generate({
                id: id,
                type: :error,
                code: code,
                msg: message
            }))
        end

        def on_shutdown
            @bindings.each_value &method(:do_unbind)
            @bindings = nil
            @debug.resolve(true) if @debug # detach debug listeners
        end
    end
end
