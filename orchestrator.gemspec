# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib', __FILE__)
require 'orchestrator/version'

Gem::Specification.new do |s|
    s.name        = 'orchestrator'
    s.version     = Orchestrator::VERSION
    s.authors     = ['Stephen von Takach']
    s.email       = ['steve@cotag.me']
    s.license     = 'MIT'
    s.homepage    = 'https://bitbucket.org/aca/control'
    s.summary     = 'A distributed system for building automation'
    s.description = 'A building automation system.'

    s.add_dependency 'rake'
    s.add_dependency 'libuv'              # High performance IO reactor for ruby
    s.add_dependency 'uv-rays'            # Evented networking library
    s.add_dependency 'addressable'        # IP address utilities
    s.add_dependency 'systemu'            # MAC address utilities
    s.add_dependency 'algorithms'         # Priority queue
    s.add_dependency 'couchbase-id'       # ID generation

    s.add_development_dependency 'rspec'    # Testing framework
    s.add_development_dependency 'yard'     # Comment based documentation generation
    

    s.files = Dir["{lib,app,config}/**/*"] + %w(Rakefile orchestrator.gemspec README.md LICENSE)
    s.test_files = Dir['spec/**/*']
    s.extra_rdoc_files = ['README.md']

    s.require_paths = ['lib']
end
