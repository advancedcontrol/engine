require 'uv-priority-queue'
require 'set'


# Transport -> connection (make break etc)
# * attach connected, disconnected callbacks
# * udp, makebreak and tcp transports
# Manager + CommandProcessor + Transport


module Orchestrator
    module Device
        class Processor
            include ::Orchestrator::Transcoder


            SEND_DEFAULTS = {
                wait: true,                 # wait for a response before continuing with sends
                delay: 0,                   # make sure sends are separated by at least this (in milliseconds)
                delay_on_receive: 0,        # delay the next send by this (milliseconds) after a receive
                max_waits: 3,               # number of times we will ignore valid tokens before retry
                retries: 2,                 # Retry attempts before we give up on the command
                hex_string: false,          # Does the input need conversion
                timeout: 5,                 # Time we will wait for a response
                priority: 50,               # Priority of a send
                retry_on_disconnect: true,  # Re-queue the command if disconnected?
                force_disconnect: false     # Mainly for use with make and break

                # Other options include:
                # * emit (creates a promise and resolves with the desired status)
                # * callback (alternative to received function)
            }

            CONFIG_DEFAULTS = {
                tokenize: false,    # If replaced with a callback can define custom tokenizers
                size_limit: 524288, # 512kb buffer max
                clear_queue_on_disconnect: :unnamed,
                flush_buffer_on_disconnect: true,
                priority_bonus: 20,  # give commands bonus priority under certain conditions
                update_status: true  # auto update connected status?

                # Other options include:
                # * inactivity_timeout (used with make and break)
                # * delimiter (string or regex to match message end)
                # * indicator (string or regex to match message start)
                # * verbose (throw errors or silently recover)
            }


            SUCCESS = Set.new([true, :success, nil, :ignore])
            FAILURE = Set.new([false, :retry, :failed, :abort])
            DUMMY_RESOLVER = proc {}


            attr_reader :config, :queue


            # init -> mod.load -> post_init
            # So config can be set in on_load if desired
            def initialize(man)
                @man = man

                @loop = @man.thread
                @logger = @man.logger
                @defaults = SEND_DEFAULTS.dup
                @config = SEND_DEFAULTS.dup

                @queue = CommandQueue(@loop, method(:send_next))
                @bonus = 0

                # Used to indicate when we can start the next response processing
                @head = ::Libuv::Q::ResolvedPromise.new(@loop, true)
                @tail = ::Libuv::Q::ResolvedPromise.new(@loop, true)

                # Method variables
                @resp_success = method(:resp_success)
                @resp_failure = method(:resp_failure)
                @resolver = proc { |resp| @loop.schedule { resolve_callback(resp) } }
            end

            def post_init(transport)
                @transport = transport
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

                @queue.push(options, options[:priority] + @bonus)

            rescue Exception => e
                @logger.print_error(e, 'error queuing command')
            end

            ##
            # Callbacks -------------------------
            def connected
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
                @man.notify_disconnected
                if @config[:update_status]
                    @man.trak(:connected, false)
                end
                if @config[:flush_buffer_on_disconnect]
                    check_data(@buffer.flush)
                end
                @buffer = nil
            end

            def buffer(data)
                if @buffer
                    @buffer.extract(data).each &method(:check_data)
                else
                    check_data(data)
                end
            end


            ##
            # Helper functions ------------------
            def send_options(options)
                @defaults.merge!(options)
            end

            def config(options)
                @config.merge!(options)
            end


            protected


            # Callback for queued commands
            def send_next(command)
                data = command[:data]
                # TODO:: Check pre-send timer conditions
                @transport.send(data)
                # TODO:: Set checkpoints for any post-send timer conditions
                if @queue.wait
                    # TODO:: Set up timers using schedule for timeouts
                end
            end

            # Check transport response data
            def check_data(data)
                resp = nil

                # Provide commands with a bonus in this section
                @bonus = @config[:priority_bonus]

                begin
                    if @queue.wait
                        @defer = @loop.defer
                        @defer.then @resp_success, @resp_failure

                        # Send response, early resolver and command
                        resp = @man.notify_received(data, @resolver, @queue.wait)
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
                resolve_callback(resp)
            end

            def resolve_callback(resp)
                if @defer
                    if SUCCESS.include? resp
                        @defer.resolve resp
                    else
                        @defer.reject resp
                    end
                    @defer = nil
                end
            end

            # We only care about queued commands here
            # Promises resolve on the next tick so processing
            #  is guaranteed to have completed
            # Check for queue wait as we may have gone offline
            def resp_success(result)
                if @queue.wait

                end
            end

            def resp_failure(result)
                if @queue.wait

                end
            end
        end
    end
end
