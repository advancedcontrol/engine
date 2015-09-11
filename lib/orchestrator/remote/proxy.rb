require 'radix/base'


module Orchestrator
    module Remote
        class Proxy
            B65 = ::Radix::Base.new(::Radix::BASE::B62 + ['-', '_', '~'])
            B10 = ::Radix::Base.new(10)

            def initialize(ctrl, dep_man, tcp)
                @ctrl = ctrl
                @dep_man = dep_man
                @thread = ctrl.loop
                @tcp = tcp

                @sent = {}
                @count = 0
            end


            # ---------------------------------
            # Send commands to the remote node:
            # ---------------------------------
            def execute(mod_id, func, args = nil, user_id = nil)
                defer = @thread.defer

                msg = {
                    type: :cmd,
                    mod: mod_id,
                    func: func
                }

                msg[:args] = args if args
                msg[:user] = user_id if user_id

                @thread.schedule do
                    id = send_with_id(msg)
                    @sent[id] = defer
                end

                defer.promise
            end

            def status(mod_id, status_name)
                defer = @thread.defer

                msg = {
                    type: :stat,
                    mod: mod_id,
                    stat: status_name
                }

                @thread.schedule do
                    id = send_with_id(msg)
                    @sent[id] = defer
                end

                defer.promise
            end

            def shutdown
                msg = {
                    type: :push,
                    push: :shutdown
                }
                send_direct(msg)
            end

            # TODO:: Expire System Cache
            # TODO:: Reload module, system, dependency, zone (settings update)
            # ------> Might also need to pass the settings down the wire to avoid race conditions

            def reload(dep_id)
                msg = {
                    type: :push,
                    push: :reload,
                    dep: dep_id
                }
                send_direct(msg)
            end

            [:load, :start, :stop, :unload].each do |cmd|
                define_method cmd do |mod_id|
                    msg = {
                        type: :push,
                        push: cmd,
                        mod: mod_id
                    }
                    send_direct(msg)
                end
            end

            def set_status(mod_id, status_name, value)
                begin
                    msg = {
                        type: :push,
                        push: :status,
                        mod: mod_id,
                        stat: status_name,
                        val: value
                    }
                    send_direct(msg)
                rescue => e
                    # TODO:: Log this status value serialisation failure
                    puts "Status value failed to send #{mod_id} -> #{status_name}=#{value}"
                    puts e.message
                    puts e.backtrace.join("\n")
                end
            end

            def restore
                msg = {
                    type: :restore
                }
                send_direct(msg)
            end


            # -------------------------------------
            # Processing data from the remote node:
            # -------------------------------------

            def process(msg)
                case msg[:type].to_sym
                when :cmd
                    puts "\nexec #{msg[:mod]}.#{msg[:func]} -> as #{msg[:user]}"
                    exec(msg[:id], msg[:mod], msg[:func], msg[:args] || [], msg[:user])
                when :stat
                    get_status(msg[:id], msg[:mod], msg[:stat])
                when :resp
                    puts "\nresp #{msg}"
                    response(msg)
                when :push
                    puts "\n#{msg[:push]} #{msg[:mod]}"
                    command(msg)
                when :restore
                    puts "\nServer requested we restore control"
                    @ctrl.nodes[NodeId].slave_control_restored
                end
            end


            protected


            def next_id
                @count += 1
                ::Radix.convert(@count, B10, B65).freeze
            end

            # This is a response to a message we requested from the node
            def response(msg)
                request = @sent.delete msg[:id]

                if request
                    if request[:reject]
                        req.reject StandardError.new(request[:reject])
                    else
                        req.resolve request[:resolve]
                        if request[:was_object]
                            # TODO:: log a warning that the return value might not
                            # be what was expected
                        end
                    end
                else
                    # TODO:: log a warning as we can't find this request
                end
            end


            # This is a request from the remote node
            def exec(req_id, mod_id, func, args, user_id)
                mod = @ctrl.loaded? mod_id
                user = User.find_by_id(user_id) if user_id

                if mod
                    result = Core::RequestProxy.new(@thread, mod, user).method_missing(func, *args)
                    if result.is_a? ::Libuv::Q::Promise
                        result.then do |val|
                            send_resolution(req_id, val)
                        end
                        result.catch do |err|
                            send_rejection(req_id, err.message)
                        end
                    else
                        send_resolution(req_id, result)
                    end
                else
                    # reject the request
                    send_rejection(req_id, 'module not loaded'.freeze)
                end
            end

            # This is a request from the remote node
            def get_status(req_id, mod_id, status)
                mod = @ctrl.loaded? mod_id

                if mod
                    val = mod.status[status.to_sym]
                    send_resolution(req_id, val)
                else
                    send_rejection(req_id, 'module not loaded'.freeze)
                end
            end

            # This is a request that isn't looking for a response
            def command(msg)
                msg_type = msg[:push].to_sym

                case msg_type
                when :shutdown
                    # TODO:: shutdown the control server
                    # -- This will trigger the failover
                    # -- Good for performing updates with little downtime

                when :reload
                    dep = Dependency.find_by_id(msg[:dep])
                    if dep
                        @dep_man.load(dep, :force).catch do |err|
                            # TODO:: Log the error here
                        end
                    else
                        # TODO:: Log the dependency not found
                    end

                when :load
                    @ctrl.update(msg[:mod], false)

                when :start, :stop
                    @ctrl.__send__(msg_type, msg[:mod], false)

                when :unload
                    @ctrl.unload(msg[:mod], false)

                when :status
                    mod_id = msg[:mod]
                    mod = @ctrl.loaded?(mod_id)

                    if mod
                        # The false indicates "don't send this update back to the remote node"
                        mod.trak(msg[:stat].to_sym, msg[:val], false)
                        puts "Received status #{msg[:stat]} = #{msg[:val]}"
                    else
                        # TODO:: warn that the module isn't known
                    end
                end
            end


            # ------------
            # IO Transport
            # ------------

            def send_with_id(msg)
                id = next_id
                msg[:id] = id
                output = ::JSON.generate(msg)
                @tcp.write "\x02#{output}\x03"
                id
            end

            def send_direct(msg)
                output = ::JSON.generate(msg)
                @tcp.write "\x02#{output}\x03"
            end

            # Reply to Requests
            def send_resolution(req_id, value)
                response = {
                    id: req_id,
                    type: :resp
                }
                # Don't send nil values (save on bytes)
                response[:resolve] = value if value.nil?

                output = nil
                begin
                    output = ::JSON.generate(response)
                rescue
                    response[:was_object] = true
                    response.delete(:resolve)

                    # Value probably couldn't be converted into a JSON object for transport...
                    output = ::JSON.generate(response)
                end

                @tcp.write "\x02#{output}\x03"
            end

            def send_rejection(req_id, msg)
                response = {
                    id: req_id,
                    type: :resp,
                    reject: msg
                }

                output = ::JSON.generate(response)

                @tcp.write "\x02#{output}\x03"
            end
        end
    end
end
