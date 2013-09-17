module Orchestrator
    class Scheduler

        # @abstract
        class Job < ::Libuv::Timer
            attr_reader :created
            attr_reader :last_scheduled
            attr_reader :last_triggered
            attr_reader :tags
            attr_reader :name


            # Valid options: tags, edge (:trailing or :leading), name, stopped, blocking (serialised)
            def initialize(loop, options = {})
                @name = options[:name]
                @tags = options[:tags] || []
                @blocking = options[:blocking]

                # init the promise
                super(loop, self.method(:trigger))

                # Create the work object
                progress options[:task]

                # start processing
                @created = @loop.now
                schedule_next unless options[:stopped]
            end

            def start
                schedule_next if @stopped
            end

            def trigger
                @last_triggered = @loop.now
                if @blocking
                    result
                    begin
                        result = ::Libuv::Q::ResolvedPromise.new(@loop, @callable.call)
                    rescue Exception => e
                        result = ::Libuv::Q::ResolvedPromise.new(@loop, e, true)
                    ensure
                        @defer.notify(result, @last_scheduled, @last_triggered)
                    end
                else
                    @work = @loop.work @callable
                    @work.finally do
                        @defer.notify(@work, @last_scheduled, @last_triggered)
                    end
                end
                schedule_next
            end

            def progress(callback = nil, &blk)
                @callable = if task.respond_to?(:arity)
                    task
                elsif task.respond_to?(:call)
                    task.method(:call)
                elsif task.is_a?(Class)
                    @handler = task.new
                    @handler.method(:call) rescue nil
                else
                    nil
                end
            end

            def unschedule
                close
            end
        end


        class OneTimeJob < Job
            def initialize(loop, time, options = {})
                @time = time
                super(loop, options)
            end


            protected


            def schedule_next
                if @time
                    @last_scheduled = @loop.now
                    start(@time)
                    @time = nil
                else
                    close   # Should only ever run once
                end
            end
        end


        class RepeatJob < Job
            def initialize(loop, time, options = {})
                @stop_after = options[:stop_after]
                @stop_at = options[:stop_at]
                @run_count = 0
                @time = time
                super(loop, options)
            end


            protected


            def schedule_next
                if @stop_at <= (@loop.now + @time)
                    close
                elsif @run_count >= @stop_after
                    close
                else
                    @run_count += 1
                    @last_scheduled = @loop.now
                    start(@time) if @stopped
                end
            end
        end


        class CronJob < RepeatJob
            def initialize(loop, cron, options = {})
                @cron = cron
                super(loop, 0, options)
            end


            protected


            def schedule_next
                @time = @cron.next
                super
            end
        end
    end
end
