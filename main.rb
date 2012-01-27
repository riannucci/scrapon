#!/usr/bin/env ruby-local-exec
require 'rubygems'
require 'bundler/setup'

require 'yaml'
require './groupon_spider'

p GrouponSpider.new(YAML.load_file('options.yml')).data.map { |i| i[:name] }
