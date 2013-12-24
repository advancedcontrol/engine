require 'set'


module Orchestrator
    Subscription = Struct.new(:sys_name, :sys_id, :mod_name, :mod_id, :index, :status, :callback, :on_thread) do
        def initialize(*args)
            super(*args)

            @do_callback = method(:do_callback)
        end

        def notify(update)
            if update != @last_update
                @last_update = update
                on_thread.schedule @do_callback
            end
        end

        def value
            @last_update
        end


        protected


        # This is always called on the subscribing thread
        def do_callback
            callback.call(self)
        end
    end

    class Status
        def initialize(thread)
            @thread = thread
            @controller = ::Orchestrator::Control.instance

            @find_subscription = method(:find_subscription)

            # {:mod_id => {status => Subscriptions}}
            @subscriptions = {}
            # {:system_id => Subscriptions}
            @systems = {}
        end


        attr_reader :thread


        # Subscribes to updates from a system module
        # Modules do not have to exist and updates will be triggered as soon as they are
        def subscribe(opt)     # sys_name, mod_name, index, status, callback, on_thread
            if opt[:sys_name] && !opt[:sys_id]
                @thread.work(proc {
                    id = ::Orchestrator::ControlSystem.bucket.get("sysname-#{sys_name}")
                    opt[:sys_id] = id

                    # Grabbing system here as thread-safe and has the potential to block
                    ::Orchestrator::System.get(id)
                }).then(proc { |sys|
                    mod = sys.get(opt[:mod_name], opt[:index] - 1)
                    if mod
                        opt[:mod_id] = mod.settings.id.to_sym
                        opt[:mod] = mod
                    end

                    do_subscribe(opt)
                })
            else
                do_subscribe(opt)
            end
        end

        # Removes subscription callback from the lookup
        def unsubscribe(sub)
            if sub.is_a? ::Libuv::Q::Promise 
                sub.then @find_subscription
            else
                find_subscription(opt)
            end
        end

        # Triggers an update to be sent to listening callbacks
        def update(mod_id, status, value)
            mod = @subscriptions[mod_id]
            if mod
                subscribed = mod[status]
                if subscribed
                    subscribed.each do |subscription|
                        subscription.notify(value)
                    end
                end
            end
        end

        # TODO:: we also need the system class to contact each of the threads
        def reloaded_system(sys_id)
            subscriptions = @systems[sys_id]
            if subscriptions
                sys = ::Orchestrator::System.get(@system)

                subscriptions.each do |sub|
                    old_id = sub.mod_id

                    # re-index the subscription
                    mod = sys.get(sub.mod_name, sub.index - 1)
                    sub.mod_id = mod ? mod.settings.id.to_sym : nil

                    # Check for changes (order, removal, replacement)
                    if old_id != sub.mod_id
                        @subscriptions[old_id][sub.status].delete(sub)

                        # Update to the new module
                        if sub.mod_id
                            @subscriptions[sub.mod_id] ||= {}
                            @subscriptions[sub.mod_id][sub.status] ||= Set.new
                            @subscriptions[sub.mod_id][sub.status].add(sub)

                            # Check for existing status to send to subscriber
                            value = mod.status[sub.status]
                            sub.notify(value) if value
                        end

                        # Perform any required cleanup
                        if @subscriptions[old_id][sub.status].empty?
                            @subscriptions[old_id].delete(sub.status)
                            if @subscriptions[old_id].empty?
                                @subscriptions.delete(old_id)
                            end
                        end
                    end
                end
            end
        end


        # NOTE:: Only to be called from subscription thread
        def exec_unsubscribe(sub)
            # Update the system lookup if a system was specified
            if sub.sys_id
                subscriptions = @systems[sub.sys_id]
                if subscriptions
                    subscriptions.delete(sub)

                    if subscriptions.empty?
                        @systems.delete(sub.sys_id)
                    end
                end
            end

            # Update the module lookup
            statuses = @subscriptions[sub.mod_id]
            if statuses
                subscriptions = statuses[sub.status]
                if subscriptions
                    subscriptions.delete(sub)

                    if subscriptions.empty?
                        statuses.delete(sub.status)

                        if statuses.empty?
                            @subscriptions.delete(sub.mod_id)
                        end
                    end
                end
            end
        end


        protected


        def do_subscribe(opt)
            # Build the subscription object (as loosely coupled as we can)
            sub = Subscription.new(opt[:sys_name], opt[:sys_id], opt[:mod_name], opt[:mod_id], opt[:index], opt[:status], opt[:callback], opt[:on_thread])

            if sub.sys_id
                @systems[sub.sys_id] ||= Set.new
                @systems[sub.sys_id].add(sub)
            end

            # Now if the module is added later we'll still receive updates
            # and also support direct module status bindings
            if sub.mod_id
                @subscriptions[sub.mod_id] ||= {}
                @subscriptions[sub.mod_id][sub.status] ||= Set.new
                @subscriptions[sub.mod_id][sub.status].add(sub)

                # Check for existing status to send to subscriber
                value = opt[:mod].status[sub.status]
                sub.notify(value) if value
            end

            # return the subscription
            sub
        end

        def find_subscription(sub)
            # Find module thread
            if sub.mod_id
                manager = @controller.loaded?(sub.mod_id)
                if manager
                    thread = manager.thread
                    thread.schedule do
                        thread.observer.exec_unsubscribe(sub)
                    end
                else
                    # NOTE:: Probably not required
                    exec_unsubscribe(sub)
                end
            else
                exec_unsubscribe(sub)
            end
        end
    end
end

module Libuv
    class Loop
        def observer
            @observer ||= ::Orchestrator::Status.new(@loop)
            @observer
        end
    end
end
