include_recipe 'eucalyptus::default'

if File.exist?('/etc/debian_version')
  if node[:euca][:hypervisor] == 'kvm'
    require_recipe 'kvm'
  end
end

# euca nc
#
packages_debian = %w(ntpdate open-iscsi libcrypt-openssl-random-perl libcrypt-openssl-rsa-perl libcrypt-x509-perl eucalyptus-nc)
packages_yum = %w(ntpdate iscsi-initiator-utils perl-Crypt-OpenSSL-RSA perl-Crypt-OpenSSL-Random perl-Crypt-OpenSSL-X509 eucalyptus-nc)

if File.exists?('/etc/debian_version')
  packages_debian.each do |pkg|
    package pkg do
        options "--force-yes"
      action :install
    end
  end
elsif File.exist?('/etc/redhat-release')
  packages_yum.each do |pkg|
    package pkg do
      action :install
    end
  end
else
  Chef::Application.exit!("This recipe only supports Debian or Red Hat Compatible Variants")
end

execute 'run-euca_conf-setup' do
  command 'euca_conf --setup'
end

template "/etc/libvirt/qemu.conf" do
  source "qemu.conf.erb"
  variables(
    :euca_user => node[:euca][:user]
  )
end 

template "/etc/libvirt/libvirtd.conf" do
  source "libvirtd.conf.erb"
end

group "libvirt"

group "libvirt" do
  members ["eucalyptus", "root"]
  action :modify
  append true
end

sockets = ['/var/run/libvirt/libvirt-sock', '/var/run/libvirt/libvirt-sock-ro']

sockets.each do |skt|
  execute "ensure ownership of #{skt}" do
    command "chown root:libvirt #{skt}"
  end
end

front_end = node[:euca][:front_end]
if node[:euca][:test]
  front_end = node[:euca][:test_front_end]
end

cron "sync time with cloud-controller" do
  command "/usr/sbin/ntpdate #{front_end}"
  user    'root'
  minute  '*/3'
end


ruby_block 'update-loop-devices-in-etc-modules' do
  #TODO: Turn into LWRP
  def limit_loop_devices(config_file, loop_entry, regex_loop)
    begin
      existing_etc_modules = File.read(config_file)
    rescue Errno::ENOENT
      existing_etc_modules = ""
    end
    if existing_etc_modules.match(regex_loop)
      existing_etc_modules.gsub(regex_loop, loop_entry)
    else
      existing_etc_modules << loop_entry
    end

    File.open(config_file, 'w+') do |f|
      f << existing_etc_modules
    end
  end

  debian_loop_config = ["/etc/modules", "loop max_loop=64\n", /^loop/]
  centos_loop_config = ["/etc/modprobe.d/dist-euca", "options loop max_loop=64\n", /^options\s+loop/]

  block do
    if File.exists?('/etc/debian_version')
      limit_loop_devices(*debian_loop_config)
    elsif File.exists?('/etc/redhat-release')
      limit_loop_devices(*centos_loop_config)
    else
      Chef::Application.exit!("This recipe only supports Debian or Red Hat Compatible Variants")
    end
  end
end


template "/etc/eucalyptus/eucalyptus.conf" do
  # right now this is just set for
  # STATIC networking mode
  source "eucalyptus.conf.erb"
  owner 'eucalyptus'
  variables(
    :hypervisor => node[:euca][:hypervisor],
    :compute_nodes => node[:euca][:compute_nodes],

    :instance_path => node[:euca][:instance_path],

    :vnet_pubinterface =>  node[:euca][:network][:node][:pub_interface],
    :vnet_privinterface => node[:euca][:network][:node][:priv_interface],

    :vnet_bridge => node[:euca][:network][:vnet][:bridge],

    :vnet_mode =>    node[:euca][:network][:vnet][:mode],

    :subnet =>    node[:euca][:network][:vnet][:subnet],
    :netmask =>   node[:euca][:network][:vnet][:netmask],
    :broadcast => node[:euca][:network][:vnet][:broadcast],
    :router =>    node[:euca][:network][:vnet][:router],
    :dns =>       node[:euca][:network][:vnet][:dns],
    :mac_map =>   node[:euca][:network][:vnet][:mac_map].map {|mac,ipaddrr| "#{mac}=#{ipaddrr}" }.join(' '),

    :addresses_per_net =>       node[:euca][:network][:vnet][:addresses_per_net],
    :public_ips_start =>        node[:euca][:network][:vnet][:public_ips_start],
    :public_ips_end =>          node[:euca][:network][:vnet][:public_ips_end]

  )

  notifies :run,          resources(:execute => "ensure-euca-ownership-of-configs"), :immediately
  notifies :restart,      resources(:service => "eucalyptus-nc"), :immediately
  action :create
end

logrotate_app "eucalyptus-node-controller" do
  cookbook 'logrotate'
  path      ['/var/log/eucalyptus/nc.log']
  frequency 'daily'
  rotate    7
end
