#!/usr/bin/env ruby-local-exec
require 'rubygems'
require 'bundler/setup'

require 'yaml'
require './groupon_spider'

GrouponSpider.new(YAML.load_file('options.yml')).tap do |spider|
  spider.page_limit = 2
  p spider.data.map { |i| i[:name] }
end
