
module Orchestrator
    module Triggers
        class Module
            include ::Orchestrator::Constants

            def on_load
                @subscriptions = []
                @schedules = []

                @triggers = []     # Trigger instance objects
                @conditions = {}   # State objects by trigger name

                on_update
            end

            def on_update
                sys_id = system.id
                result = task {
                    triggers = Trigger.for(sys_id).to_a
                    triggers.each(&:name) # Load the parent model
                    triggers
                }
                result.then method(:update)
            end


            protected


            def update(triggers)
                @triggers = triggers

                # unsubscribe
                @subscriptions.each do |sub|
                    unsubscribe sub
                end
                @subscriptions = []

                # stop any schedules
                @conditions.each_value(&:destroy)
                @conditions = {}

                # create new trigger objects
                # with current status values
                sys_proxy = system
                callback = method(:callback)
                triggers.each do |trig|
                    state = State.new(trig, schedule, callback)
                    @conditions[trig.name] = state

                    # subscribe to status variables and
                    # map any existing status into the triggers
                    state.subscriptions.each do |sub|
                        @subscriptions << subscribe(sys_proxy, state, sub[:mod], sub[:index], sub[:status])
                    end

                    # enable the triggers
                    state.enable(trig.enabled)
                end
            end

            def subscribe(sys_proxy, state, mod, index, status)
                sub = sys_proxy.subscribe(mod, index, status) do |update|
                    # TODO:: update the state var
                end
                sub
            end

            def callback(name, state)

            end
        end
    end
end
