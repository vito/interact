$:.unshift File.expand_path("../lib", __FILE__)

require 'interact/version'

spec = Gem::Specification.new do |s|
  s.name = "interact"
  s.version = Interact::VERSION
  s.author = "Alex Suraci"
  s.email = "i.am@toogeneric.com"
  s.homepage = "http://github.com/vito/interact"
  s.summary = "A simple API for command-line interaction."
  s.description = "A simple API for command-line interaction. Provides a novel 'rewinding' feature, allowing users to go back in time and re-enter a botched answer. Supports multiple-choice, password prompting, overriding input events, defaults, etc."

  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ["README.md", "LICENSE"]
  s.license = "BSD"
  
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec",   "~> 2.0"

  s.require_path = 'lib'
  s.files = %w(LICENSE README.md Rakefile) + Dir.glob("{lib}/**/*")
end
