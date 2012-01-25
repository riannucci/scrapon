#!/usr/bin/env ruby-local-exec
require 'progressbar'

class ProgressBar
  # Monkeypatch progressbar otherwise title is only 14 chars wide
  def title_width=(width)
    @title_width = width
    @format = "%-#{@title_width}s %3d%% %s %s"
    show
  end

  # Aryk: why are you checking if the method exists?, don't you want to overwrite it regardless?
end if !ProgressBar.instance_methods(false).include?(:title_width=)

