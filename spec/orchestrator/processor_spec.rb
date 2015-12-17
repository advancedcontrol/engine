require 'rails'
require 'orchestrator'


class MockDevice
    def initialize(log)
        @log = log
    end

    def received(data, resolve, command)
        if command
            @log << command[:result]
            command[:result]
        else
            @log << data
            :success
        end
    end
end

class MockTransport
    def initialize(thread, log, processor)
        @thread = thread
        @log = log
        @proc = processor
    end

    def disconnect
        @log << :disconnect
    end

    def transmit(cmd)
        @log << cmd[:action]

        case cmd[:action]
        when :success
            defer = @thread.defer
            defer.resolve(true)
            @thread.next_tick do
                @thread.next_tick do
                    @proc.buffer('response')
                end
            end
            return defer.promise
        when :failure
            return ::Libuv::Q.reject(@thread, :before_transmit_error)
        when :dont_respond
            return @thread.defer.promise
        when :delay_response
            # TODO::
        end
    end
end
MockSettings = OpenStruct.new
MockSettings.id = "test"


describe "command queue" do
    before :each do
        @log = []
        @loop = ::Libuv::Loop.default
        @manager = ::Orchestrator::Device::Manager.new(@loop, MockDevice, MockSettings)

        md = MockDevice.new(@log)
        @manager.instance_eval do
            @instance = md
        end

        @proc = ::Orchestrator::Device::Processor.new(@manager)
        @proc.transport = MockTransport.new(@loop, @log, @proc)
        @cmd = {
            action: :success,
            result: :success,
            data: "test",
            defer: @loop.defer,
            on_receive: proc { |data, resolve, command|
                @log << command[:result]
                command[:result]
            }
        }
    end

    it "will accept commands for queuing" do
        @loop.run do
            @proc.queue_command @cmd

            @loop.next_tick do
                @loop.next_tick do
                    @loop.next_tick do
                        @loop.stop
                    end
                end
            end
        end

        expect(@log).to eq([:success, :success])
    end

    it "will process responses before a command is queued" do
        @loop.run do
            @proc.buffer(:whatwhat)
            @proc.queue_command @cmd

            @loop.next_tick do
                @loop.next_tick do
                    @loop.next_tick do
                        @loop.stop
                    end
                end
            end
        end

        expect(@log).to eq([:whatwhat, :success, :success])
    end

    it "will process multiple commands" do
        @loop.run do
            @proc.buffer(:whatwhat)
            @proc.queue_command @cmd
            @proc.queue_command @cmd

            @loop.next_tick do
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

        expect(@log).to eq([:whatwhat, :success, :success, :success, :success])
    end
end
