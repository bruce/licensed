# frozen_string_literal: true
require "test_helper"
require "tmpdir"

if Licensed::Shell.tool_available?("go")
  describe Licensed::Source::Go do
    let(:go_path) { File.expand_path("../../fixtures/go", __FILE__) }
    let(:fixtures) { File.join(go_path, "src/test") }
    let(:config) { Licensed::Configuration.new("go" => { "GOPATH" => go_path }) }
    let(:source) { Licensed::Source::Go.new(config) }

    describe "enabled?" do
      it "is true if go source is available" do
        Dir.chdir(fixtures) do
          assert source.enabled?
        end
      end

      it "is false if go source is not available" do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            refute source.enabled?
          end
        end
      end

      it "is false if disabled" do
        Dir.chdir(fixtures) do
          assert source.enabled?
          config["sources"][source.type] = false
          refute source.enabled?
        end
      end
    end

    it "uses ENV['GOPATH'] if not set in configuration" do
      begin
        original_go_path = ENV["GOPATH"]
        ENV["GOPATH"] = go_path
        config.delete("go")

        Dir.chdir fixtures do
          assert source.dependencies.detect { |d| d["name"] == "github.com/hashicorp/golang-lru" }
        end
      ensure
        ENV["GOPATH"] = original_go_path
      end
    end

    describe "dependencies" do
      it "includes direct dependencies" do
        Dir.chdir fixtures do
          dep = source.dependencies.detect { |d| d["name"] == "github.com/hashicorp/golang-lru" }
          assert dep
          assert_equal "go", dep["type"]
          assert dep["homepage"]
          assert dep["summary"]
        end
      end

      it "includes indirect dependencies" do
        Dir.chdir fixtures do
          dep = source.dependencies.detect { |d| d["name"] == "github.com/hashicorp/golang-lru/simplelru" }
          assert dep
          assert_equal "go", dep["type"]
          assert dep["homepage"]
        end
      end

      it "doesn't include depenencies from the go std library" do
        Dir.chdir fixtures do
          refute source.dependencies.any? { |d| d["name"] == "runtime" }
        end
      end

      describe "with unavailable packages" do
        # use a custom go path that doesn't contain go libraries installed from
        # setup scripts
        let(:go_path) { Dir.mktmpdir }

        before do
          # fixtures now points at the tmp location, copy go source to tmp
          # fixtures location
          FileUtils.mkdir_p File.join(go_path, "src")
          FileUtils.cp_r File.expand_path("../../fixtures/go/src/test", __FILE__), fixtures

          # the tests are expected to print errors from `go list` which
          # should not be hidden during normal usage. hide that output during
          # the test execution
          @previous_stderr = $stderr
          $stderr.reopen(File.new("/dev/null", "w"))
        end

        after do
          $stderr.reopen(@previous_stderr)
          FileUtils.rm_rf go_path
        end

        it "do not raise an error if ignored" do
          config.ignore("type" => "go", "name" => "github.com/hashicorp/golang-lru")

          Dir.chdir fixtures do
            source.dependencies
          end
        end

        it "raises an error" do
          Dir.chdir fixtures do
            assert_raises RuntimeError do
              source.dependencies
            end
          end
        end
      end

      describe "search root" do
        it "is set to the vendor path for vendored packages" do
          Dir.chdir fixtures do
            dep = source.dependencies.detect { |d| d["name"] == "github.com/gorilla/context" }
            assert dep
            assert_equal File.join(fixtures, "vendor"), dep.search_root
          end
        end

        it "is set to #gopath" do
          Dir.chdir fixtures do
            dep = source.dependencies.detect { |d| d["name"] == "github.com/hashicorp/golang-lru" }
            assert dep
            assert_equal go_path, dep.search_root
          end
        end
      end

      describe "package version" do
        it "is nil when git is unavailable" do
          Dir.chdir fixtures do
            Licensed::Git.stub(:available?, false) do
              dep = source.dependencies.detect { |d| d["name"] == "github.com/gorilla/context" }
              assert_nil dep["version"]
            end
          end
        end

        it "is the latest git SHA of the package directory" do
          Dir.chdir fixtures do
            dep = source.dependencies.detect { |d| d["name"] == "github.com/gorilla/context" }
            assert_match(/[a-f0-9]{40}/, dep["version"])
          end
        end
      end
    end
  end
end
