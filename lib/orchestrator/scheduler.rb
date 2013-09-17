require 'set'


module Orchestrator
    
    # Scheduler deals with the timing and management of scheduled work
    class Scheduler
        def initialize(loop)
            @loop = loop
            @jobs = Set.new  # A set of all the active jobs in the system
            @tags = {}       # Sets of tagged jobs
        end

        def in(time, callback = nil, &blk)
            # integer = seconds
            # string to be parsed
        end

        def at(time, callback = nil, &blk)
            # datetime / time
            # string = datetime.parse
        end

        def every(time, callback = nil, &blk)
            # integer = seconds
            # string to be parsed
        end

        def cron(time, callback = nil, &blk)
            # build cron object
        end

        def unschedule(*args)
            if args.length == 0
                # Terminate all jobs
                jobs.each { |j| j.unschedule }
            else
                # Terminate tagged or individual jobs
                args.each do |job|
                    if job.is_a? Symbol
                        jobs = @tags[job]
                        next if jobs.nil?
                        jobs.each { |j| j.unschedule }
                    else
                        job.unschedule
                    end
                end
            end
        end

        def tags
            @tags.keys
        end
    end

end
