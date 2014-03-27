require 'set'


# Note:: We should be logging the User id in the log
# see: http://pastebin.com/Wrjp8b8e (rails log_tags)
module Orchestrator
    class Logger
        LEVEL = {
            debug: 0,
            info: 1,
            warn: 2,
            error: 3,
            fatal: 4
        }.freeze

        # TODO:: Make this a config item
        DEFAULT_LEVEL = 2

        def initialize(loop, mod)
            @loop = loop
            @mod_id = mod.id
            if mod.respond_to? :dependency
                @klass = mod.dependency.class_name
            else
                @klass = 'User' # Filter by user driven events and behavior
            end
            @level = DEFAULT_LEVEL
            @listeners = Set.new
            @logger = ::Orchestrator::Control.instance.logger
        end

        def level=(level)
            @level = LEVEL[level] || level
        end
        attr_reader :level

        # Add listener
        def add(listener)
            @loop.schedule do
                @listeners.add listener
            end
            listener.promise.finally do
                @loop.schedule do
                    @listeners.delete listener
                end
            end
            listener
        end

        def delete(listener)
            @loop.schedule do
                @listeners.delete listener
                if @listeners.size == 0
                    level = DEFAULT_LEVEL   # back to efficient logging
                end
            end
        end

       
        def debug(msg)
            if @level <= 0
                log(:debug, msg)
            end
        end

        def info(msg)
            if @level <= 1
                log(:info, msg)
            end
        end

        def warn(msg)
            if @level <= 2
                log(:warn, msg)
            end
        end

        def error(msg)
            if @level <= 3
                log(:error, msg)
            end
        end

        def fatal(msg)
            if @level <= 4
                log(:fatal, msg)
            end
        end

        def print_error(e, msg = '')
            msg << "\n#{e.message}"
            msg << "\n#{e.backtrace.join("\n")}" if e.respond_to?(:backtrace) && e.backtrace
            error(msg)
        end


        protected


        def log(level, msg)
            @loop.schedule do
                if LEVEL[level] >= DEFAULT_LEVEL
                    @loop.work do
                        @logger.tagged(@klass, @mod_id) {
                            @logger.send(level, msg)
                        }
                    end
                end
                @listeners.each do |listener|
                    listener.notify(@klass, @mod_id, level, msg)
                end
            end
        end
    end
end
