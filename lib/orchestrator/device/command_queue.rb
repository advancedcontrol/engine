require 'algorithms'
require 'bisect'


# Transport -> connection (make break etc)
# * attach connected, disconnected callbacks
# * udp, makebreak and tcp transports
# Manager + CommandProcessor + Transport


module Orchestrator
    module Device
        class CommandQueue


            OFFLINE_MSG = Error::CommandCanceled.new 'command canceled as module went offline'


            attr_accessor :waiting
            attr_reader :state
            attr_reader :pause


            # init -> mod.load -> post_init
            # So config can be set in on_load if desired
            def initialize(loop, callback)
                @loop = loop
                @callback = callback

                @named_commands = {
                    # name: [[priority list], command]
                    # where command may be nil
                }
                @comparison = method(:comparison)
                @pending_commands = Containers::Heap.new(&@comparison)

                @waiting = nil      # Last command sent that was marked as waiting
                @pause = 0
                @state = :online    # online / offline
                @pause_shift = method(:pause_shift)
                @move_forward = method(:move_forward)
            end

            def shift_next_tick
                @pause += 1
                @loop.next_tick @pause_shift
            end

            def shift
                return if @pause > 0 # we are waiting for the next_tick?

                @waiting = nil  # Discard the current command
                if length > 0
                    next_cmd = @pending_commands.pop

                    if next_cmd.class == Symbol # (named command)
                        result = @named_commands[next_cmd]
                        result[0].shift
                        cmd = result[1]
                        if cmd.nil?
                            shift_next_tick if length > 0
                            return  # command already executed, this is a no-op
                        else
                            result[1] = nil
                        end
                    else
                        cmd = next_cmd
                    end

                    @waiting = cmd if cmd[:wait]
                    shift_promise = @callback.call cmd

                    if shift_promise.is_a? ::Libuv::Q::Promise
                        @pause += 1
                        shift_promise.finally do # NOTE:: This schedule may not be required...
                            @loop.schedule @move_forward
                        end
                    else
                        shift_next_tick if length > 0
                    end
                end
            end

            def push(command, priority)
                if @state == :offline && command[:name].nil?
                    return
                end

                if command[:name]
                    name = command[:name].to_sym

                    current = @named_commands[name] ||= [[], nil]

                    # Chain the promises if the named command is already in the queue
                    cmd = current[1]
                    cmd[:defer].resolve(command[:defer].promise) if cmd

                    
                    current[1] = command   # replace the old command
                    priors = current[0]

                    # Only add commands of higher priority to the queue
                    if priors.empty? || priors[-1] < priority
                        priors << priority
                        queue_push(@pending_commands, name, priority)
                    end
                else
                    queue_push(@pending_commands, command, priority)
                end

                if @waiting.nil? && @state == :online
                    shift  # This will trigger the callback
                end
            end

            def length
                @pending_commands.size
            end


            # If offline we'll only maintain named command state and queue
            def online
                @state = :online

                # next tick is important as it allows the module time to updated
                # any named commands that it desires in the connected callback
                shift_next_tick
            end

            def online?
                @state == :online
            end

            def offline(clear = false)
                @state = :offline

                if clear
                    @waiting[:defer].reject(OFFLINE_MSG) if @waiting
                    cancel_all(OFFLINE_MSG)
                    @waiting = nil
                else
                    # Keep named commands
                    new_queue = Containers::Heap.new(&@comparison)

                    while length > 0
                        cmd = @pending_commands.pop
                        if cmd.class == Symbol
                            res = @named_commands[cmd][0]
                            pri = res.shift
                            res << pri
                            queue_push(new_queue, cmd, pri)
                        else
                            cmd[:defer].reject(OFFLINE_MSG)
                        end
                    end
                    @pending_commands = new_queue
                    
                    # clear waiting if it is not a named command.
                    # The processor will re-queue it if retry on disconnect is set
                    if @waiting && @waiting[:name].nil?
                        @waiting = nil
                    end
                end
            end

            def cancel_all(msg)
                while length > 0
                    cmd = @pending_commands.pop
                    if cmd.class == Symbol
                        res = @named_commands[cmd]
                        if res
                            res[1][:defer].reject(msg)
                            @named_commands.delete(cmd)
                        end
                    else
                        cmd[:defer].reject(msg)
                    end
                end
            end


            protected


            # If we next_tick a shift then a push may be able to
            # sneak in before that command is shifted.
            # If the new push is a waiting command then the next
            # tick shift will discard it which is undesirable
            def pause_shift
                @pause -= 1
                shift
            end

            def move_forward
                @pause -= 1
                if !@waiting && length > 0
                    shift
                end
            end


            # Queue related methods
            # This ensures that the highest priorities (largest values)
            # Are processed first, if they have the same priority then they are
            # processed in the order that the commands were queued
            #
            # See: http://www.rubydoc.info/github/kanwei/algorithms/Containers/MaxHeap#initialize-instance_method
            def comparison(x, y)
                if x[0] == y[0]
                    x[1] < y[1]
                else
                    (x[0] <=> y[0]) == 1
                end
            end

            def queue_push(queue, obj, pri)
                pri = [pri, Time.now.to_f]
                queue.push(pri, obj)
            end
        end
    end
end
