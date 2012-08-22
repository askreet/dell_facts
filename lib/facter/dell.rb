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

if File.exist? '/opt/dell/srvadmin/bin/omreport'

  # The report contains many headings, each which need to be parsed slightly differently
  headings = [
    'System',
    'Main System Chassis',
    'Network Data',
    'Storage Enclosures',
  ]

  main_system_chassis_subheadings = [
    /^Chassis Information$/,
    /^Remote Access Information$/,
    /^Processor \d+$/,
    /^Memory$/,
    /^Memory Array \d+$/,
    /^Slot PCI\d+$/,
    /^BIOS Information$/,
    /^Firmware Information$/,
  ]

  section = nil
  subsection = nil
  firmware_name = nil
  storage_enclosure_id = -1

  cached_command_output('/opt/dell/srvadmin/bin/omreport system summary').each_line do |line|
    # Determine if we are getting a new heading
    next if line =~ /^-*$/
    if headings.member? line.chomp
      section = line.chomp
      subsection = nil
      next
    end

    next if section == 'Network Data'
    next if section.nil?

    # Check for subsection if we're in Main System Chassis
    if section == 'Main System Chassis' and line.count(":") == 0
      main_system_chassis_subheadings.each do |regexp|
        if line.match(regexp)
          subsection = line.chomp
          next
        end
      end
    end

    k,v = line.split(/\s+:\s+/)

    if subsection == 'Firmware Information' and k == 'Name'
      firmware_name = v.chomp.downcase.gsub(" ", "_")
    end

    if section == 'Storage Enclosures' and k == 'Name'
      storage_enclosure_id += 1
    end

    k.chomp!
    next if v.nil?

    v.chomp!

    fact_name = 'dell_'
    fact_name << section.downcase.gsub(" ", "_")
    # The Storage Enclosures section is full of subsections called 'Storage Enclosures' -- not very useful.
    unless subsection.nil? or section == 'Storage Enclosures' or subsection == 'Firmware Information'
      fact_name << "_"  << subsection.downcase.gsub(" ", "_")
    end

    if subsection == 'Firmware Information'
      fact_name << "_" << firmware_name
    end

    if section == 'Storage Enclosures'
      fact_name << storage_enclosure_id.to_s
    end

    fact_name << "_" << k.downcase.gsub(" ", "_")

    Facter.add(fact_name) do
      setcode do
        v
      end
    end
  end

  # Controller-level information
  controllers = {}
  this_controller = '0'

  cached_command_output("/opt/dell/srvadmin/bin/omreport storage controller").each_line do |line|
    k,v = line.split(/\s+:\s+/)

    k.chomp!
    next if v.nil?

    v.chomp!

    # We're starting a new controller:
    if k == 'ID'
      this_controller = v
      controllers[this_controller] = {}
    elsif k != ''
      controllers[this_controller][k] = v
    end
  end

  # How many controllers do we have?
  Facter.add('dell_storage_controllers') do
    setcode do
      controllers.length
    end
  end

  # Gather data about each controller
  # Which datapoint do we care about?
  controller_data_to_gather = [
    'Name',
    'State',
    'Cache Memory Size',
    'Driver Version',
    'Firmware Version',
    'Status',
    'Slot ID',
  ]

  vdisk_data_to_gather = [
    'Status',
    'Name',
    'State',
    'Layout',
    'Size',
    'Device Name',
    'Bus Protocol',
    'Read Policy',
    'Write Policy',
    'Cache Policy',
  ]

  pdisk_data_to_gather = [
    'Bus Protocol',
    'Capacity',
    'Hot Spare',
    'Name',
    'Serial No.',
    'State',
    'Status',
  ]

  controllers.each do |controller_id, controller_data|

    # Store controller information

    controller_fact_basename = "dell_storage_controller#{controller_id}"

    controller_data.each do |datapoint, value|
      if controller_data_to_gather.member? datapoint
        datapoint_safe_name = datapoint.downcase.gsub(" ", "_")
        fact_name = "#{controller_fact_basename}_#{datapoint_safe_name}"
        
        # Add the Fact
        Facter.add(fact_name) do
          setcode do
            value
          end
        end
      end
    end

    # Store per-controller Virtual Disk information
    vdisks={}
    this_vdisk=0
    
    cached_command_output("/opt/dell/srvadmin/bin/omreport storage vdisk controller=#{controller_id}").each_line do |line|
      k,v = line.split(/\s+:\s+/)

      k.chomp!
      next if v.nil?

      v.chomp!

      # We're starting a new Virtual Disk:
      if k == 'ID'
        this_vdisk = v
        vdisks[this_vdisk] = {}
      elsif k != ''
        vdisks[this_vdisk][k] = v
      end
    end

    vdisks.each do |vdisk_id, vdisk_data|

      # Store Virtual Disk information
      vdisk_fact_basename = "#{controller_fact_basename}_vdisk#{vdisk_id}"

      vdisk_data.each do |datapoint, value|
        datapoint_safe_name = datapoint.downcase.gsub(" ", "_")
        fact_name = "#{vdisk_fact_basename}_#{datapoint_safe_name}"
        
        # Add the Fact
        Facter.add(fact_name) do
          setcode do
            value
          end
        end

      end #vdisk_data.each

      # Store per-controller, per-vdisk Physical Disk information

      pdisks={}
      this_pdisk=0
      
      cached_command_output("/opt/dell/srvadmin/bin/omreport storage pdisk controller=#{controller_id} vdisk=#{vdisk_id}").each_line do |line|
        k,v = line.split(/\s+:\s+/)

        k.chomp!
        next if v.nil?

        v.chomp!

        # We're starting a new Virtual Disk:
        if k == 'ID'
          this_pdisk = v
          pdisks[this_pdisk] = {}
        elsif k != ''
          pdisks[this_pdisk][k] = v
        end
      end

      pdisks.each do |pdisk_id, pdisk_data|

        # Store Virtual Disk information
        pdisk_fact_basename = "#{vdisk_fact_basename}_pdisk#{pdisk_id.gsub(":", "_")}"

        pdisk_data.each do |datapoint, value|
          datapoint_safe_name = datapoint.downcase.gsub(" ", "_")
          fact_name = "#{pdisk_fact_basename}_#{datapoint_safe_name}"
          
          if pdisk_data_to_gather.member? datapoint
            # Add the Fact
            Facter.add(fact_name) do
              setcode do
                value
              end
            end
          end
        end
      end #pdisks.each

    end #vdisks.each

  end #controllers.each

  proc_data_to_gather = [ 'Connector Name',
                          'Processor Brand',
                          'Processor Version',
                          'Core Count' ]

  this_proc = nil
  procs = {}
  cached_command_output("/opt/dell/srvadmin/bin/omreport chassis processors").each_line do |line|
    k,v = line.split(/\s+:\s+/)

    k.chomp!
    next if v.nil?
    next if k == 'Health'

    v.chomp!

    # We're starting a new Processor:
    if k == 'Index'
      this_proc = v
      procs[this_proc] = {}
    elsif k != ''
      procs[this_proc][k] = v
    end
  end

  procs.each do |proc_id, proc_data|

    # Store Virtual Disk information
    proc_fact_basename = "dell_chassis_processor#{proc_id}"

    proc_data.each do |datapoint, value|
      datapoint_safe_name = datapoint.downcase.gsub(" ", "_")
      fact_name = "#{proc_fact_basename}_#{datapoint_safe_name}"
      
      if proc_data_to_gather.member? datapoint
        # Add the Fact
        Facter.add(fact_name) do
          setcode do
            value
          end
        end
      end
    end

  end #procs.each

  # Do not cache this output as it will be used by a Puppet module to actually modify the value.
  Facter.add('dell_front_panel') do
    setcode do
      %x{/opt/dell/srvadmin/bin/omreport chassis frontpanel}.grep(/^LCD Line 1/)[0].split(/\s+:\s+/)[1].chomp!
    end
  end

end

