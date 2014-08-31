require 'set'


module Orchestrator
    class Dependency < Couchbase::Model
        design_document :dep
        include ::CouchbaseId::Generator


        ROLES = Set.new([:device, :service, :logic])


        attribute :name
        attribute :role
        attribute :description
        attribute :default # default data (port or URI)

        # Override default role accessors
        def role
            @role ||= self.attributes[:role].to_sym if self.attributes[:role]
        end
        def role=(name)
            @role = name.to_sym
            self.attributes[:role] = name
        end

        attribute :class_name
        attribute :module_name
        attribute :settings,        default: lambda { {} }

        attribute :created_at,      default: lambda { Time.now.to_i }


        # Find the modules that rely on this dependency
        def modules
            ::Orchestrator::Module.dependent_on(self.id)
        end

        def default_port=(port)
            self.role = :device
            self.default = port
        end

        def default_uri=(uri)
            self.role = :service
            self.default = uri
        end


        protected


        # Validations
        validates :name,            presence: true
        validates :class_name,      presence: true
        validates :module_name,     presence: true
        validate  :role_exists


        def role_exists
            if self.role && ROLES.include?(self.role.to_sym)
                self.role = self.role.to_s
            else
                errors.add(:role, 'is not valid')
            end
        end

        # Delete all the module references relying on this dependency
        before_delete :cleanup_modules
        def cleanup_modules
            modules.each do |mod|
                mod.delete
            end
        end
    end
end
