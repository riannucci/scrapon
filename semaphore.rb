#!/usr/bin/env ruby-local-exec

#
# $Id: semaphore.rb,v 1.2 2003/03/15 20:10:10 fukumoto Exp $
# $Id: semaphore.rb,v 1.3 2012/01/20 19:39:10 robbie@mixbook.com Exp $
#   * Updated to ruby 1.9.3 compatibility.
#   * Fixed some races.
#   * Removed unnecessary aliases.
#

class CountingSemaphore

  def initialize(initvalue = 0)
    @counter = initvalue
    @waiting_list = []
    @lock = Mutex.new
  end

  def down
    pushed = nil
    @lock.synchronize {
      if (@counter -= 1) < 0
        pushed = @waiting_list.push(Thread.current)
      end
    }
    Thread.stop if pushed
    self
  end

  def up
    t = nil
    @lock.synchronize {
      if (@counter += 1) <= 0
        t = @waiting_list.shift
      end
    }
    # This can only throw "thread killed", and so there's no point in retry'ing
    t.wakeup if t rescue nil 
    self
  end

  def synchronize
    down
    yield
  ensure
    up
  end

end

