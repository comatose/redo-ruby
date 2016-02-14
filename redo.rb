require 'pathname'

def list_do_files target
  tokens = target.split('.')
  results = []
  for i in 1..tokens.length-1
    results += [[tokens[0...i].join('.'), tokens[i...tokens.length]]]
  end
  [[target, "#{Pathname.new(target).basename.to_s}.do"]] + \
  results.map { |l| [l[0], (["default"] + l[1] + ["do"]).join('.')] }
end

def redo_target target
  print list_do_files target
end

def redo_build
  ARGV.each { |t| redo_target t }
end

redo_build
