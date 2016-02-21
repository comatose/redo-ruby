#!/usr/bin/env ruby

require 'pathname'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'digest'
require 'base64'

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
    begin
      @targets.each { |t| redo_for_ t }
    rescue Exception => e
      abort e.to_s
    end
    FileUtils.rm_rf @temp_dir
  end

  def get_dependencies target
    dep_file_name = File.join(@deps_dir, Base64.encode64(target).strip)
    return nil unless File.exist? dep_file_name
    File.open(dep_file_name, "r") { |file| YAML::load_file dep_file_name }
  end

  def up_to_date target
    return :outdated unless File.exist? target

    dofiles = list_do_files(target).select { |bn, df| File.exist? df }
    deps = get_dependencies target
    unless deps.nil?

    end
    return :uptodate if dofiles.empty?
    return :conflicted if !dofiles.empty?
    raise "invalid dependency: #{target}"
  end

  def redo_for_ target
    puts "visit #{target}"
    return if up_to_date target

    dofiles = list_do_files(target).select { |bn, df| File.exist? df }
    abort "no dofiles found." if dofiles.empty?

    run_do target, dofiles[0]

    add_dependency @deps_path, [:existing_dependency, target, Digest::MD5.file(target).to_s]
  end

  def add_dependency dep_file, dep
    if dep_file
      deps = YAML::load_file dep_file
      deps = [] unless deps
      deps << dep
      File.open(dep_file, "w") { |file| file << YAML.dump(deps) }
    end
  end

  def run_do target, dofile
    tmp_out = File.join @temp_dir, target
    tmp_deps = Tempfile.new target, @tmp_out_dir
    p "sh -vxe \"#{dofile[1]}\" \"#{dofile[0]}\" \"#{dofile[0]}\" \"#{tmp_out}\""
    env = {@REDO_DEPS_PATH => tmp_deps.path, @REDO_CALL_DEPTH => "#{@call_depth + 1}"}
    add_dependency tmp_deps, [:existing_dependency, dofile[1], Digest::MD5.file(dofile[1]).to_s]
    r = system(env, "sh", "-ve", "#{dofile[1]}", "#{dofile[0]}", "#{dofile[0]}", "#{tmp_out}")
    if r
      FileUtils.mv tmp_out, target, :force => true
      FileUtils.mv tmp_deps, File.join(@deps_dir, target), :force => true
    else
      FileUtils.rm_f [tmp_out, tmp_deps]
      raise "#{dofile[1]} failed."
    end
  end
end

case $0
when /.*(redo)(-ifchange)*$/
  redo_ = Redo.new ARGV
  redo_.run
else
  abort "unknown redo command"
end
