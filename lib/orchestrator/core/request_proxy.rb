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
        PROTECTED[:send] = true

        # Callbacks
        PROTECTED[:on_load] = true
        PROTECTED[:on_unload] = true
        PROTECTED[:received] = true



        class RequestProxy
            def initialize(thread, mod)
                @mod = mod
                @thread = thread
            end

            def method_missing(name, *args, &block)
                defer = @thread.defer

                if ::Orchestrator::Core::PROTECTED[name]
                    err = Error::ProtectedMethod.new "attempt to access module '#{@mod.settings.id}' protected method '#{name}'"
                    defer.reject(err)
                    @mod.logger.warn(err.message)
                elsif @mod.nil?
                    err = Error::ModuleUnavailable.new "method '#{name}' request failed as the module is not available at this time"
                    defer.reject(err)
                    # TODO:: debug log here
                else
                    @mod.thread.schedule do
                        begin
                            defer.resolve(
                                @mod.instance.__send__(name, *args, &block)
                            )
                        rescue Exception => e
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
