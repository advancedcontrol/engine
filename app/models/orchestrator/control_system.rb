require 'set'


module Orchestrator
    class ControlSystem < Couchbase::Model
        design_document :sys
        include ::CouchbaseId::Generator


        # Allows us to lookup systems by names
        after_save :update_name


        attribute :name
        attribute :description
        attribute :disabled     # prevents load on boot

        attribute :zones,       default: lambda { [] }
        attribute :modules,     default: lambda { [] }
        attribute :settings,    default: lambda { {} }

        attribute :created_at,  default: lambda { Time.now.to_i }


        def name=(new_name)
            @old_name ||= self.attributes[:name] || true
            self.attributes[:name] = new_name
        end


        protected


        # Zones and settings are only required for confident coding
        validates :name,        presence: true
        validates :zones,       presence: true
        validate  :name_unique

        def name_unique
            result = ControlSystem.bucket.get("sysname-#{name}", {quiet: true})
            if result != nil && result != self.id
                errors.add(:name, 'must be unique')
            end
        end

        def update_name
            if @old_name && @old_name != self.name
                ControlSystem.bucket.delete("sysname-#{@old_name}", {quiet: true}) unless @old_name == true
                ControlSystem.bucket.set("sysname-#{self.name}", self.id)
            end
            @old_name = nil
        end
    end
end
