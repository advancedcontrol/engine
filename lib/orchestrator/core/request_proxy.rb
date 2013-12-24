module Orchestrator
    module Core
        PROTECTED = ::ThreadSafe::Cache.new
        PROTECTED[:unsubscribe] = true
        PROTECTED[:subscribe] = true
        PROTECTED[:schedule] = true
        PROTECTED[:systems] = true
        PROTECTED[:system] = true
        PROTECTED[:task] = true
        PROTECTED[:send] = true


        class RequestProxy
            def initialize(thread, mod)
                @mod = mod
                @thread = thread
            end

            def method_missing(name, *args, &block)
                defer = @thread.defer

                if ::Orchestrator::Core::PROTECTED[name]
                    defer.reject(:protected)
                else
                    @mod.thread.schedule do
                        begin
                            defer.resolve(
                                @mod.instance.__send__(name, *args, &block)
                            )
                        rescue Exception => e
                            defer.reject(e)
                        end
                    end
                end

                defer.promise
            end
        end
    end
end
