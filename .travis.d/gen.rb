require 'yaml'
require 'json'
require 'erb'

SOURCE_DIR = File.expand_path(File.dirname(__FILE__))
TEMPLATES_DIR = File.join SOURCE_DIR, '/templates/'

APP_TEMPLATE = File.join TEMPLATES_DIR, 'app.yaml.erb'
INGRESS_TEMPLATE = File.join TEMPLATES_DIR, 'ingress.yaml.erb'

def basename_no_ext(file)
  File.basename(file, File.extname(file))
end

def load_app_data(data, app_config, dome_name, app_name)
  # generate more configs part
  if app_config['git'].is_a? String
    remote = app_config['git']
    app_config['git'] = {}
    app_config['git']['remote'] = remote
  end
  git = app_config['git']['remote']
  branch = app_config['git']['branch'] || 'master'
  git_parts = git.split(File::SEPARATOR)
  repo_name = basename_no_ext(git_parts[-1])
  org_name = git_parts[-2]

  # get git rev
  git_rev = app_config['git']['rev']
  if git_rev.nil?
    git_rev = `git ls-remote #{git} #{branch}`
    git_rev = git_rev.strip.split[0]
  end

  shortname = if app_config['name'] && app_name == :main
                app_config['name']
              else
                app_name
              end
  data[dome_name] = {} unless data.key? dome_name
  data[dome_name]['name'] = dome_name
  data[dome_name]['apps'] = {} unless data[dome_name].key? 'apps'
  data[dome_name]['apps'][app_name] = app_config
  data[dome_name]['apps'][app_name]['git']['user'] = org_name
  data[dome_name]['apps'][app_name]['git']['shortname'] = repo_name
  data[dome_name]['apps'][app_name]['git']['rev'] = git_rev
  data[dome_name]['apps'][app_name]['shortname'] = shortname
  data[dome_name]['apps'][app_name]['uid'] = "#{shortname}-#{dome_name}"
  data
end

# Load all the configuration files!
def load_config
  # Go through all the .yaml and .yml files here!
  (Dir['**/*.yaml'] + Dir['**/*.yml'])
    .select { |f| File.file? f }
    .reject { |f| basename_no_ext(f)[0] == '.' || f[0] == '.' }
    .map    { |f| [YAML.safe_load(File.read(f)), f] }
    .reject { |y| y[0]['ignore'] }
    .each_with_object({}) do |app_data, data|

    app_config, file = app_data
    puts "Parsing #{file}."

    dome_name, app_name, overflow = File.split file

    if file =~ /main\.ya*ml/
      dome_name = 'default'
      app_name = :main
    elsif app_name.nil? || !overflow.nil?
      raise "Cannot handle more than one folder deep: #{file}"
    else
      app_name = basename_no_ext app_name
    end

    load_app_data(data, app_config, dome_name, app_name)
  end
end

`rm -rf .output/*.yaml`

biodomes = load_config

biodomes.each do |dome_name, biodome|
  # TODO: get the real value from
  biodome['mongo'] = 'altered-pug-mongodb'

  biodome['apps'].each do |app_name, app|
    path = ".output/#{app_name}-#{dome_name}-deployment.yaml"
    puts "Writing #{path}."

    File.open path, 'w' do |file|
      data = ERB.new(File.read(APP_TEMPLATE)).result(binding)
      file.write(data)
    end
  end
end

path = '.output/ingress.yaml'
puts "Writing #{path}."

File.open path, 'w' do |file|
  data = ERB.new(File.read(INGRESS_TEMPLATE)).result(binding)
  file.write(data)
end
