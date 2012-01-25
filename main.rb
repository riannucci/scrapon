#!/usr/bin/env ruby-local-exec
require './groupon_spider'
require 'yaml'

p GrouponSpider.new(YAML.load_file('options.yml')).data.map { |i| i[:name] }
