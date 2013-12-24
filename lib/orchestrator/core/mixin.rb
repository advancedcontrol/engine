module Orchestrator
    module Core
        SCHEDULE_ACCESS_DENIED = 'schedule unavailable in a task'.freeze

        module Mixin

            # Returns a wrapper around a shared instance of ::UV::Scheduler
            # 
            # @return [::Orchestrator::Core::ScheduleProxy]
            def schedule
                raise SCHEDULE_ACCESS_DENIED unless @__config__.thread.reactor_thread?
                @__config__.get_scheduler
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
                thread = @__config__.thread
                defer = thread.defer
                thread.schedule do
                    defer.resolve(thread.work(callback, &block))
                end
                defer.promise
            end

            # Thread safe status access
            def [](name)
                @__config__.status[name.to_sym]
            end

            # thread safe status settings
            def []=(status, value)
                @__config__.trak(status.to_sym, value)
            end

            # thread safe status subscription
            def subscribe(status, callback = nil, &block)
                callback ||= block
                raise 'callback required' unless callback.respond_to? :call

                thread = @__config__.thread
                defer = thread.defer
                thread.schedule do
                    defer.resolve(@__config__.subscribe(status, callback))
                end
                defer.promise
            end

            # thread safe unsubscribe
            def unsubscribe(sub)
                @__config__.thread.schedule do
                    @__config__.unsubscribe(sub)
                end
            end
        end
    end
end
