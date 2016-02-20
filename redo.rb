#!/usr/bin/env ruby

require 'pathname'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'digest'

class Redo
  def initialize files
    @targets = files.map { |f| redo_target_from_dir(Dir.pwd, f) }

    @REDO_CALL_DEPTH = "REDO_CALL_DEPTH"
    @call_depth = ENV.fetch(@REDO_CALL_DEPTH, 0).to_i

    @REDO_DEPS_PATH = "REDO_DEPS_PATH"
    @deps_path = ENV[@REDO_DEPS_PATH]

    @REDO_SESSION_ID = "REDO_SESSION_ID"
    @session_id = ENV.fetch(@REDO_SESSION_ID, Process.pid).to_i

    @config_dir = ".redo"
    @temp_dir = File.join @config_dir, "temp", @session_id.to_s
    @temp_out_dir = File.join @temp_dir, "out"
    @deps_dir = File.join @config_dir, "deps"
  end

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

  def run
    FileUtils.mkdir_p @temp_out_dir
    FileUtils.mkdir_p @deps_dir
    @targets.each { |t| redo_for_ t }
    FileUtils.rm_rf @temp_dir
  end

  def redo_for_ target
    puts "visit #{target}"
    dofile = list_do_files(target).select { |bn, df| File.exist? df }
    abort "no dofiles found." if dofile.empty?

    run_do target, dofile[0]

    if @deps_path
      deps = YAML::load_file @deps_path
      deps = [] unless deps
      deps << [:existing_dependency, target, Digest::MD5.file(target).to_s]
      File.open(@deps_path, "w") { |file| file << YAML.dump(deps) }
    end
  end

  def run_do target, dofile
    tmp_out = File.join @temp_dir, target
    tmp_deps = Tempfile.new target, @tmp_out_dir
    p "sh -vxe \"#{dofile[1]}\" \"#{dofile[0]}\" \"#{dofile[0]}\" \"#{tmp_out}\""
    env = {@REDO_DEPS_PATH => tmp_deps.path, @REDO_CALL_DEPTH => "#{@call_depth + 1}"}
    system(env, "sh", "-vxe", "#{dofile[1]}", "#{dofile[0]}", "#{dofile[0]}", "#{tmp_out}")
    FileUtils.mv tmp_out, target, :force => true
    FileUtils.mv tmp_deps, File.join(@deps_dir, target), :force => true
  end
end

case $0
when /.*(redo)(-ifchange)*$/
  redo_ = Redo.new ARGV
  redo_.run
else
  abort "unknown redo command"
end
