require 'libuv'
require 'orchestrator/resolver'

describe "Looking up a hostname" do
    before :each do
        @loop = ::Libuv::Loop.new


        @tickcount = 0
        @check = @loop.check
        @check.progress do
            @tickcount += 1
        end
        @check.start


        @deferred = @loop.defer
        @promise = @deferred.promise
        @promise.catch do |error|
            @log << error
        end
        @promise.finally do
            @loop.stop
        end


        @log = []
    end


    it "should resolve an IP addresses without delay" do
        @loop.run do
            Orchestrator::Resolver.lookup(@deferred, '::1')
            @promise.then do |result|
                @result = result
            end
        end

        @log.should == []
        ['::1', '127.0.0.1'].should include(@result)
        @tickcount.should == 2
    end

    it "should resovle a hostname on a seperate thread", :network => true do
        @loop.run do
            Orchestrator::Resolver.lookup(@deferred, 'google.com')
            @promise.then do |result|
                @result = result
            end
        end

        @log.should == []
        @result.nil?.should == false
        @result.class.should == String
        @tickcount.should > 2
    end

    it "should reject invalid hostnames on a seperate thread", :network => true do
        @loop.run do
            Orchestrator::Resolver.lookup(@deferred, 'notgoogle')
            @promise.then do |result|
                @result = result
            end
        end

        @log.length.should == 1
        @result.nil?.should == true
        @tickcount.should > 2
    end
end
