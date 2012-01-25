#!/usr/bin/env ruby-local-exec

require './semaphore'

module Enumerable

  # Aryk: make sure to list out the variable, no typos :)
  def map_threads(protect_concurrency, abort_on_exception = true, &block)
    protect = CountingSemaphore.new(protect_concurrency).method(:synchronize)
    map.each do |x|
      Thread.new do
        Thread.current.abort_on_exception = abort_on_exception
        block.call(x, protect)
      end
    end
  end

  def reduce_threads(acc)
    until empty?
      reject! do |thread| 
        (!thread.alive?).tap do |dead|
          acc = yield(acc, thread) if dead
        end
      end
      sleep 0.1 # don't burn up the CPU
    end
    acc
  end
end
