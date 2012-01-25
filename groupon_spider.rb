#!/usr/bin/env ruby-local-exec
require 'mechanize'
require 'progressbar'
require 'logger'
require 'chronic'
require './fix_progressbar'
require './number_tools'
require './thread_tools'

class GrouponSpider
  GROUPON_HOME = 'https://www.groupon.com/login'.freeze

  # Aryk: no reason to make DEFAULTS constant
  # any particular defaults just go initialize. in the 1% chance you need to reuse those defaults, then abstract it out...
  # make sure to spell out as well. "merchant_id"???  merchant_id, merchandise_id?? idk...its not clear. The best ruby code
  # reads like english and that would be a mispelling.
  attr_accessor :concurrency, :verbose, :username, :password, :page_limit, :user_id, :merchant_id, :fail_fast

  # Aryk: why do you need to set the instance variables to nil?. If you don't set it, then you just
  # don't set it
  def initialize(options={})
    options = {:concurrency => 12, :verbose => true, :fail_fast => false}.update(options)
    options.each { |attr, value| send("#{attr}", value) }

    @agent = Mechanize.new do |agent|
      agent.user_agent_alias = 'Mac FireFox'
      agent.log = Logger.new options[:log_file] if options[:log_file]
    end
  end

  def data
    do_login(@username, @password)
    scrape_data(scrape_ids(determine_limit))
  end

  def base_user_url
    "/users/#{user_id}/deals"
  end

  def base_merch_url
    "/users/#{user_id}/merchants/#{merchange_id}/deals".freeze
  end

  private

  def do_login(username, password)
    log('Loading groupon login page')
    @agent.get GROUPON_HOME do |page|
      log("Logging in as #@username")
      page.form_with :action => '/session' do |form|
        form['session[email_address]'] = username
        form['session[password]']      = password
      end.click_button
    end
  end

  def determine_limit
    log('Determining number of groupon deal pages... ', true)
    @agent.get(base_merch_url) do |page|
      [page.root.xpath('//a[@class="next_page"]/preceding-sibling::a[1]').first.content.to_i, page_limit].compact.min.tap do |limit|
        log("#{limit}#{' (limited)' if page_limit}")
      end
    end
  end

  def scrape_ids(limit)
    with_progress('Fetching groupon ids', limit) do |progress|
      (1..limit).to_a.map_threads(concurrency) do |i, protect|
        page = get_url("#{base_merch_url}?page=#{i}")
        Thread.current[:ids] = page.root.xpath('//table[@class="deal_list"]//a[@class="title"]/@href').map { |href| href.content.split("/").last }
      end.reduce_threads([]) do |acc, thread| 
        progress.inc
        acc += thread[:ids]
      end
    end
  end

  def scrape_data(groupon_ids)
    with_progress('Fetching groupon data', groupon_ids.size) do |progress|
      groupon_ids.map_threads(concurrency) do |deal_id, protect| 
        begin
          %w{scrape_dates scrape_csv}.each { |func| send(func, deal_id, protect) }
        rescue Exception
          log("Failed on deal_id '#{deal_id}'")
          raise if fail_fast
        end
      end.reduce_threads([]) do |acc, thread| 
        progress.inc
        acc << Hash[thread.keys.grep(/groupon_(.*)/o).map { |k| [k.to_s.split("_",2).last.to_sym,thread[k]] }]
      end
    end
  end

  def scrape_csv(deal_id, protect)
    csv_page = get_url(protect, "#{base_merch_url}/#{deal_id}/vouchers.csv")
    Thread.current[:groupon_csv]  = csv_page.content
    Thread.current[:groupon_name] = csv_page.filename.split('.').first
  end

  def scrape_dates(deal_id, protect)
    date_page = get_url(protect, "#{base_user_url}/#{deal_id}")
    Thread.current[:groupon_exp_date] = Chronic.parse(date_page.root.xpath("//div[@class='fine_print']//li[1]").first.content.match(/Expires (.*)/o)[1])
    [
      [date_page, "//div[@class='fine_print']//li[contains(., 'valid until')]", /Not valid until ([^.]*)./o],
      ["/deals/#{deal_id}/admin_panel", "//div[@class='stats']//dd[contains(., 'Featured Date')]", /Featured Date:\s*(\S*)/o]
    ].each do |page_or_url, xpath,rexp|
      # You had: protect.call { 3.attempts("Failed(#{date_url})") { @agent.get(page_or_url) } }
      # Did you mean protect.call { 3.attempts("Failed(#{page_or_url})") { @agent.get(page_or_url) } } ????
      # If so, this is a perfect example of modularizing and keeping code clean and DRY, this would never have happened.
      # Once you DRY it up, look mom! it fits on oneline :)
      page = page_or_url.is_a?(String) ? get_url(protect, page_or_url) : page_or_url
      Thread.current[:groupon_start_date] = Chronic.parse(page.root.xpath(xpath).first.content.match(rexp)[1]) rescue nil
      break if Thread.current[:groupon_start_date]
    end
    raise "No start date!" if !Thread.current[:groupon_start_date]
  end

  # Returns chronic page object with protection! (Robbie, not quite sure what this protect thing does, could have done a better job naming.)
  def get_url(protect, url)
    protect.call { 3.attempts("Failed(#{url})") { @agent.get(url) } }
  end

  # Helpers
  class Dummy; def method_missing(m, *as, &b) end; end
  def with_progress(msg, size)
    begin
      progress = @verbose ? ProgressBar.new(msg, size) : Dummy.new
      progress.title_width = 23
      yield progress
    ensure
      progress.finish
    end
  end

  def log(msg, inline=false)
    send(inline ? :print : :puts, msg) if @verbose
  end
end
