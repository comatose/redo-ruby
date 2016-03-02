#!/usr/bin/env ruby

require 'pathname'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'digest'
require 'base64'

module Settings
  REDO_CALL_DEPTH = "REDO_CALL_DEPTH"
  CALL_DEPTH = ENV.fetch(REDO_CALL_DEPTH, 0).to_i

  REDO_DEPS_PATH = "REDO_DEPS_PATH"
  DEPS_PATH = ENV[REDO_DEPS_PATH]

  REDO_SESSION_ID = "REDO_SESSION_ID"
  SESSION_ID = ENV.fetch(REDO_SESSION_ID, Process.pid).to_i

  CONFIG_DIR = ".redo"
  TEMP_DIR = File.join CONFIG_DIR, "temp", SESSION_ID.to_s
  TEMP_OUT_DIR = File.join TEMP_DIR, "out"
  DEPS_DIR = File.join CONFIG_DIR, "deps"

  def Settings.encode_path file
    Base64.encode64(file).strip
  end

  def Settings.spawned_env tmp_deps_path
    {REDO_DEPS_PATH => tmp_deps_path,
     REDO_CALL_DEPTH => "#{CALL_DEPTH + 1}"}
  end

  def Settings.file_signature file
    Digest::MD5.file(file).to_s
  end
end

class Redo
  def initialize files
    @targets = files.map { |f| redo_target_from_dir(Dir.pwd, f) }

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
    FileUtils.mkdir_p Settings::TEMP_OUT_DIR
    FileUtils.mkdir_p Settings::DEPS_DIR
    begin
      @targets.each { |t| redo_for_ t }
    rescue Exception => e
      abort e.to_s
    end
    FileUtils.rm_rf Settings::TEMP_DIR
  end

  def get_dependencies target
    dep_file_name = File.join(Settings::DEPS_DIR, Settings.encode_path(target))
    return nil unless File.exist? dep_file_name
    File.open(dep_file_name, "r") { |file| YAML::load_file dep_file_name }
  end

  def up_to_date target
    return :outdated unless File.exist? target

    dofiles = list_do_files(target).select { |bn, df| File.exist? df }
    deps = get_dependencies target
    unless deps.nil?
      effective_do = deps[0][1]
      ex_dos = list_do_files(target).take_while { |df| df[1] != effective_do }
      ex_deps = ex_dos.map { |df| [:non_existing_dependency, df[1]] }
      return collect (ex_deps + deps)
    end
    return :uptodate if dofiles.empty?
    return :conflicted if !dofiles.empty?
    raise "invalid dependency: #{target}"
  end

  def up_to_date2 target
    case target[0]
    when :non_existing_dependency
      if File.exist? target[1]
        return :outdated
      else
        return :uptodate
      end

    when :existing_dependency
      if !File.exist?(target[1]) ||
         target[2] != Settings::file_signature(target[1])
        return :outdated
      else
        return up_to_date target[1]
      end
    end
  end

  def collect deps
    return :uptodate if deps.nil? || deps.empty?

    r = up_to_date2 deps[0]
    return r unless r == :uptodate

    return collect deps.drop 1
  end

  def redo_for_ target
    indent = ' ' * Settings::CALL_DEPTH
    puts "visit #{indent + target}"
    r = up_to_date(target)
    puts "#{target} status = #{r}"
    return if r == :uptodate

    dofiles = list_do_files(target).select { |bn, df| File.exist? df }
    abort "no dofiles found." if dofiles.empty?

    run_do target, dofiles[0]

    add_dependency Settings::DEPS_PATH, [:existing_dependency, target,
                                         Settings::file_signature(target)]
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
    tmp_out = File.join Settings::TEMP_DIR, target
    tmp_deps = Tempfile.new target, Settings::TEMP_OUT_DIR
    p "sh -vxe \"#{dofile[1]}\" \"#{dofile[0]}\" \"#{dofile[0]}\" \"#{tmp_out}\""
    add_dependency tmp_deps, [:existing_dependency, dofile[1],
                              Settings::file_signature(dofile[1])]
    r = system(Settings.spawned_env(tmp_deps.path), "sh", "-ve",
               "#{dofile[1]}", "#{dofile[0]}", "#{dofile[0]}", "#{tmp_out}")
    if r
      FileUtils.mv tmp_out, target, :force => true
      FileUtils.mv tmp_deps, File.join(Settings::DEPS_DIR, Settings.encode_path(target)), :force => true
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
