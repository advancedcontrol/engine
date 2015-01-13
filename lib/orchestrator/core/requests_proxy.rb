require 'forwardable'

module Orchestrator
    module Core
        class RequestsProxy
            extend Forwardable

            
            def initialize(thread, modules, user = nil)
                if modules.nil?
                    @modules = []
                else
                    @modules = modules.is_a?(Array) ? modules : [modules]
                end
                @thread = thread
                @user = user
                @trace = []
            end


            attr_reader :trace


            # Provide Enumerable support
            def each
                return enum_for(:each) unless block_given?

                @modules.each do |mod|
                    yield RequestProxy.new(@thread, mod, @user)
                end
            end

            # Provide some helper methods
            def_delegators :@modules, :count, :length, :empty?, :each_index

            def last
                mod = @modules.last
                return nil unless mod
                return RequestProxy.new(@thread, mod, @user)
            end

            def first
                mod = @modules.first
                return nil unless mod
                return RequestProxy.new(@thread, mod, @user)
            end

            def [](index)
                mod = @modules[index]
                return nil unless mod
                return RequestProxy.new(@thread, mod, @user)
            end
            alias_method :at, :[]

            # Returns true if there is no object to proxy
            # Allows RequestProxy and RequestsProxy to be used interchangably
            #
            # @return [true|false]
            def nil?
                @modules.empty?
            end


            def method_missing(name, *args, &block)
                if ::Orchestrator::Core::PROTECTED[name]
                    err = Error::ProtectedMethod.new "attempt to access a protected method '#{name}' in multiple modules"
                    ::Libuv::Q.reject(@thread, err)
                    # TODO:: log warning err.message
                else
                    @trace = caller

                    promises = @modules.map do |mod|
                        defer = mod.thread.defer
                        mod.thread.schedule do
                            # Keep track of previous in case of recursion
                            previous = nil
                            begin
                                if @user
                                    previous = mod.current_user
                                    mod.current_user = @user
                                end

                                defer.resolve(
                                    mod.instance.public_send(name, *args, &block)
                                )
                            rescue => e
                                mod.logger.print_error(e, '', @trace)
                                defer.reject(e)
                            ensure
                                mod.current_user = previous if @user
                            end
                        end
                        defer.promise
                    end

                    @thread.finally(*promises)
                end
            end
        end
    end
end
