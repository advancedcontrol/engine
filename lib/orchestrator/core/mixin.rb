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

                # Check level to speed processing
                if @__config__.logger.level == 0
                    @__config__.logger.debug "Status updated: #{status} = #{value}"
                end
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

            def logger
                @__config__.logger
            end

            def setting(name)
                set = name.to_sym
                @__config__.setting(set)
            end

            # Updates a setting that will effect the local module only
            #
            # @param name [String|Symbol] the setting name
            # @param value [String|Symbol|Numeric|Array|Hash] the setting value
            # @return [::Libuv::Q::Promise] Promise that will resolve once the setting is persisted
            def define_setting(name, value)
                set = name.to_sym
                @__config__.define_setting(set, value)
            end

            def wake_device(mac, ip = '<broadcast>')
                @__config__.thread.schedule do
                    @__config__.thread.wake_device(mac, ip)
                end
            end

            # Outputs any statistics collected on the module
            def __STATS__
                stats = {}
                if @__config__.respond_to? :processor
                    stats[:queue_size] = @__config__.processor.queue.length
                    stats[:queue_waiting] = !@__config__.processor.queue.waiting.nil?
                    stats[:queue_pause] = @__config__.processor.queue.pause
                    stats[:queue_state] = @__config__.processor.queue.state

                    stats[:last_send] = @__config__.processor.last_sent_at
                    stats[:last_receive] = @__config__.processor.last_receive_at
                end

                logger.debug JSON.generate(stats)
            end
        end
    end
end
