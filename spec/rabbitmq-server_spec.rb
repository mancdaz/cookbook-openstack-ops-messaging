require_relative "spec_helper"
require "resolv"

describe "openstack-ops-messaging::rabbitmq-server" do
  before { ops_messaging_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.node.stub(:save)
      @chef_run.converge "openstack-ops-messaging::rabbitmq-server"
    end

    it "overrides default rabbit attributes" do
      expect(@chef_run.node["openstack"]["mq"]["port"]).to eql "5672"
      expect(@chef_run.node["openstack"]["mq"]["listen"]).to eql "127.0.0.1"
      expect(@chef_run.node["rabbitmq"]["address"]).to eql "127.0.0.1"
      expect(@chef_run.node["rabbitmq"]["default_user"]).to eql "guest"
      expect(@chef_run.node['rabbitmq']['default_pass']).to eql "rabbit-pass"
      expect(@chef_run.node['rabbitmq']['nodename']).to eql "guest@Fauxhai"
    end

    describe "erl_bind_networking" do
      before do
        ::Chef::Recipe.any_instance.stub(:address_for).
          with("lo").
          and_return "10.0.0.10"
        ::Resolv.stub(:getname).
          with("10.0.0.10").
          and_return "foo.example.com"
        @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
          n.set["openstack"]["mq"] = {
            "erl_bind_networking" => true
          }
        end
        @chef_run.node.stub(:save)
        @chef_run.converge "openstack-ops-messaging::rabbitmq-server"
      end

      it "overrides rabbit's erl_networking_bind_address" do
        attr = @chef_run.node["rabbitmq"]["erl_networking_bind_address"]
        expect(attr).to eql "10.0.0.10"
      end

      it "overrides rabbit's nodename" do
        expect(@chef_run.node["rabbitmq"]["nodename"]).to eql "guest@foo"
      end

      it "logs an error when IP does not resolve r/DNS" do
        ::Resolv.stub(:getname).
          with("10.0.0.10").
          and_raise ::Resolv::ResolvError.new("test exception")
        chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
          n.set["openstack"]["mq"] = {
            "erl_bind_networking" => true
          }
        end
        chef_run.node.stub(:save)
        chef_run.converge "openstack-ops-messaging::rabbitmq-server"

        expect(chef_run).to log "IP '10.0.0.10' failed to resolve reverse DNS!"
      end
    end

    describe "cluster" do
      before do
        @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
          n.set["openstack"]["mq"] = {
            "cluster" => true
          }
        end
        @chef_run.node.stub(:save)
        @chef_run.converge "openstack-ops-messaging::rabbitmq-server"
      end

      it "overrides cluster" do
        expect(@chef_run.node['rabbitmq']['cluster']).to be_true
      end

      it "overrides erlang_cookie" do
        expect(@chef_run.node['rabbitmq']['erlang_cookie']).to eql(
          "erlang-cookie"
        )
      end

      it "overrides and sorts cluster_disk_nodes" do
        expect(@chef_run.node['rabbitmq']['cluster_disk_nodes']).to eql(
          ["guest@host1", "guest@host2"]
        )
      end
    end

    it "includes rabbit recipes" do
      expect(@chef_run).to include_recipe "rabbitmq"
      expect(@chef_run).to include_recipe "rabbitmq::mgmt_console"
    end

    describe "lwrps" do
      it "deletes guest user" do
        resource = @chef_run.find_resource(
          "rabbitmq_user",
          "remove rabbit guest user"
        ).to_hash

        expect(resource).to include(
          :user => "guest",
          :action => [:delete]
        )
      end

      it "doesn't delete guest user" do
        opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
        chef_run = ::ChefSpec::ChefRunner.new opts
        chef_run.node.stub(:save)
        chef_run.converge "openstack-ops-messaging::rabbitmq-server"

        resource = chef_run.find_resource(
          "rabbitmq_user",
          "remove rabbit guest user"
        )

        expect(resource).to be_nil
      end

      it "adds user" do
        resource = @chef_run.find_resource(
          "rabbitmq_user",
          "add openstack rabbit user"
        ).to_hash

        expect(resource).to include(
          :user => "guest",
          :password => "rabbit-pass",
          :action => [:add]
        )
      end

      it "adds vhost" do
        resource = @chef_run.find_resource(
          "rabbitmq_vhost",
          "add openstack rabbit vhost"
        ).to_hash

        expect(resource).to include(
          :vhost => "/",
          :action => [:add]
        )
      end

      it "sets user permissions" do
        resource = @chef_run.find_resource(
          "rabbitmq_user",
          "set openstack user permissions"
        ).to_hash

        expect(resource).to include(
          :user => "guest",
          :vhost => "/",
          :permissions => '.* .* .*',
          :action => [:set_permissions]
        )
      end

      it "sets administrator tag" do
        resource = @chef_run.find_resource(
          "rabbitmq_user",
          "set rabbit administrator tag"
        ).to_hash

        expect(resource).to include(
          :user => "guest",
          :tag => "administrator",
          :action => [:set_tags]
        )
      end
    end
  end
end
