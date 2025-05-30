require 'irb/completion'

begin
  AwesomePrint.irb! if require 'awesome_print'
rescue LoadError
  # suppress exception if awesome_print was not found
end

if defined?(ActiveSupport)
  Time.zone = ActiveSupport::TimeZone.all.detect { |s| s.name =~ /Kolkata/ }
  I18n.reload!
  puts "loaded timezone for #{Time.zone.tzinfo.name}"
end

# utility method that returns the instance methods on klass
# that aren't already on Object
def m(klass)
  klass.public_instance_methods - Object.public_instance_methods
end
