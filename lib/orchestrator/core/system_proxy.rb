require 'set'


module Orchestrator
    module Core
        class SystemProxy
            def initialize(thread, sys_id)
                @system = sys_id
                @thread = thread
            end

            def set(mod, index = 1)
                index -= 1  # Get the real index
                name = mod.to_sym

                RequestProxy.new(@thread, system.get(name, index))
            end

            def all(mod)
                name = mod.to_sym
                RequestsProxy.new(@thread, system.all(name))
            end

            def count(mod)
                name = mod.to_sym
                system.count(name)
            end

            def modules
                system.modules
            end


            protected


            def system
                ::Orchestrator::System.get(@system)
            end
        end
    end
end
