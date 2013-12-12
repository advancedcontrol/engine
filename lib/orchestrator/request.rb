module Orchestrator
    class Request < ::Libuv::Q::DeferredPromise
        # TODO:: Ruby enum?
        Errors = [:invalid_system_value, :invalid_module_name, :unauthorized]

        def initialize(loop, user, system, mod, func, *args)
            @user = user        # permission level + user details
            @mod_name = mod     # symbol
            @func = func        # symbol
            @args = args        # array

            @system = Systems[system]

            # Initialise the promise
            super(loop, loop.defer)

            # Ensure we execute the request on the correct event loop
            if @system.nil?
                @defer.reject(:invalid_system_value)
            else
                @system.loop.next_tick method(:lookup)
            end
        end

        def lookup
            @mod = @system[@mod_name]
            if @mod.nil?
                @defer.reject(:invalid_module_name)
            else
                @mod.loop.next_tick method(:execute)
            end
        end

        def execute
            if @mod.security_check(@user, @func)
                @defer.resolve(@mod.execute(@func, args))
            else
                @defer.reject(:unauthorized)
            end
        end
    end
end
