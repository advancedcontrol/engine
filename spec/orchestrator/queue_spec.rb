require 'rails'
require 'orchestrator'

describe "command queue" do
    before :each do
        @loop = ::Libuv::Loop.default
    end

    # Uses promises to pause shifts until any timers
    # have been resolved
    it "should queue and shift until waiting" do
        count = 0
        log = []
        queue = ::Orchestrator::Device::CommandQueue.new(@loop, proc { |cmd|
            count += 1
            if count % 2 == 1
                defer = @loop.defer
                @loop.next_tick do
                    log << cmd[:name]
                    defer.resolve(true)
                end
                defer.promise
            else
                log << cmd[:name]
            end
        })

        @loop.run do
            queue.push({name: :first}, 50)
            queue.push({name: :second}, 50)
            @loop.next_tick do
                queue.push({name: :third, wait: true}, 50)
                @loop.next_tick do
                    queue.push({name: :fourth}, 50)
                    @loop.next_tick do
                        @loop.next_tick do
                            @loop.stop
                        end
                    end
                end
            end
        end

        expect(log).to eq([:first, :second, :third])
    end

    it "should continue processing after waiting" do
        count = 0
        log = []
        queue = ::Orchestrator::Device::CommandQueue.new(@loop, proc { |cmd|
            count += 1
            if count == 3
                log << cmd[:name]
                queue.shift
            else
                defer = @loop.defer
                @loop.next_tick do
                    log << cmd[:name]
                    defer.resolve(true)
                end
                defer.promise
            end
        })

        @loop.run do
            queue.push({name: :first}, 50)
            queue.push({name: :second}, 50)
            @loop.next_tick do
                queue.push({name: :third, wait: true}, 50)
                @loop.next_tick do
                    queue.push({name: :fourth}, 50)
                    @loop.next_tick do
                        @loop.next_tick do
                            @loop.stop
                        end
                    end
                end
            end
        end

        expect(log).to eq([:first, :second, :third, :fourth])
    end

    it "should work with anonymous commands" do
        count = 0
        log = []
        queue = ::Orchestrator::Device::CommandQueue.new(@loop, proc { |cmd|
            count += 1
            if count == 3
                log << cmd[:data]
                queue.shift
            else
                defer = @loop.defer
                @loop.next_tick do
                    log << cmd[:data]
                    defer.resolve(true)
                end
                defer.promise
            end
        })

        @loop.run do
            queue.push({data: :first}, 50)
            queue.push({data: :second}, 50)
            @loop.next_tick do
                queue.push({data: :third, wait: true}, 50)
                @loop.next_tick do
                    queue.push({data: :fourth}, 50)
                    @loop.next_tick do
                        @loop.next_tick do
                            @loop.stop
                        end
                    end
                end
            end
        end

        expect(log).to eq([:first, :second, :third, :fourth])
    end

    it "should save named commands when offline" do
        log = []
        queue = ::Orchestrator::Device::CommandQueue.new(@loop, proc { |cmd|
            defer = @loop.defer
            @loop.next_tick do
                log << cmd[:data]
                defer.resolve(true)
            end
            defer.promise
        })

        @loop.run do
            dummy_defer = @loop.defer

            queue.push({name: :first, wait: true, data: :first}, 50)
            queue.push({data: :second, defer: dummy_defer}, 50)
            queue.push({name: :third, data: :third}, 50)
            queue.push({data: :fourth, defer: dummy_defer}, 50)

            queue.offline

            @loop.next_tick do
                queue.online

                @loop.next_tick do
                    @loop.next_tick do
                        @loop.next_tick do
                            @loop.next_tick do
                                @loop.next_tick do
                                    @loop.stop
                                end
                            end
                        end
                    end
                end
            end
        end

        expect(log).to eq([:first, :third])
    end

    it "should save no commands if cleared" do
        log = []
        queue = ::Orchestrator::Device::CommandQueue.new(@loop, proc { |cmd|
            defer = @loop.defer
            @loop.next_tick do
                log << cmd[:data]
                defer.resolve(true)
            end
            defer.promise
        })

        @loop.run do
            dummy_defer = @loop.defer
            
            queue.push({name: :first, defer: dummy_defer, wait: true, data: :first}, 50)
            queue.push({data: :second, defer: dummy_defer}, 50)
            queue.push({name: :third, defer: dummy_defer, data: :third}, 50)
            queue.push({data: :fourth, defer: dummy_defer}, 50)

            queue.offline(:clear)

            @loop.next_tick do
                queue.online

                @loop.next_tick do
                    @loop.next_tick do
                        @loop.next_tick do
                            @loop.next_tick do
                                @loop.next_tick do
                                    @loop.stop
                                end
                            end
                        end
                    end
                end
            end
        end

        expect(log).to eq([:first])
    end
end
