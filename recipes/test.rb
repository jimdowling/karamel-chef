case node['platform']
when 'ubuntu'
  package ['bundler', 'firefox', 'libappindicator1', 'fonts-liberation', 'libxss1', 'xdg-utils']

  remote_file '/tmp/google-chrome.deb' do
    source 'https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb'
    owner 'root'
    group 'root'
    mode '0755'
    action :create
  end

  bash 'install_chrome' do
    user 'root'
    group 'root'
    cwd '/tmp'
    code <<-EOH
      dpkg -i google-chrome*.deb
    EOH
  end

when 'centos'
  # Centos comes with a pre world-war-1 version of ruby
  # We are going to install ruby 2.4 using RVM (Ruby version manage)
  # which, of course, is not in the repo.
  bash "install_ruby_24" do
    user "root"
    group "root"
    code <<-EOH
      yum install gcc-c++ patch readline readline-devel zlib zlib-devel libyaml-devel libffi-devel openssl-devel make bzip2 autoconf automake libtool bison iconv-devel sqlite-devel
      gpg2 --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
      curl -sSL https://rvm.io/mpapis.asc | sudo gpg2 --import -
      curl -sSL https://rvm.io/pkuczynski.asc | sudo gpg2 --import -
      curl -sSL https://get.rvm.io | bash -s stable
      source /etc/profile.d/rvm.sh
      rvm reload
      rvm install 2.4.1
    EOH
  end
end

elastic_endpoint=""
case node['platform']
when 'ubuntu'
  elastic_endpoint="#{node[:karamel][:default][:private_ips][2]}:9200"
when 'centos'
  elastic_endpoint="#{node[:karamel][:default][:private_ips][0]}:9200"
end

# Copy the environment configuration in the test directory
template "#{node['test']['hopsworks']['test_dir']}/.env" do
  source "rspec_env.erb"
  owner "vagrant"
  group "vagrant"
  mode 0755
  variables(lazy {
    h = {}
    h['elastic_endpoint'] = elastic_endpoint
    h
  })
end

# Delete form workspace preivous test results
file "#{node['test']['hopsworks']['report_dir']}/#{node['platform']}.xml" do
  action :delete
end

# Install dependencies and execute tests
case node['platform']
when 'ubuntu'
  bash "dependencies_tests" do
    user "root"
    ignore_failure true
    cwd node['test']['hopsworks']['test_dir']
    timeout node['karamel']['test_timeout']
    environment ({'PATH' => "#{ENV['PATH']}:/home/vagrant/.gem/ruby/2.3.0/bin:/srv/hops/mysql/bin",
                  'LD_LIBRARY_PATH' => "#{ENV['LD_LIBRARY_PATH']}:/srv/hops/mysql/lib",
                  'JAVA_HOME' => "/usr/lib/jvm/default-java"})
    code <<-EOH
      bundle install
      rspec --format RspecJunitFormatter --out #{node['test']['hopsworks']['report_dir']}/ubuntu.xml
    EOH
  end

  # Run Selenium tests
  bash 'selenium-firefox' do
    user 'root'
    ignore_failure true
    cwd node['test']['hopsworks']['base_dir']
    environment ({'HOPSWORKS_URL' => 'https://localhost:8181/hopsworks',
                  'HEADLESS' => "true",
                  'BROWSER' => "firefox"})
    code <<-FIREFOX
      mvn clean install -P-web
      cd hopsworks-IT/target/failsafe-reports
      for file in *.xml ; do cp $file #{node['test']['hopsworks']['report_dir']}/firefox-${file} ; done
    FIREFOX
    only_if { node['test']['hopsworks']['frontend'] }
  end

  bash 'selenium-chrome' do
    user 'root'
    ignore_failure true
    cwd node['test']['hopsworks']['base_dir']
    environment ({'HOPSWORKS_URL' => 'https://localhost:8181/hopsworks',
                  'HEADLESS' => "true",
                  'BROWSER' => "chrome"})
    code <<-CHROME
      mvn clean install -P-web
      cd hopsworks-IT/target/failsafe-reports
      for file in *.xml ; do cp $file #{node['test']['hopsworks']['report_dir']}/chrome-${file} ; done
    CHROME
    only_if { node['test']['hopsworks']['frontend'] }
  end

when 'centos'
  bash "dependencies_tests" do
    user "root"
    ignore_failure true
    timeout node['karamel']['test_timeout']
    cwd node['test']['hopsworks']['test_dir']
    environment ({'PATH' => "#{ENV['PATH']}:/usr/local/rvm/gems/ruby-2.4.1/bin:/usr/local/rvm/gems/ruby-2.4.1@global/bin:/usr/local/rvm/rubies/ruby-2.4.1/bin:/usr/local/bin:/srv/hops/mysql/bin",
              'LD_LIBRARY_PATH' => "#{ENV['LD_LIBRARY_PATH']}:/srv/hops/mysql/lib",
              'HOME' => "/home/vagrant",
              'rvm_bin_path' => '/usr/local/rvm/bin',
              'rvm_path' => "/usr/local/rvm",
              'rvm_prefix' => "/usr/local",
              'RUBY_VERSION' => 'ruby-2.4.1',
              'MY_RUBY_HOME' => '/usr/local/rvm/rubies/ruby-2.4.1',
              'GEM_PATH' => "/usr/local/rvm/gems/ruby-2.4.1:/usr/local/rvm/gems/ruby-2.4.1@global",
              'GEM_HOME' => "/usr/local/rvm/gems/ruby-2.4.1",
              'JAVA_HOME' => "/usr/lib/jvm/java"})
    code <<-EOH
      set -e
      /usr/local/rvm/bin/rvm use 2.4.1
      gem install bundler -v 1.17.3
      bundle install
      rspec --format RspecJunitFormatter --out #{node['test']['hopsworks']['report_dir']}/centos.xml
    EOH
  end
end
