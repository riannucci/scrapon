#!/usr/bin/env ruby-local-exec
require 'mechanize'
require 'progressbar'
require 'logger'
require 'andand'
require 'chronic'
require './number_tools'
require './thread_tools'

class GrouponSpider
  GROUPON_HOME     = 'https://www.groupon.com/login'.freeze
  LIMIT_XPATH      = '//a[@class="next_page"]/preceding-sibling::a[1]'.freeze
  GROUPON_ID_XPATH = '//table[@class="deal_list"]//a[@class="title"]/@href'.freeze
  EXPIRATION_XPATH = '//div[@class="fine_print"]//li[1]'.freeze
  START1_XPATH     = '//div[@class="fine_print"]//li[contains(., "valid until")]'.freeze
  START2_XPATH     = '//div[@class="stats"]//dd[contains(., "Featured Date")]'.freeze

  attr_accessor :concurrency, :verbose, :username, :password, :page_limit, :user_id, :merchant_id, :fail_fast

  def initialize(options={})
    options = {
      :concurrency  => 12, 
      :verbose      => true, 
      :fail_fast    => false
    }.update(options)
    options.each { |attr, value| send("#{attr}=", value) }

    @agent = Mechanize.new do |agent|
      agent.user_agent_alias = 'Mac FireFox'
      agent.log = Logger.new options[:log_file] if options[:log_file]
    end
  end

  def data
    do_login(@username, @password)
    scrape_data(scrape_ids(determine_limit))
  end

  def user_url
    "/users/#{user_id}/deals"
  end

  def merchant_url
    "/users/#{user_id}/merchants/#{merchant_id}/deals".freeze
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
    [@agent.get(merchant_url).root.xpath(LIMIT_XPATH).first.content.to_i, page_limit].compact.min.tap do |limit|
      log("#{limit}#{' (limited)' if page_limit}")
    end
  end

  def scrape_ids(limit)
    with_progress('Fetching ids', limit) do |progress|
      (1..limit).to_a.map_threads(concurrency) do |i, protect|
        page = get_url(protect, "#{merchant_url}?page=#{i}")
        Thread.current[:ids] = page.root.xpath(GROUPON_ID_XPATH).map { |href| href.content.split("/").last }
      end.reduce_threads([]) do |acc, thread| 
        progress.inc
        acc += thread[:ids]
      end
    end
  end

  def scrape_data(groupon_ids)
    method_weight = {
      :scrape_dates => 1,
      :scrape_csv => 2
    }
    total_weight = method_weight.values.inject(:+)
    with_progress('Fetching data', groupon_ids.size * (total_weight+1)) do |progress|
      groupon_ids.map_threads(concurrency) do |deal_id, protect| 
        increments = total_weight
        begin
          method_weight.each do |func, weight| 
            send(func, deal_id, protect) 
            increments -= weight
            progress.inc(weight)
          end
        rescue Exception
          log("Failed on deal_id '#{deal_id}'")
          raise if fail_fast
        ensure
          progress.inc(increments)
        end
      end.reduce_threads([]) do |acc, thread| 
        progress.inc
        acc << Hash[thread.keys.grep(/groupon_(.*)/o).map { |k| [k.to_s.split("_",2).last.to_sym,thread[k]] }]
      end
    end
  end

  def scrape_csv(deal_id, protect)
    csv_page = get_url(protect, "#{merchant_url}/#{deal_id}/vouchers.csv")
    Thread.current[:groupon_csv]  = csv_page.content
    Thread.current[:groupon_name] = csv_page.filename.split('.').first
  end

  def scrape_dates(deal_id, protect)
    date_page = get_url(protect, "#{user_url}/#{deal_id}")
    Thread.current[:groupon_expiration_date] = Chronic.parse(date_page.root.xpath(EXPIRATION_XPATH).first.content.match(/Expires (.*)/o)[1])
    [
      [date_page,                       START1_XPATH, /Not valid until ([^.]*)./o],
      ["/deals/#{deal_id}/admin_panel", START2_XPATH, /Featured Date:\s*(\S*)/o]
    ].each do |page_or_url, xpath, regex|
      page = page_or_url.is_a?(String) ? get_url(protect, page_or_url) : page_or_url
      Thread.current[:groupon_start_date] = Chronic.parse(page.root.xpath(xpath).first.content.match(regex)[1]) rescue nil
      break if Thread.current[:groupon_start_date]
    end
    raise "No start date!" if !Thread.current[:groupon_start_date]
  end

  # Helpers
  class Dummy; def method_missing(m, *as, &b) end; end
  def with_progress(msg, size)
    begin
      progress = @verbose ? ProgressBar.new(msg, size) : Dummy.new
      yield progress
    ensure
      progress.andand.finish
    end
  end

  def get_url(protect, url, message = "Failed(#{url})")
    protect.call { 3.attempts(message) { @agent.get(url) } }
  end

  def log(msg, inline=false)
    send(inline ? :print : :puts, msg) if @verbose
  end
end
