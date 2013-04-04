#
# Cookbook Name:: eucalyptus-cookbook
# Recipe:: default
#
# Copyright 2012, Fort Hill Company
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
include_recipe 'cron'

#TODO: Turn version detection into a do once and global property
if File.exist?('/etc/debian_version')
  include_recipe 'apt'
elsif File.exist?('/etc/redhat-release')
  include_recipe 'yum'
else
  Chef::Application.exit!("This recipe only supports Debian or Red Hat Compatible Variants")
end

euca_version = node[:euca][:install][:version]
euca2ools_version = node[:euca][:install][:euca2ools][:version]

if File.exist?('/etc/debian_version')
  apt_repository "eucalyptus" do
    uri "http://eucalyptussoftware.com/downloads/repo/eucalyptus/#{euca_version}/debian/"
    distribution "squeeze"
    components %w(main)
    action :add
    notifies :run, resources(:execute => "apt-get update"), :immediately
  end
elsif File.exist?('/etc/redhat-release')
  yum_repository "eucalyptus" do
    url "http://downloads.eucalyptus.com/software/eucalyptus/#{euca_version}/centos/6/x86_64/"
  end
  yum_repository "euca2ools" do
    url "http://downloads.eucalyptus.com/software/euca2ools/#{euca2ools_version}/centos/6/x86_64/"
  end
  include_recipe 'yumrepo::epel'
else
  Chef::Application.exit!("This recipe only supports Debian or Red Hat Compatible Variants")
end

include_recipe 'eucalyptus::ssh_keys'
include_recipe 'eucalyptus::cloud_controller_registration'

service "eucalyptus-nc" do
  action :nothing
end

service "eucalyptus-cloud" do
  action :nothing
end

service "eucalyptus-cc" do
  action :nothing
end

execute "eucalyptus-clean-restart" do
  command "/etc/init.d/eucalyptus-cc cleanrestart"
  notifies :create, resources(:eucalyptus_register_cluster => node[:euca][:cluster_name]), :delayed

  action :nothing
end

execute "ensure-euca-ownership-of-configs" do
  command "chown -R eucalyptus /etc/eucalyptus"
  action :nothing
end

execute 'euca-conf-setup' do
  command 'euca_conf --setup'
  action :nothing
end

service 'ntp' do
  action :nothing
end

package 'aoetools' do
  action :install
end

package 'bridge-utils' do
  action :install
end
