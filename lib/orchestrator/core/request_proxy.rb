module Orchestrator
    module Core
        class RequestProxy
            def initialize(thread, mod)
                @mod = mod
                @thread = thread
            end

            def method_missing(name, *args, &block)
                defer = @thread.defer

                @mod.thread.schedule do
                    begin
                        defer.resolve(
                            @mod.instance.__send__(name, *args, &block)
                        )
                    rescue Exception => e
                        defer.reject(e)
                    end
                end

                defer.promise
            end
        end
    end
end
