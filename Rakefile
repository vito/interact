require 'rake'

task :default => "spec"

desc "Run specs"
task "spec" => ["bundler:install", "test:spec"]

namespace "bundler" do
  desc "Install gems"
  task "install" do
    sh("bundle install")
  end
end

namespace "test" do
  task "spec" do |t|
    sh("cd spec && rake spec")
  end
end
