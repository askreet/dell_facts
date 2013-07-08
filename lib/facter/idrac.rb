# vim: ts=2 sw=2 expandtab

require 'facter'
require 'rubygems'
require 'time'

# Run a command, unless it's already been run and the output is cached.
def cached_command_output(command, cache_time = 86400)

  cache_directory = '/var/opt/lib/pe-puppet/facts/cached_command_output'
  Dir.mkdir cache_directory unless File.exist? cache_directory

  cache_file = cache_directory + '/' + command.gsub("/", "_")

  if File.exist?(cache_file) && File.mtime(cache_file) > (Time.now - cache_time) then
    command_output = File.read(cache_file).chomp
  else
    command_output = %x{#{command}}
    f = File.open(cache_file, 'w')
    f.puts command_output
    f.close
  end

  return command_output

end

# Are there alternate locations this could be installed?
if File.exists? '/opt/dell/srvadmin/sbin/racadm'

  Facter.add('dell_has_racadm') do
    setcode do
      'true'
    end
  end

  # What data points should we gather, and what should we call them as Facts?
  name_mapping = {
    'NIC Enabled'  => 'nic_enabled',
    'IPv4 Enabled' => 'enabled',
    'DHCP Enabled' => 'dhcp',
    'IP Address'   => 'ip',
    'Subnet Mask'  => 'netmask',
    'Gateway'      => 'gateway',
    
    'IPv6 Enabled'  => 'enabled',
    'DHCP6 Enabled' => 'dhcp',
    'IP Address 1'  => 'ip',
    'Gateway'       => 'gateway',

    'NIC Selection' => 'nic_type',
    'Link Detected' => 'has_link',
    'Speed'         => 'speed',
    'Duplex Mode'   => 'duplex',
  }

  heading = ''
  cached_command_output('/opt/dell/srvadmin/sbin/racadm getniccfg', 3600).each_line do |line|

    # Are we in a new section?
    if line =~ /^IPv4 settings/
      heading = 'ipv4_'
      next
    elsif line =~ /^IPv6 settings/
      heading = 'ipv6_'
      next
    elsif line =~ /^LOM Status/
      heading = ''
      next
    end

    d = line.split("=")
    next if d.length != 2

    key = d[0].strip
    value = d[1].strip

    if name_mapping.has_key? key
      fact_name = 'dell_rac_' + heading + name_mapping[key]

      Facter.add(fact_name) do
        setcode do
          value
        end
      end
    end

  end

else
  Facter.add('dell_has_racadm') do
    setcode do
      'false'
    end
  end
end
