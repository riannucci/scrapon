#!/usr/bin/env ruby-local-exec

class Integer

  def attempts(msg = nil)
    tries = 0
    begin
      yield
    rescue Exception => e
      tries += 1
      if tries > self
        puts "#{msg}: #{e.to_s}" if msg
        raise
      else
        retry
      end
    end
  end

end

