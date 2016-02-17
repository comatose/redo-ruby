#!/usr/bin/env ruby

require 'pathname'

def list_do_files target
  tokens = target.split('.')
  results = []
  for i in 1..tokens.length-1
    results += [[tokens[0...i].join('.'), tokens[i...tokens.length]]]
  end
  [[target, "#{File.basename target}.do"]] + \
  results.map { |basename, dofile| [basename, (["default"] + dofile + ["do"]).join('.')] }
end

def redo_target_from_dir(base_dir, target)
  target = Pathname.new target
  if target.relative?
    return target.to_s
  else
    return target.relative_path_from(Pathname.new base_dir).to_s
  end
end

def redo_ target
  puts redo_target_from_dir(Dir.pwd, target)
  print list_do_files target
end

case $0
when /.*(redo)(-ifchange)*$/
  ARGV.each { |t| redo_ t }
else
  exit "unknown redo command"
end
