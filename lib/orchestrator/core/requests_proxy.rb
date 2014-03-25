module Orchestrator
    module Core
        class RequestsProxy
            def initialize(thread, modules)
                if modules.nil?
                    @modules = []
                else
                    @modules = modules.is_a?(Array) ? modules : [modules]
                end
                @thread = thread
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
