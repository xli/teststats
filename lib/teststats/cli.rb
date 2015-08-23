require 'thor'
require 'teststats'
require 'json'
require 'erb'

module Teststats
  class CLI < Thor
    DEFAULTS = {
      'test_unit' => {
        :pattern => '*_test.rb',
        :directory => 'test',
        :test_regex => /^\s+def test_/
      },
      'rspec' => {
        :pattern => '*_spec.rb',
        :directory => 'spec',
        :test_regex => /^\s+it ["']/
      }
    }
    desc "count", "Test count growing stats. Notice, this command will checkout old revisions to count tests, recommend a clean repository to avoid problem."
    option :framework, :banner => "Supports: test_unit and rspec, default to test_unit when root directory contains test directory, default to rspect when the root directory contains 'spec' directory"
    option :pattern, :banner => "default to '*_test.rb' for test_unit, '*_spec.rb' for rspec"
    option :directory, :banner => 'default to test for test_unit, spec for rspec'
    option :repository, :default => Dir.pwd, :banner => "Your git repository root directory. Recommend run this script inside your git repository root directory"
    option :output, :default => 'output', :banner => "Output file name"
    option :output_format, :default => 'html', :banner => "html or text"
    def count
      Dir.chdir(options[:repository]) do
        validate!
        f = framework
        current_branch = `git rev-parse --abbrev-ref HEAD`
        puts "Working on branch #{current_branch}"
        puts "List revisions"
        rev_list = `git log --pretty=tformat:%H,%aI -- #{f.directory}`.split("\n")
        puts "Found #{rev_list.size} revisions"

        data = {}
        rev_list.each do |rev|
          hash, date = rev.split(',')
          date = date.split('T')[0]
          next if data.has_key?(date)

          `git checkout -q -f #{hash}`
          files = Dir[f.test_files]
          puts "#{hash[0..8]} #{date} #{files.size} test files"
          data[date] = files.map(&f.count).reduce(:+).to_i
        end
        `git checkout #{current_branch}`
        output(data.to_a.sort_by{|d|d[0]})
      end
    end

    private
    def framework
      name = options[:framework] || detect_framework
      unless DEFAULTS.has_key?(name)
        puts "Unsupported framework #{name.inspect}, options: #{DEFAULTS.keys.inspect}"
        exit(1)
      end
      f = {:name => name}
      DEFAULTS[name].each do |k, v|
        f[k] = options[k] || v
      end
      f[:test_files] = [f[:directory], '**', f[:pattern]].join("/")
      f[:count] = lambda {|file| File.read(file).split("\n").map {|l| l =~ f[:test_regex] ? 1 : 0}.reduce(:+).to_i}
      OpenStruct.new(f)
    end

    def detect_framework
      if File.directory?('test')
        'test_unit'
      elsif File.directory?('spec') || File.directory?('specs')
        'rspec'
      else
        raise "Unknown test framework"
      end
    end

    def output(data)
      title = "#{Dir.pwd.split("/").last} Test Count History"
      case options[:output_format]
      when 'text'
        output_data_file = "#{options[:output]}.txt"
        puts "write data to file #{output_data_file}"
        File.open(output_data_file, 'w') do |f|
          f.write("##{title}\n")
          f.write("#Date\tTest Count\n")
          data.each do |date, count|
            f.write("#{date}\t#{count}\n")
          end
        end
      else
        output_html_file = "#{options[:output]}.html"
        puts "output #{output_html_file}"
        data = data.map{|d| {:date => d[0], :count => d[1]}}
        File.open(output_html_file, 'w') do |f|
          erb = ERB.new(File.read(File.expand_path('../line_chart.html.erb', __FILE__)))
          f.write(erb.result(binding))
        end
      end
    end

    def validate!
      if !File.directory?('.git')
        puts "#{options[:repository]} is not a Git repository root directory."
        exit(1)
      end
    end
  end
end
