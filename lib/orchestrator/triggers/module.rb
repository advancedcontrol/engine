
module Orchestrator
    module Triggers
        class Module
            include ::Orchestrator::Constants

            def on_load
                @triggers = {}      # Trigger instance objects by id
                @trigger_names = {}
                @conditions = {}    # State objects by trigger id
                @debounce = {}
                @subscriptions = {} # Reference to each subscription
                @updating = Mutex.new

                reload_all
            end

            def reload_all
                return if @reloading
                @reloading = true

                sys_id = system.id
                result = task {
                    triggers = TriggerInstance.for(sys_id).to_a
                    triggers.each(&:name) # Load the parent model
                    triggers
                }
                result.then method(:load_all)
                result.catch do |e|
                    logger.print_error(e, 'error loading system triggers - retrying...')

                    # Random period retry so we don't overwhelm the database
                    schedule.in(3000 + (1 + rand(2500))) do
                        @reloading = false
                        reload_all
                    end
                end
            end

            def reload_id(id)
                thread.work(proc {
                    @updating.synchronize {
                        model = ::Orchestrator::TriggerInstance.find id
                        model.name  # Load the parent model
                        model
                    }
                }).then(proc { |model|
                    # Update the model if it was updated
                    reload(model)
                }, proc { |e|
                    # report any errors updating the model
                    logger.print_error(e, "error loading trigger #{id}")
                })
            end

            def reload(trig)
                # Check trigger belongs to this system
                if system.id == trig.system_id
                    # Unload any previous trigger with the same ID
                    old = @triggers[trig.id]
                    remove(old) if old

                    # Load the new trigger
                    @triggers[trig.id] = trig
                    @trigger_names[trig.name] = trig

                    state = State.new(trig, schedule, method(:callback))
                    @conditions[trig.id] = state

                    subs = []
                    sys_proxy = system
                    state.subscriptions.each do |sub|
                        subs << subscribe(sys_proxy, state, sub[:mod], sub[:index], sub[:status])
                    end
                    @subscriptions[trig.id] = subs

                    # enable the triggers
                    state.enable(trig.enabled)
                end
            end

            def remove(trig)
                @trigger_names.delete(trig.name)
                @subscriptions[trig.id].each do |sub|
                    unsubscribe sub
                end
                @conditions[trig.id].destroy

                timer = @debounce[trig.id]
                timer.cancel if timer

                @triggers.delete(trig.id)
            end

            def run_trigger_action(name)
                trig = @triggers[name] || @trigger_names[name]
                perform_trigger_actions(trig.id)
            end


            protected


            def load_all(triggers)
                @triggers = {}
                @trigger_names = {}

                # unsubscribe
                @subscriptions.each_value do |subs|
                    subs.each do |sub|
                        unsubscribe sub
                    end
                end
                @subscriptions = {}

                # stop any schedules
                @conditions.each_value(&:destroy)
                @conditions = {}

                # stop and debounce timers
                @debounce.each_value(&:cancel)

                # create new trigger objects
                # with current status values
                sys_proxy = system
                callback = method(:callback)
                triggers.each do |trig|
                    @triggers[trig.id] = trig
                    @trigger_names[trig.name] = trig

                    state = State.new(trig, schedule, callback)
                    @conditions[trig.id] = state

                    # subscribe to status variables and
                    # map any existing status into the triggers
                    subs = []
                    state.subscriptions.each do |sub|
                        subs << subscribe(sys_proxy, state, sub[:mod], sub[:index], sub[:status])
                    end
                    @subscriptions[trig.id] = subs

                    # enable the triggers
                    state.enable(trig.enabled)
                end

                @reloading = false
            end

            def subscribe(sys_proxy, state, mod, index, status)
                sub = sys_proxy.subscribe(mod, index, status) do |update|
                    # Update the state var
                    state.set_value(mod, index, status, update.value)
                end
                sub
            end

            # Function called when the trigger state is updated
            def callback(id, state)
                trig = @triggers[id]
                if trig.debounce_period > 0
                    existing = @debounce[id]
                    existing.cancel if existing
                    @debounce[id] = schedule.in(trig.debounce_period * 1000) do
                        @debounce.delete(id)
                        update_model(id, state)
                    end
                else
                    update_model(id, state)
                end
            end

            CAS = 'cas'.freeze
            def update_model(id, state)
                # Access the database in a non-blocking fashion
                thread.work(proc {
                    @updating.synchronize {
                        model = ::Orchestrator::TriggerInstance.find_by_id id

                        if model
                            model.triggered = state
                            model.save!(CAS => model.meta[CAS])
                            model.name  # Load the parent model
                            model
                        else
                            nil
                        end
                    }
                }).then(proc { |model|
                    # Update the model if it was updated
                    if model
                        @triggers[id] = model
                        @trigger_names[model.name] = model
                    else
                        model = @triggers[id]
                        model.triggered = state
                        logger.warn "trigger #{model.id} not found: (#{model.name})"
                    end
                }, proc { |e|
                    # report any errors updating the model
                    logger.print_error(e, 'error updating triggered state in database model')
                }).finally do
                    perform_trigger_actions(id) if state
                end
            end

            def perform_trigger_actions(id)
                model = @triggers[id]
                model.actions.each do |act|
                    begin
                        case act[:type].to_sym
                        when :exec
                            # Execute the action
                            system.get(act[:mod], act[:index]).method_missing(act[:func], *act[:args])
                        when :email
                            # TODO:: provide hooks into action mailer
                        end
                    rescue => e
                        logger.print_error(e, "error performing trigger action #{act} for trigger #{model.id}: #{model.name}")
                    end
                end
            end
        end
    end
end
