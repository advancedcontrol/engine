require 'set'


# Transport -> connection (make break etc)
# * attach connected, disconnected callbacks
# * udp, makebreak and tcp transports
# Manager + CommandProcessor + Transport


module Orchestrator
    module Device
        class Processor
            include ::Orchestrator::Transcoder


            # Any command that waits:
            # send('power on?').then( execute after command complete )
            # Named commands mean the promise may never resolve
            # Totally replaces emit as we don't care and makes cross module request super easy
            # -- non-wait commands resolve after they have been written to the socket!!


            SEND_DEFAULTS = {
                wait: true,                 # wait for a response before continuing with sends
                delay: 0,                   # make sure sends are separated by at least this (in milliseconds)
                delay_on_receive: 0,        # delay the next send by this (milliseconds) after a receive
                max_waits: 3,               # number of times we will ignore valid tokens before retry
                retries: 2,                 # Retry attempts before we give up on the command
                hex_string: false,          # Does the input need conversion
                timeout: 5000,              # Time we will wait for a response
                priority: 50,               # Priority of a send
                force_disconnect: false     # Mainly for use with make and break

                # Other options include:
                # * emit callback to occur once command complete
                # * callback (alternative to received function)
            }

            CONFIG_DEFAULTS = {
                tokenize: false,    # If replaced with a callback can define custom tokenizers
                size_limit: 524288, # 512kb buffer max
                clear_queue_on_disconnect: false,
                flush_buffer_on_disconnect: false,
                priority_bonus: 20,  # give commands bonus priority under certain conditions
                update_status: true  # auto update connected status?

                # Other options include:
                # * inactivity_timeout (used with make and break)
                # * delimiter (string or regex to match message end)
                # * indicator (string or regex to match message start)
                # * verbose (throw errors or silently recover)
            }


            SUCCESS = Set.new([true, :success, :abort, nil, :ignore])
            FAILURE = Set.new([false, :retry, :failed])
            DUMMY_RESOLVER = proc {}


            attr_reader :config, :queue
            attr_accessor :transport


            # init -> mod.load -> post_init
            # So config can be set in on_load if desired
            def initialize(man)
                @man = man

                @loop = @man.thread
                @logger = @man.logger
                @defaults = SEND_DEFAULTS.dup
                @config = CONFIG_DEFAULTS.dup

                @queue = CommandQueue.new(@loop, method(:send_next))
                @responses = []
                @wait = false
                @connected = false
                @bonus = 0

                @last_sent_at = 0
                @last_receive_at = 0


                # Used to indicate when we can start the next response processing
                @head = ::Libuv::Q::ResolvedPromise.new(@loop, true)
                @tail = ::Libuv::Q::ResolvedPromise.new(@loop, true)

                # Method variables
                @resp_success = method(:resp_success)
                @resp_failure = method(:resp_failure)
                @resolver = proc { |resp| @loop.schedule { resolve_callback(resp) } }
            end

            ##
            # Helper functions ------------------
            def send_options(options)
                @defaults.merge!(options)
            end

            def config=(options)
                @config.merge!(options)
            end

            #
            # Public interface
            def queue_command(options)
                # Make sure we are sending appropriately formatted data
                raw = options[:data]

                if raw.is_a?(Array)
                    options[:data] = array_to_str(raw)
                elsif options[:hex_string] == true
                    options[:data] = hex_to_byte(raw)
                end

                data = options[:data]
                options[:retries] = 0 if options[:wait] == false

                if options[:name].is_a? String
                    options[:name] = options[:name].to_sym
                end

                # merge in the defaults
                options = @defaults.merge(options)

                @queue.push(options, options[:priority] + @bonus)

            rescue Exception => e
                options[:defer].reject(e)
                @logger.print_error(e, 'error queuing command')
            end

            ##
            # Callbacks -------------------------
            def connected
                @connected = true
                @man.notify_connected
                if @config[:update_status]
                    @man.trak(:connected, true)
                end
                tokenize = @config[:tokenize]
                if tokenize
                    if tokenize.respond_to? :call
                        @buffer = tokenize.call
                    else
                        @buffer = ::UV::BufferedTokenizer.new(@config)
                    end
                end
            end

            def disconnected
                @connected = false
                @man.notify_disconnected
                if @config[:update_status]
                    @man.trak(:connected, false)
                end
                if @config[:flush_buffer_on_disconnect]
                    check_data(@buffer.flush)
                end
                @buffer = nil

                if @queue.waiting
                    resp_failure(:disconnected)
                end
            end

            def buffer(data)
                @last_receive_at = @loop.now

                if @buffer
                    @responses.concat @buffer.extract(data)
                else
                    @responses << data
                end

                # if we are waiting we don't want to process this data just yet
                if !@wait
                    check_next
                end
            end


            protected


            def check_next
                return unless @responses.length > 0
                loop do
                    check_data(@responses.shift)
                    break if @wait || @responses.length == 0
                end
            end

            # Check transport response data
            def check_data(data)
                resp = nil

                # Provide commands with a bonus in this section
                @bonus = @config[:priority_bonus]

                begin
                    if @queue.waiting
                        @wait = true
                        @defer = @loop.defer
                        @defer.promise.then @resp_success, @resp_failure

                        # Send response, early resolver and command
                        # TODO:: call callback if present
                        resp = @man.notify_received(data, @resolver, @queue.waiting)
                    else
                        resp = @man.notify_received(data, DUMMY_RESOLVER)
                        # Don't need to trigger Queue next here as we are not waiting on anything
                    end
                rescue Exception => e
                    @logger.print_error(e, 'error processing response data')
                    @defer.reject :abort if @defer
                ensure
                    @bonus = 0
                end

                # Check if response is a success or failure
                resolve_callback(resp) unless resp == :async
            end

            def resolve_callback(resp)
                if @defer
                    if FAILURE.include? resp
                        @defer.reject resp
                    else
                        @defer.resolve resp
                    end
                    @defer = nil
                end
            end

            def resp_failure(result_raw, *args)
                if @queue.waiting
                    result = result_raw.is_a?(Fixnum) ? :timeout : result_raw
                    cmd = @queue.waiting
                    @logger.debug "command failed with #{result}: #{cmd[:name]}- #{cmd[:data]}"

                    if cmd[:retries] == 0

                        err = Error::CommandFailure.new "command aborted with #{result}: #{cmd[:name]}- #{cmd[:data]}"
                        cmd[:defer].reject(err)
                        @logger.warn err.message
                    else
                        cmd[:retries] -= 1
                        cmd[:wait_count] = 0      # reset our ignore count
                        @queue.push(cmd, cmd[:priority] + @config[:priority_bonus])
                    end
                end

                clear_timers

                @wait = false
                @queue.waiting = nil
                check_next                    # Process already received
                @queue.shift if @connected    # Then send a new command
            end

            # We only care about queued commands here
            # Promises resolve on the next tick so processing
            #  is guaranteed to have completed
            # Check for queue wait as we may have gone offline
            def resp_success(result)
                if @queue.waiting && (result == :success || result == :abort || (result && result != :ignore))
                    if result == :abort
                        err = Error::CommandFailure.new "command aborted with #{result}: #{cmd[:name]}- #{cmd[:data]}"
                        @queue.waiting[:defer].reject(err)
                    else
                        @queue.waiting[:defer].resolve(result)
                        callback = @queue.waiting[:emit]
                        if callback
                            @loop.next_tick do
                                call_emit callback
                            end
                        end
                    end

                    clear_timers

                    @wait = false
                    @queue.waiting = nil
                    check_next      # Process pending
                    @queue.shift    # Send the next command

                    # Else it must have been a nil or :ignore
                elsif @queue.waiting
                    cmd = @queue.waiting
                    cmd[:wait_count] ||= 0
                    cmd[:wait_count] += 1
                    if cmd[:wait_count] > cmd[:max_waits]
                        resp_failure(:max_waits_exceeded)
                    else
                        check_next
                    end

                else  # ensure consistent state (offline event may have occurred)

                    clear_timers

                    @wait = false
                    check_next
                end
            end

            # If a callback was in place for the current
            def call_emit(callback)
                begin
                    callback.call
                rescue Exception => e
                    @logger.print_error(e, 'error in emit callback')
                end
            end


            # Callback for queued commands
            def send_next(command)
                # Check for any required delays between sends
                if command[:delay] > 0
                    gap = @last_sent_at + command[:delay] - @loop.now
                    if gap > 0
                        defer = @loop.defer
                        sched = schedule.in(gap) do
                            defer.resolve(process_send(command))
                        end
                        # in case of shutdown we need to resolve this promise
                        sched.catch do
                            defer.reject(:shutdown)
                        end
                        defer.promise
                    else
                        process_send(command)
                    end
                else
                    process_send(command)
                end
            end

            def process_send(command)
                # delay on receive
                if command[:delay_on_receive] > 0
                    gap = @last_receive_at + command[:delay_on_receive] - @loop.now

                    if gap > 0
                        defer = @loop.defer
                        
                        sched = schedule.in(gap) do
                            defer.resolve(process_send(command))
                        end
                        # in case of shutdown we need to resolve this promise
                        sched.catch do
                            defer.reject(:shutdown)
                        end
                        defer.promise
                    else
                        transport_send(command)
                    end
                else
                    transport_send(command)
                end
            end

            def transport_send(command)
                data = command[:data]
                @transport.write(data)
                @last_sent_at = @loop.now

                if @queue.waiting
                    # Set up timers for command timeout
                    @timeout = schedule.in(command[:timeout], @resp_failure)
                else
                    # resole the send promise early as we are not waiting for the response
                    command[:defer].resolve(:no_wait)
                end
                nil # ensure promise chain is not propagated
            end

            def clear_timers
                @timeout.cancel if @timeout
                @timeout = nil
            end

            def schedule
                @schedule ||= @man.get_scheduler
            end
        end
    end
end