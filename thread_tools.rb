#!/usr/bin/env ruby-local-exec

require './semaphore'

module Enumerable
  def map_threads(protect_concurrency, abort_on_ex = true, &b) 
    protect = CountingSemaphore.new(protect_concurrency).method(:synchronize)
    map.each do |x|
      Thread.new do
        Thread.current.abort_on_exception = abort_on_ex
        b.call(x, protect)
      end
    end
  end

  def reduce_threads(acc)
    while !empty?
      reject! do |thread| 
        (!thread.alive?).tap do |dead|
          acc = yield(acc, thread) if dead
        end
      end
      sleep 0.1 # don't burn up the CPU
    end
    return acc
  end
end
