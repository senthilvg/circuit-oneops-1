require File.expand_path('../../libraries/virtual_machine_manager', __FILE__)
require File.expand_path('../../libraries/models/virtual_machine_model', __FILE__)
require File.expand_path('../../libraries/models/volume_model', __FILE__)
require File.expand_path('../../libraries/models/nic_model', __FILE__)
require File.expand_path('../../libraries/models/cdrom_model', __FILE__)
require File.expand_path('../../libraries/models/tenant_model', __FILE__)

def get_volume(compute_provider, datastore, name, disk_mode, thin_provisioned, disk_size)
  volume_model = VolumeModel.new(datastore)
  volume_model.name = name
  volume_model.disk_mode = disk_mode
  volume_model.thin_provisioned = thin_provisioned
  volume_model.size_gb = disk_size
  volume_attributes = volume_model.serialize_object

  return compute_provider.volumes.new(volume_attributes)
end

def get_network_interface(compute_provider, service_compute)
  nic_model = NicModel.new(service_compute[:network], service_compute[:network])
  nic_model.status = 'ok'
  nic_model.summary = 'VM Network'
  nic_attributes = nic_model.serialize_object

  return compute_provider.interfaces.new(nic_attributes)
end

def get_cdrom(compute_provider, service_compute, instance_uuid = nil)
  if !instance_uuid.nil? && !instance_uuid.empty?
    cdrom_model = CdromModel.new(service_compute[:datastore], service_compute[:iso],
                                 instance_uuid)
    return cdrom_model.serialize_object
  else
    cdrom_model = CdromModel.new(service_compute[:datastore], service_compute[:iso])
  end
  cdroms_attributes =  cdrom_model.serialize_object

  return compute_provider.cdroms.new(cdroms_attributes)
end

def get_customization_spec
  ip_settings = {}
  ip_settings['ip'] = '10.9.108.212'
  ip_settings['subnetMask'] = '255.255.252.0'
  ip_settings['gateway'] = ['10.9.108.1']
  ip_settings['domain'] = 's06000.us.wal-mart.com'
  ip_settings['dnsServerList'] = ['10.9.108.98', '161.173.7.20']

  custom_spec = {}
  custom_spec['domain'] = 's06000.us.wal-mart.com'
  custom_spec['hostname'] = 'oneopstesthost2'
  custom_spec['time_zone'] = 'UTC'
  custom_spec['ipsettings'] = ip_settings
  # custom_spec['encryptionKey'] = []

  return custom_spec
end

def get_virtual_machine_attributes(service_compute, cpu_size, memory_size, volumes, network_interface, customization_spec)
  virtual_machine_model = VirtualMachineModel.new(node[:server_name])
  virtual_machine_model.cpus = cpu_size
  virtual_machine_model.memory_mb = memory_size
  virtual_machine_model.guest_id = service_compute[:guest_id]
  virtual_machine_model.datacenter = service_compute[:datacenter]
  virtual_machine_model.template_path = node[:image_id]
  virtual_machine_model.cluster = service_compute[:cluster]
  virtual_machine_model.datastore = service_compute[:datastore]
  virtual_machine_model.resource_pool = 'Resources'
  virtual_machine_model.power_on = false
  virtual_machine_model.connection_state = 'connected'
  virtual_machine_model.volumes = volumes
  virtual_machine_model.interfaces = [network_interface]
  virtual_machine_model.customization_spec = customization_spec

  return virtual_machine_model.serialize_object
end
#--------------------------------------------------
rfcCi = node[:workorder][:rfcCi]
compute_attributes = rfcCi[:ciAttributes]
cloud_name = node[:workorder][:cloud][:ciName]
service_compute = node[:workorder][:services][:compute][cloud_name][:ciAttributes]

size_map = JSON.parse(service_compute[:sizemap])
size_values = size_map[rfcCi["ciAttributes"]["size"]].split('x')
cpu_size = size_values[0]
memory_size = size_values[1]
disk_size = size_values[2]

Chef::Log.info("Connecting to vCenter " + service_compute[:endpoint].to_s)
Chef::Log.info("Data Center " + service_compute[:datacenter].to_s)
Chef::Log.info("Cluster " + service_compute[:cluster].to_s)
tenant_model = TenantModel.new(service_compute[:endpoint], service_compute[:username], service_compute[:password], service_compute[:publickey])
compute_provider = tenant_model.get_compute_provider

volumes = Array.new
Chef::Log.info("configuring disks")
volumes.push(get_volume(compute_provider, service_compute[:datastore], 'os', 'PERSISTENT', true, 9))
volumes.push(get_volume(compute_provider, service_compute[:datastore], 'data_disk', 'INDEPENDENT_PERSISTENT', true, disk_size))

Chef::Log.info("configuring network interfaces")
network_interface = get_network_interface(compute_provider, service_compute)
customization_spec = get_customization_spec()

Chef::Log.info("configuring virtual machine")
vm_attributes = get_virtual_machine_attributes(service_compute, cpu_size, memory_size, volumes, network_interface, customization_spec)
# Chef::Log.info("lookat break: " + node[:puga] )
Chef::Log.info("Creating VM ..... " + node[:server_name].to_s)
start_time = Time.now
Chef::Log.info("start time " + start_time.to_s)
public_key = node.workorder.payLoad[:SecuredBy][0][:ciAttributes][:public]
virtual_machine_manager = VirtualMachineManager.new(compute_provider, public_key)
instance_id = virtual_machine_manager.clone(vm_attributes)
puts "***RESULT:instance_id="+instance_id
# puts "***RESULT:hypervisor="+hypervisor
Chef::Log.info("end time " + Time.now.to_s)
total_time = Time.now - start_time
Chef::Log.info("Total time to create " + total_time.to_s)

Chef::Log.info("Getting ip address... ")
ip_address = virtual_machine_manager.ip_address
node.set[:ip] = ip_address
Chef::Log.info("Assigned ip address is " + ip_address)
puts "***RESULT:private_ip="+ip_address
puts "***RESULT:public_ip="+ip_address
puts "***RESULT:dns_record="+ip_address

Chef::Log.info("Exiting vSphere add_node ")
# Chef::Log.info("lookat break: " + node[:puga] )
