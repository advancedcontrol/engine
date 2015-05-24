
module Orchestrator
    class TriggerInstance < Couchbase::Model
        design_document :trig
        include ::CouchbaseId::Generator

        belongs_to :control_system, :class_name => "Orchestrator::ControlSystem".freeze
        belongs_to :trigger, :class_name => "Orchestrator::Trigger".freeze

        attribute :created_at, default: lambda { Time.now.to_i }
        attribute :enabled,    default: true
        attribute :triggered,  default: false
        attribute :important,  default: false

        attribute :debounce_period, default: 0


        def name
            trigger.name
        end

        def description
            trigger.description
        end

        def conditions
            trigger.conditions
        end

        def actions
            trigger.actions
        end


        DEFAULT_JSON_METHODS = [
            :name,
            :description,
            :conditions,
            :actions
        ].freeze
        def serializable_hash(options = {})
            options = options || {}
            options[:methods] = DEFAULT_JSON_METHODS
            super
        end


        protected


        # Validate that
        # * there are some conditions entered
        # * there are some actions entered
    end
end
