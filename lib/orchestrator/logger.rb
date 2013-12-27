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

        def initialize(loop, mod)
            @loop = loop
            @mod_id = mod
            @klass = mod.dependency.class_name
            @level = 3
            @listeners = Set.new
            @logger = ::Orchestrator::Control.instance.logger
        end

        def level=(level)
            @level = LEVEL[level] || level
        end

        # Add listener
        def add(listener)
            @loop.schedule do
                @listeners.add listener
            end
            listener.finally do
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
                    level = 3   # back to efficient logging
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
            msg << "\n#{e.backtrace}" if e.respond_to? :backtrace
            error(msg)
        end


        protected


        def log(level, msg)
            @loop.schedule do
                if LEVEL[level] >= 3
                    @loop.work do
                        @logger.tagged(@klass, @mod_id) {
                            @logger.send(level, msg)
                        }
                    end
                end
                @listeners.each do |listener|
                    listener.notify(@mod_id, level, msg)
                end
            end
        end
    end
end
