# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib', __FILE__)
require 'orchestrator/version'

Gem::Specification.new do |s|
    s.name        = 'orchestrator'
    s.version     = Orchestrator::VERSION
    s.authors     = ['Stephen von Takach']
    s.email       = ['steve@advancedcontrol.com.au']
    s.license     = 'CC BY-NC-SA'
    s.homepage    = 'https://github.com/advancedcontrol/engine'
    s.summary     = 'A distributed system for building automation'
    s.description = 'A building and Internet of Things automation system'

    s.add_dependency 'rake'
    s.add_dependency 'rails'
    s.add_dependency 'libuv'                # High performance IO reactor for ruby
    s.add_dependency 'oauth'                # OAuth protocol support
    s.add_dependency 'bindata'              # Binary structure support
    s.add_dependency 'uv-rays', '>= 1.3.0'  # Evented networking library
    s.add_dependency 'addressable'          # IP address utilities
    s.add_dependency 'algorithms'           # Priority queue
    s.add_dependency 'couchbase-id'         # ID generation
    s.add_dependency 'elasticsearch'        # Searchable model indexes
    s.add_dependency 'co-elastic-query', '>= 1.0.6'    # Query builder

    s.add_development_dependency 'rspec'    # Testing framework
    s.add_development_dependency 'yard'     # Comment based documentation generation


    s.files = Dir["{lib,app,config}/**/*"] + %w(Rakefile orchestrator.gemspec README.md LICENSE.md)
    s.test_files = Dir['spec/**/*']
    s.extra_rdoc_files = ['README.md']

    s.require_paths = ['lib']
end
