Puppet::Type.type(:service).provide :openbsd, :parent => :init do

  desc "Provider for OpenBSD's rc.d daemon control scripts"

  commands :rcctl => '/usr/sbin/rcctl'

  confine :operatingsystem => :openbsd
  defaultfor :operatingsystem => :openbsd
  has_feature :flaggable

  def startcmd
    if @resource[:flags] and flags != @resource[:flags]
      # Unfortunately, the startcmd gets called, before
      # the service is enabled (in case its supposed to be enabled).
      # Setting flags via rcctl is only possible, when the service is enabled
      # In case the service is not to be enabled, it will be automatically
      # disabled later in the same puppet run.
      self.enable
      self.flags = @resource[:flags]
    end
    [command(:rcctl), '-f', :start, @resource[:name]]
  end

  def stopcmd
    [command(:rcctl), :stop, @resource[:name]]
  end

  def restartcmd
    (@resource[:hasrestart] == :true) && [command(:rcctl), '-f', :restart, @resource[:name]]
  end

  def statuscmd
    [command(:rcctl), :check, @resource[:name]]
  end

  # @api private
  # When storing the name, take into account not everything has
  # '_flags', like 'multicast_host' and 'pf'.
  def self.instances
    instances = []

    begin
      execpipe([command(:rcctl), :getall]) do |process|
        process.each_line do |line|
          match = /^(.*?)(?:_flags)?=(.*)$/.match(line)
          next if match[1].match(/.*?_timeout$|.*?_user$/)
          attributes_hash = {
            :name      => match[1],
            :flags     => match[2],
            :hasstatus => true,
            :provider  => :openbsd,
          }

          instances << new(attributes_hash);
        end
      end
      instances
    rescue Puppet::ExecutionFailure
      return nil
    end
  end

  def enabled?
    output = Puppet::Util::Execution.execute([command(:rcctl), "get", @resource[:name], "status"],
                     :failonfail => false, :combine => false, :squelch => false)
    if output.exitstatus == 0
      self.debug("Is enabled")
      return :true
    else
      self.debug("Is disabled")
      return :false
    end
  end

  def enable
    self.debug("Enabling")
    rcctl(:enable, @resource[:name])
    if @resource[:flags]
      rcctl(:set, @resource[:name], :flags, @resource[:flags])
    end
  end

  def disable
    self.debug("Disabling")
    rcctl(:disable, @resource[:name])
  end

  def running?
    output = execute([command(:rcctl), "check", @resource[:name]],
                     :failonfail => false, :combine => false, :squelch => false).chomp
    return true if output.match(/\(ok\)/)
  end

  # Uses the wrapper to prevent failure when the service is not running;
  # rcctl(8) return non-zero in that case.
  def flags
    output = execute([command(:rcctl), "get", @resource[:name], "flags"],
                     :failonfail => false, :combine => false, :squelch => false).chomp
    self.debug("Flags are: \"#{output}\"")
    output
  end

  def flags=(value)
    self.debug("Changing flags from #{flags} to #{value}")
    rcctl(:set, @resource[:name], :flags, value)
    # If the service is already running, force a restart as the flags have been changed.
    rcctl(:restart, @resource[:name]) if running?
  end
end
