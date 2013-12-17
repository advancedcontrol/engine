require 'addressable/uri'


module Orchestrator
    class Module < Couchbase::Model
        design_document :mod
        include ::CouchbaseId::Generator


        # The classes / files that this module requires to execute
        # Defines module type
        # Requires dependency_id to be set
        belongs_to :dependency, :class_name => "Orchestrator::Dependency"
        belongs_to :control_system, :class_name => "Orchestrator::ControlSystem"


        # Device module
        def hostname; ip; end
        def hostname=(name); ip = name; end
        attribute :ip
        attribute :tls
        attribute :udp
        attribute :port
        attribute :makebreak,   default: false

        # HTTP Service module
        attribute :uri

        # Custom module names (in addition to what is defined in the dependency)
        attribute :priority,    default: 0
        attribute :settings,    default: lambda { {} }
        attribute :names,       default: lambda { [] }

        attribute :created_at,  default: lambda { Time.now.to_i }
        attribute :role         # cache the dependency role locally for load order


        # Loads all the modules for this node
        def self.all
            # ascending order by default (device, service then logic)
            by_module_type
        end
        view :by_module_type


        protected


        validates :dependency, presence: true
        validate  :configuration


        def configuration
            case dependency.role
            when :device
                self.role = 1
                begin
                    url = Addressable::URI.parse("http://#{self.ip}:#{self.port}/")
                    url.scheme && url.host && url
                rescue
                    errors.add(:ip, 'address / hostname or port are not valid')
                end
            when :service
                self.role = 2
                begin
                    url = Addressable::URI.parse(self.uri)
                    url.scheme && url.host && url
                rescue
                    errors.add(:uri, 'is an invalid URI')
                end
            else # logic
                self.role = 3
                if control_system.nil?
                    errors.add(:control_system, 'must be associated')
                end
            end
        end
    end
end
