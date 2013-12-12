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
			app.config.automate = ActiveSupport::OrderedOptions.new
			app.config.orchestrator.module_paths = []

			# Clearance levels defined in code
			app.config.orchestrator.clearance_levels = Set.new([:Admin, :Support, :User, :Public])
			app.config.orchestrator.default_clearance = :User		# Functions not given a clearance level are assumed User level
			app.config.orchestrator.untrusted_clearance = :Public	# Default clearance is not given to untrusted parties

			# if not zero all UDP sockets must be transmitted from a single thread
			app.config.automate.datagram_port = 0	# ephemeral port (random selection)
		end
		
		#
		# Discover the possible module location paths after initialisation is complete
		#
		config.after_initialize do |app|
			
			app.config.assets.paths.each do |path|
				Pathname.new(path).ascend do |v|
					if ['app', 'vendor'].include?(v.basename.to_s)
						app.config.automate.module_paths << "#{v.to_s}/modules"
						break
					end
				end
			end
			
			app.config.automate.module_paths.uniq!

			# TODO:: Start the control system

		end
	end
end
