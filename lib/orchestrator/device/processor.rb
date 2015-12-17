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
                # * emit callback to occur once command complete (may be discarded if a named command)
                # * on_receive (alternative to received function)
                # * clear_queue (clear further commands once this has run)
            }

            CONFIG_DEFAULTS = {
                tokenize: false,    # If replaced with a callback can define custom tokenizers
                size_limit: 524288, # 512kb buffer max
                clear_queue_on_disconnect: false,
                flush_buffer_on_disconnect: false,
                priority_bonus: 20,  # give commands bonus priority under certain conditions
                update_status: true, # auto update connected status?
                thrashing_threshold: 1500  # min milliseconds between connection retries

                # Other options include:
                # * inactivity_timeout (used with make and break)
                # * delimiter (string or regex to match message end)
                # * indicator (string or regex to match message start)
                # * verbose (throw errors or silently recover)
                # * wait_ready (wait for some signal before signaling connected)
                # * encoding (BINARY) (force encoding on incoming data)
                # * before_transmit (callback for last min data modifications)
            }


            SUCCESS = Set.new([true, :success, :abort, nil, :ignore])
            FAILURE = Set.new([false, :retry, :failed, :fail])
            DUMMY_RESOLVER = proc {}
            TERMINATE_MSG = Error::CommandCanceled.new 'command canceled due to module shutdown'
            UNNAMED = 'unnamed'


            attr_reader :config, :queue, :thread, :schedule
            attr_accessor :transport

            # For statistics only
            attr_reader :last_sent_at, :last_receive_at, :timeout


            # init -> mod.load -> post_init
            # So config can be set in on_load if desired
            def initialize(man)
                @man = man
                @schedule = @man.get_scheduler

                @thread = @man.thread
                @logger = @man.logger
                @defaults = SEND_DEFAULTS.dup
                @config = CONFIG_DEFAULTS.dup

                # Method variables
                @resp_failure = method(:resp_failure)
                @transport_send = method(:transport_send)
                @transmit_failure = method(:transmit_failure)

                # Setup the queue
                @queue = ::Orchestrator::CommandQueue.new(@thread)
                @queue.pop(@transport_send)

                @responses = []
                @wait = false
                @connected = false
                @checking = Mutex.new
                @bonus = 0

                @last_sent_at = 0
                @last_receive_at = 0
            end

            ##
            # Helper functions ------------------
            def send_options(options)
                @defaults.merge!(options) if options
            end

            def config=(options)
                if options
                    @config.merge!(options)
                    # use tokenize to signal a buffer update
                    new_buffer if options.include?(:tokenize)
                end
            end

            #
            # Public interface
            def queue_command(options)
                # Make sure we are sending appropriately formatted data
                raw = options[:data]

                if raw.class == Array
                    options[:data] = array_to_str(raw)
                elsif options[:hex_string] == true
                    options[:data] = hex_to_byte(raw)
                end

                data = options[:data]
                options[:retries] = 0 if options[:wait] == false

                if options[:name].class == String
                    options[:name] = options[:name].to_sym
                end

                # merge in the defaults
                options = @defaults.merge(options)

                @queue.push(options, options[:priority] + @bonus)

            rescue => e
                options[:defer].reject(e)
                @logger.print_error(e, 'error queuing command')
            end


            def terminate
                @thread.schedule method(:do_terminate)
            end



            # ===================
            # TRANSPORT CALLBACKS
            # ===================
            def connected
                @connected = true
                new_buffer
                @man.notify_connected
                if @config[:update_status]
                    @man.trak(:connected, true)
                end
            end

            def connected?
                @connected == true
            end

            def disconnected
                @connected = false
                @man.notify_disconnected
                if @config[:update_status]
                    @man.trak(:connected, false)
                end
                if @buffer && @config[:flush_buffer_on_disconnect]
                    check_data(@buffer.flush)
                end
                @buffer = nil

                if @current_cmd
                    resp_failure(:disconnected)
                end
            end
            # =======================
            # END TRANSPORT CALLBACKS
            # =======================
            


            # =========
            # BUFFERING
            # =========

            def buffer(data)
                @last_receive_at = @thread.now

                if @buffer
                    begin
                        @responses.concat @buffer.extract(data)
                    rescue => e
                        @logger.print_error(e, 'error tokenizing data. Clearing buffer..')
                        new_buffer
                    end
                else
                    # tokenizing buffer above will enforce encoding
                    if @config[:encoding]
                        data.force_encoding(@config[:encoding])
                    end
                    @responses << data
                end

                # if we are waiting we don't want to process this data just yet
                if !@wait
                    check_next
                end
            end

            def check_next
                return if @checking.locked? || @responses.length <= 0
                @checking.synchronize {
                    loop do
                        check_data(@responses.shift)
                        break if @wait || @responses.length == 0
                    end
                }
            end


            protected


            def new_buffer
                tokenize = @config[:tokenize]
                if tokenize
                    if tokenize.respond_to? :call
                        @buffer = tokenize.call
                    else
                        @buffer = ::UV::BufferedTokenizer.new(@config)
                    end
                elsif @buffer
                    # remove the buffer if none
                    @buffer = nil
                end
            end

            # =============
            # END BUFFERING
            # =============



            # ===================
            # RESPONSE PROCESSING
            # ===================

            # Check transport response data
            def check_data(data)
                resp = nil

                # Provide commands with a bonus in this section
                @bonus = @config[:priority_bonus]
                cmd = @current_cmd

                begin    
                    if cmd
                        @wait = true
                        callback_complete = false

                        # Send response, early resolver and command
                        resolver = proc { |resp|
                            @thread.schedule {
                                resolve_callback(resp) unless callback_complete || cmd != @current_cmd
                                callback_complete = true
                            }
                        }
                        resp = @man.notify_received(data, resolver, cmd)
                        resolve_callback(resp) unless callback_complete || resp == :async
                        callback_complete = true
                    else
                        @man.notify_received(data, DUMMY_RESOLVER, nil)
                        clear_timeout
                        @wait = false
                        check_next
                        # Don't need to trigger Queue next here as we are not waiting on anything
                    end
                rescue => e
                    # NOTE:: This error should never be called
                    callback_complete = true
                    @logger.print_error(e, 'internal error processing response data')
                    resp_failure :abort if cmd
                ensure
                    @bonus = 0
                end
            end

            def resolve_callback(resp)
                if FAILURE.include? resp
                    resp_failure(resp)
                else
                    resp_success(resp)
                end
            end

            def resp_failure(result_raw, timeout = nil)
                cmd = @current_cmd

                if cmd
                    begin
                        result = timeout.nil? ? result_raw : :timeout
                        
                        # Debug in proc so we don't perform needless processing
                        debug_proc = proc { |text|
                            debug = "#{text} with #{result}: <#{cmd[:name] || UNNAMED}> "
                            if cmd[:data]
                                debug << "#{cmd[:data].inspect}"
                            else
                                debug << cmd[:path]
                            end
                            debug
                        }

                        if cmd[:retries] == 0
                            err = Error::CommandFailure.new debug_proc.call('command aborted')
                            cmd[:defer].reject(err)
                            @logger.warn err.message
                        else
                            @logger.debug { debug_proc.call 'command failed' }
                            cmd[:retries] -= 1
                            cmd[:wait_count] = 0      # reset our ignore count
                            @queue.push(cmd, cmd[:priority] + @config[:priority_bonus])
                        end
                    rescue => e
                        # Prevent the queue from ever pausing - this should never be called
                        @logger.print_error(e, 'internal error handling request failure')
                    end

                    ready_next(cmd)
                else
                    @logger.warn "failure during response processing: #{result_raw} (no command provided)"
                end

                @wait = false
                check_next                    # Process already received
            end

            # We only care about queued commands here
            # Promises resolve on the next tick so processing
            #  is guaranteed to have completed
            # Check for queue wait as we may have gone offline
            def resp_success(result)
                cmd = @current_cmd

                if result && result != :ignore
                    # Disconnect if this was desired
                    transport.disconnect if cmd[:force_disconnect]

                    if result == :abort
                        err = Error::CommandFailure.new "module aborted command with #{result}: <#{cmd[:name] || UNNAMED}> #{(cmd[:data] || cmd[:path]).inspect}"
                        cmd[:defer].reject(err)
                    else
                        cmd[:defer].resolve(result)
                    end

                    # Continue processing commands
                    ready_next(cmd)
                    @wait = false
                    check_next      # Process pending

                # Else it must have been a nil or :ignore
                else
                    cmd[:wait_count] ||= 0
                    cmd[:wait_count] += 1
                    if cmd[:wait_count] > cmd[:max_waits]
                        resp_failure(:max_waits_exceeded)
                    else
                        @wait = false
                        check_next
                    end
                end
            end


            # =======================
            # END RESPONSE PROCESSING
            # =======================


            def do_terminate
                # Reject the current command
                if @current_cmd
                    @current_cmd[:defer].reject(TERMINATE_MSG)
                end

                # Stop any timers
                clear_timeout
                @delay_timer.cancel if @delay_timer

                # Clear the queue
                @queue.cancel_all(TERMINATE_MSG)
                @queue.pop nil
            end


            # =============
            # COMMAND QUEUE
            # =============


            # If a callback was in place for the current
            def call_emit(cmd)
                callback = cmd[:emit]
                if callback
                    @thread.next_tick do
                        begin
                            callback.call
                        rescue => e
                            @logger.print_error(e, 'error in emit callback')
                        end
                    end
                end
            end

            def transport_send(command)
                @logger.info "next command popped from queue"

                # Delay the current commad if desired
                delay_on_rec = command[:delay_on_receive]
                current_time = @thread.now
                if delay_on_rec && delay_on_rec > 0
                    gap = @last_receive_at + delay_on_rec - current_time
                    if gap > 0
                        @delay_timer = schedule.in(gap) do
                            @delay_timer = nil
                            transport_send(command)
                        end

                        return
                    end
                end

                @current_cmd = command

                # Clear the queue if required (useful for emergency stops etc)
                if command[:clear_queue]
                    @queue.cancel_all("Command #{command[:name]} cleared the queue")
                end

                # Perform the transmit
                transmitted = @transport.transmit(command)
                @last_sent_at = current_time

                # Disconnect if the transmit is taking longer than the response timeout
                @timeout = schedule.in(command[:timeout], proc { |time, sched|
                    transmit_failure(command, :transmit_timeout)
                })

                # if the command is waiting for a response (after transmit)
                # * setup processing timeout (device might send multiple responses that are ignored)
                # else
                # * request the next command
                transmitted.then do
                    @timeout.cancel

                    if command[:wait]
                        @timeout = schedule.in(command[:timeout], @resp_failure)
                    else
                        # resolve the send promise early as we are not waiting for the response
                        command[:defer].resolve(:no_wait)
                        ready_next(command)
                    end

                    command[:defer].promise.finally do
                        call_emit command
                    end
                end

                # Disconnect if transmit failed
                transmitted.catch do |reason|
                    transmit_failure(command, reason)
                end

                nil # ensure promise chain is not propagated
            end

            def ready_next(old_cmd)
                clear_timeout
                @current_cmd = nil

                delay = old_cmd[:delay]
                if delay && delay > 0
                    gap = @last_sent_at + delay - @thread.now
                    if gap > 0
                        @delay_timer = schedule.in(gap) do
                            @delay_timer = nil
                            @queue.pop(@transport_send)
                        end
                    else
                        @queue.pop(@transport_send)
                    end
                else
                    @queue.pop(@transport_send)
                end
            end

            def clear_timeout
                @timeout.cancel if @timeout
                @timeout = nil
            end

            def transmit_failure(cmd, reason)
                clear_timeout
                transport.disconnect

                ready_next cmd if @current_cmd.nil?

                resp_failure reason
            end

            # =================
            # END COMMAND QUEUE
            # =================
        end
    end
end
