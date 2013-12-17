require 'set'


module Orchestrator
	class Engine < ::Rails::Engine
		isolate_namespace Orchestrator
		
		
		rake_tasks do
			load "tasks/orchestrator_tasks.rake"
		end
		
		#
		# Define the application configuration
		#
		config.before_initialize do |app|						# Rails.configuration
			app.config.orchestrator = ActiveSupport::OrderedOptions.new
			app.config.orchestrator.module_paths = []

			# Clearance levels defined in code
			app.config.orchestrator.clearance_levels = Set.new([:Admin, :Support, :User, :Public])

			# Set these to be the same to enforce explicit clearance levels
			app.config.orchestrator.default_clearance = :User		# Functions not given a clearance level are assumed User level
			app.config.orchestrator.untrusted_clearance = :Public	# Default clearance is not given to untrusted parties

			# if not zero all UDP sockets must be transmitted from a single thread
			app.config.orchestrator.datagram_port = 0	# ephemeral port (random selection)
		end
		
		#
		# Discover the possible module location paths after initialisation is complete
		#
		config.after_initialize do |app|
			
			app.config.assets.paths.each do |path|
				Pathname.new(path).ascend do |v|
					if ['app', 'vendor'].include?(v.basename.to_s)
						app.config.orchestrator.module_paths << "#{v.to_s}/modules"
						break
					end
				end
			end
			
			app.config.orchestrator.module_paths.uniq!

			# Force design documents
			temp = ::Couchbase::Model::Configuration.design_documents_paths
			::Couchbase::Model::Configuration.design_documents_paths = [File.expand_path(File.join(File.expand_path("../", __FILE__), '../../app/models/orchestrator'))]
        	::Orchestrator::Module.ensure_design_document!
        	::Couchbase::Model::Configuration.design_documents_paths = temp

			# Start the control system by initializing it
			Control.instance
		end
	end
end
