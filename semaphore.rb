#!/usr/bin/env ruby-local-exec

#
# $Id: semaphore.rb,v 1.2 2003/03/15 20:10:10 fukumoto Exp $
# $Id: semaphore.rb,v 1.3 2012/01/20 19:39:10 robbie@mixbook.com Exp $
#   * Updated to ruby 1.9.3 compatibility.
#   * Fixed some races.
#   * Removed unnecessary aliases.
#

class CountingSemaphore

  def initialize(counter = 0)
    @counter = counter
    @waiting_list = []
    @lock = Mutex.new
  end

  def down
    added = nil
    @lock.synchronize { added = @waiting_list.push(Thread.current) if (@counter -= 1) < 0 }
    Thread.stop if added
    self
  end

  def up
    removed = nil
    @lock.synchronize { removed = @waiting_list.shift if (@counter += 1) <= 0 }
    # This can only throw "thread killed", and so there's no point in retry'ing
    removed.wakeup if removed rescue nil
    self
  end

  def synchronize
    down
    yield
  ensure
    up
  end

end

