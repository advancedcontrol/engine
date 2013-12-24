module Orchestrator
    module Core
        module Mixin

            # Returns a wrapper around a shared instance of ::UV::Scheduler
            # 
            # @return [::Orchestrator::Core::ScheduleProxy]
            def schedule
                @scheduler ||= ::Orchestrator::Core::ScheduleProxy.new(@__config__.thread)
            end

            # Looks up a system based on its name and returns a proxy to that system via a promise
            #
            # @param name [String] the name of the system being accessed
            # @return [::Libuv::Q::Promise] Returns a single promise
            def systems(name)
                task do
                    @__config__.get_system(name)
                end
            end

            # Performs a long running task on a thread pool in parallel.
            #
            # @param callback [Proc] the work to be processed on the thread pool
            # @return [::Libuv::Q::Promise] Returns a single promise
            def task(callback = nil, &block)
                @__config__.thread.work(callback, &block)
            end

            def [](name)
                @__config__.status[name.to_sym]
            end

            def []=(status, value)
                @__config__.trak(status.to_sym, value)
            end

            def subscribe(status, callback = nil, &block)
                @__config__.subscribe(status, callback || block)
            end

            def unsubscribe(sub)
                if sub.is_a? ::Libuv::Q::Promise
                    sub.then do |val|
                        unsubscribe(val)
                    end
                elsif sub.mod_id == @__config__.settings.id.to_sym
                    @__config__.stattrak.exec_unsubscribe(sub)
                else
                    @__config__.stattrak.unsubscribe(sub)
                end
            end
        end
    end
end
