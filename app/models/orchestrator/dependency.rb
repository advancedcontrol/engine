require 'set'


module Orchestrator
    class Dependency < Couchbase::Model
        include ::CouchbaseId::Generator


        ROLES = Set.new([:device, :service, :logic])


        attribute :name
        attribute :role
        attribute :description

        attribute :class_name
        attribute :module_names,    default: lambda { [] }
        attribute :settings,        default: lambda { {} }

        attribute :created_at,      default: lambda { Time.now.to_i }


        protected


        # Validations
        validates :name,            presence: true
        validates :class_name,      presence: true
        validates :module_names,    presence: true
        validate  :role_exists


        def role_exists
            if self.role && ROLES.include?(self.role.to_sym)
                self.role = self.role.to_s
            else
                errors.add(:role, 'is not a valid security level')
            end
        end
    end
end
