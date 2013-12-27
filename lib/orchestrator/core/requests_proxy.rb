module Orchestrator
    module Core
        class RequestsProxy
            def initialize(thread, modules)
                @modules = modules.is_a?(Array) ? modules : [modules]
                @thread = thread
            end

            def method_missing(name, *args, &block)
                if ::Orchestrator::Core::PROTECTED[name]
                    ::Libuv::Q.reject(@thread, :protected)
                    @mod.logger.warn("attempt to access a protected method '#{name}' in multiple modules")
                else
                    promises = @modules.map do |mod|
                        defer = mod.thread.defer
                        mod.thread.schedule do
                            begin
                                defer.resolve(
                                    mod.instance.__send__(name, *args, &block)
                                )
                            rescue Exception => e
                                @mod.logger.print_error(e)
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
