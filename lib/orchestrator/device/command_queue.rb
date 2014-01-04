require 'uv-priority-queue'
require 'bisect'


# Transport -> connection (make break etc)
# * attach connected, disconnected callbacks
# * udp, makebreak and tcp transports
# Manager + CommandProcessor + Transport


module Orchestrator
    module Device
        class CommandQueue

            
            attr_reader :waiting


            # init -> mod.load -> post_init
            # So config can be set in on_load if desired
            def initialize(loop, callback)
                @loop = @loop
                @callback = callback

                @named_commands = {
                    # name: [[priority list], command]
                    # where command may be nil
                }
                @pending_commands = UV::PriorityQueue.new(fifo: true)

                @waiting = nil      # Last command sent that was marked as waiting
                @state = :online    # online / offline
                @shift = method(:shift)
            end

            def shift
                @waiting = nil  # Discard the current command
                if length > 0
                    next_cmd = @pending_commands.pop

                    if next_cmd.is_a? Symbol # (named command)
                        result = @named_commands[next_cmd]
                        result[0].shift
                        cmd = result[1]
                        if cmd.nil? && length > 0
                            @loop.next_tick @shift
                            return  # command already executed, this is a no-op
                        end
                    else
                        cmd = next_cmd
                    end

                    @waiting = cmd if cmd[:wait]
                    @callback.call cmd
                end
            end

            def push(command, priority)
                if @state == :offline && command[:name].nil?
                    return
                end

                if command[:name]
                    name = command[:name].to_sym

                    current = @named_commands[name] ||= [[], nil]
                    current[0] << priority
                    current[1] = command

                    @pending_commands.push(name, priority)
                else
                    @pending_commands.push(command, priority)
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
                @loop.next_tick @shift
            end

            def offline(clear = false)
                @state = :offline

                if clear
                    @pending_commands.clear
                    @named_commands.clear

                    @waiting = nil
                else
                    # Keep named commands
                    new_queue = UV::PriorityQueue.new(fifo: true)

                    while length > 0
                        cmd = @pending_commands.pop
                        if cmd.is_a? Symbol
                            res = @named_commands[cmd][0]
                            pri = res.shift
                            res << pri
                            new_queue.push(cmd, pri)
                        end
                    end
                    @pending_commands = new_queue
                    
                    if @waiting && @waiting[:name].nil?
                        @waiting = nil
                    end
                end
            end
        end
    end
end
