require 'forwardable'

module Orchestrator
    module Core
        class RequestsProxy
            extend Forwardable

            
            def initialize(thread, modules)
                if modules.nil?
                    @modules = []
                else
                    @modules = modules.is_a?(Array) ? modules : [modules]
                end
                @thread = thread
            end


            # Provide Enumerable support
            def each
                return enum_for(:each) unless block_given?

                @modules.each do |mod|
                    yield RequestProxy.new(@thread, mod)
                end
            end

            # Provide some helper methods
            def_delegators :@modules, :count, :length, :empty?, :each_index

            def last
                mod = @modules.last
                return nil unless mod
                return RequestProxy.new(@thread, mod)
            end

            def first
                mod = @modules.first
                return nil unless mod
                return RequestProxy.new(@thread, mod)
            end

            def [](index)
                mod = @modules[index]
                return nil unless mod
                return RequestProxy.new(@thread, mod)
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
                    promises = @modules.map do |mod|
                        defer = mod.thread.defer
                        mod.thread.schedule do
                            begin
                                defer.resolve(
                                    mod.instance.public_send(name, *args, &block)
                                )
                            rescue => e
                                mod.logger.print_error(e)
                                defer.reject(e)
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
