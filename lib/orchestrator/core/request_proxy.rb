module Orchestrator
    module Core
        PROTECTED = ::ThreadSafe::Cache.new
        PROTECTED[:unsubscribe] = true
        PROTECTED[:subscribe] = true
        PROTECTED[:schedule] = true
        PROTECTED[:systems] = true
        #PROTECTED[:setting] = true # settings might be useful
        PROTECTED[:system] = true
        PROTECTED[:logger] = true
        PROTECTED[:task] = true
        PROTECTED[:wake_device] = true

        # Object functions
        PROTECTED[:__send__] = true
        PROTECTED[:public_send] = true
        PROTECTED[:taint] = true
        PROTECTED[:untaint] = true
        PROTECTED[:trust] = true
        PROTECTED[:untrust] = true
        PROTECTED[:freeze] = true

        # Callbacks
        PROTECTED[:on_load] = true
        PROTECTED[:on_unload] = true
        PROTECTED[:on_update] = true
        PROTECTED[:connected] = true
        PROTECTED[:disconnected] = true
        PROTECTED[:received] = true

        # Device module
        PROTECTED[:send] = true
        PROTECTED[:defaults] = true
        PROTECTED[:disconnect] = true
        PROTECTED[:config] = true

        # Service module
        PROTECTED[:get] = true
        PROTECTED[:put] = true
        PROTECTED[:post] = true
        PROTECTED[:delete] = true
        PROTECTED[:request] = true
        PROTECTED[:clear_cookies] = true
        PROTECTED[:use_middleware] = true


        #
        # This class exists so that we can access regular kernel methods
        class RequestForward
            def initialize(thread, mod, user = nil)
                @mod = mod
                @thread = thread
                @user = user
                @trace = []
            end

            attr_reader :trace

            def request(name, *args, &block)
                defer = @thread.defer

                if @mod.nil?
                    err = Error::ModuleUnavailable.new "method '#{name}' request failed as the module is not available at this time"
                    defer.reject(err)
                    # TODO:: debug log here
                elsif ::Orchestrator::Core::PROTECTED[name]
                    err = Error::ProtectedMethod.new "attempt to access module '#{@mod.settings.id}' protected method '#{name}'"
                    defer.reject(err)
                    @mod.logger.warn(err.message)
                else
                    @trace = caller

                    @mod.thread.schedule do
                        # Keep track of previous in case of recursion
                        previous = nil
                        begin
                            if @user
                                previous = @mod.current_user
                                @mod.current_user = @user
                            end

                            instance = @mod.instance
                            if instance.nil?
                                if @mod.running == false
                                    err = StandardError.new "method '#{name}' request failed as the module '#{@mod.settings.id}'' is currently stopped"
                                    defer.reject(err)
                                else
                                    logger.warn "the module #{@mod.settings.id} is currently stopped however should be running. Attempting restart"
                                    if @mod.start
                                        defer.resolve(@mod.instance.public_send(name, *args, &block))
                                    else
                                        err = StandardError.new "method '#{name}' request failed as the module '#{@mod.settings.id}'' failed to start"
                                        defer.reject(err)
                                    end
                                end
                            else
                                defer.resolve(instance.public_send(name, *args, &block))
                            end
                        rescue => e
                            @mod.logger.print_error(e, '', @trace)
                            defer.reject(e)
                        ensure
                            @mod.current_user = previous if @user
                        end
                    end
                end

                defer.promise
            end

            def respond_to?(symbol, include_all)
                if @mod
                    @mod.instance.respond_to?(symbol, include_all)
                else
                    false
                end
            end
        end


        # By using basic object we should be almost perfectly proxying the module code
        class RequestProxy < BasicObject
            def initialize(thread, mod, user = nil)
                @mod = mod
                @forward = RequestForward.new(thread, mod, user)
            end


            def trace
                @forward.trace
            end


            # Simplify access to status variables as they are thread safe
            def [](name)
                @mod.instance[name]
            end

            def []=(status, value)
                @mod.instance[status] = value
            end

            # Returns true if there is no object to proxy
            #
            # @return [true|false]
            def nil?
                @mod.nil?
            end

            # Returns true if the module responds to the given method
            #
            # @return [true|false]
            def respond_to?(symbol, include_all = false)
                @forward.respond_to?(symbol, include_all)
            end

            # Looks up the arity of a method
            def arity(method)
                @mod.instance.method(method.to_sym).arity
            end


            # All other method calls are wrapped in a promise
            def method_missing(name, *args, &block)
                @forward.request(name.to_sym, *args, &block)
            end
        end
    end
end
