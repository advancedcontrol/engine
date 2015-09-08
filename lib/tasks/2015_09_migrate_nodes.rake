namespace :migrate do

    desc 'Upgrades models to support distributed control'
    task :nodes => :environment do
        # This adds support for statistics collection via elasticsearch
        edges = ::Orchestrator::EdgeControl.all.to_a
        if edges.length <= 1
            edge = edges[0] || ::Orchestrator::EdgeControl.new
            edge.name ||= 'Master Node'
            edge.host_origin ||= 'http://127.0.0.1'
            edge.save!
            puts "Edge node created with id #{edge.id}"

            puts "Migrating modules"
            ::Orchestrator::Module.all.each do |mod|
                mod.edge_id = edge.id
                mod.save!
            end

            puts "Migrating systems"
            ::Orchestrator::ControlSystem.all.each do |sys|
                sys.edge_id = edge.id
                sys.save!
            end
        else
            puts "Multiple edge node models already exist. Aborting migrate"
        end
    end

end
