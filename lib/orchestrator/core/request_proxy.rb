module Orchestrator
    module Core
        PROTECTED = ::ThreadSafe::Cache.new
        PROTECTED[:unsubscribe] = true
        PROTECTED[:subscribe] = true
        PROTECTED[:schedule] = true
        PROTECTED[:systems] = true
        #PROTECTED[:setting] = true # settings might be useful
        PROTECTED[:system] = true
        PROTECTED[:logger] = true
        PROTECTED[:task] = true
        PROTECTED[:wake_device] = true

        # Object functions
        PROTECTED[:__send__] = true
        PROTECTED[:public_send] = true
        PROTECTED[:taint] = true
        PROTECTED[:untaint] = true
        PROTECTED[:trust] = true
        PROTECTED[:untrust] = true
        PROTECTED[:freeze] = true

        # Callbacks
        PROTECTED[:on_load] = true
        PROTECTED[:on_unload] = true
        PROTECTED[:on_update] = true
        PROTECTED[:connected] = true
        PROTECTED[:disconnected] = true
        PROTECTED[:received] = true

        # Device module
        PROTECTED[:send] = true
        PROTECTED[:defaults] = true
        PROTECTED[:disconnect] = true
        PROTECTED[:config] = true

        # Service module
        PROTECTED[:get] = true
        PROTECTED[:put] = true
        PROTECTED[:post] = true
        PROTECTED[:delete] = true
        PROTECTED[:request] = true
        PROTECTED[:clear_cookies] = true
        PROTECTED[:use_middleware] = true


        class RequestProxy
            def initialize(thread, mod)
                @mod = mod
                @thread = thread
            end

            # Simplify access to status variables as they are thread safe
            def [](name)
                @mod.instance[name]
            end

            def []=(status, value)
                @mod.instance[status] = value
            end

            # Returns true if there is no object to proxy
            #
            # @return [true|false]
            def nil?
                @mod.nil?
            end

            # Returns true if the module responds to the given method
            #
            # @return [true|false]
            def respond_to?(symbol, include_all = false)
                if @mod
                    @mod.instance.respond_to?(symbol, include_all)
                else
                    false
                end
            end

            # All other method calls are wrapped in a promise
            def method_missing(name, *args, &block)
                defer = @thread.defer

                if @mod.nil?
                    err = Error::ModuleUnavailable.new "method '#{name}' request failed as the module is not available at this time"
                    defer.reject(err)
                    # TODO:: debug log here
                elsif ::Orchestrator::Core::PROTECTED[name]
                    err = Error::ProtectedMethod.new "attempt to access module '#{@mod.settings.id}' protected method '#{name}'"
                    defer.reject(err)
                    @mod.logger.warn(err.message)
                else
                    @mod.thread.schedule do
                        begin
                            defer.resolve(
                                @mod.instance.public_send(name, *args, &block)
                            )
                        rescue => e
                            @mod.logger.print_error(e)
                            defer.reject(e)
                        end
                    end
                end

                defer.promise
            end
        end
    end
end
