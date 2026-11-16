# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'
require 'yaml'
require_relative '../scripts/template-repository-cloner'

RSpec.describe TemplateRepositoryCloner do
  let(:source_package) { 'com.example.springboottemplate' }
  let(:source_dir) { 'com/example/springboottemplate' }
  let(:source_class) { 'SpringBootTemplateApplication' }
  let(:package) { 'com.acme.myapp' }
  let(:target_dir) { 'com/acme/myapp' }

  before { allow($stdout).to receive(:puts) }

  describe 'standalone design' do
    it 'does not depend on anything under scripts/utilities' do
      source = File.read(File.expand_path('../scripts/template-repository-cloner.rb', __dir__))
      expect(source).not_to match(/^\s*require(_relative)?\b.*utilities/)
      expect(source.scan(/^require\s+'([^']+)'/).flatten).to all(satisfy { |lib| %w[fileutils find yaml].include?(lib) })
    end
  end

  describe 'String extensions' do
    it 'titleizes' do
      expect('hELLO'.titleize).to eq 'Hello'
      expect(''.titleize).to eq ''
    end

    it 'converts a package name to hyphen, folder and class forms' do
      expect('Com.Acme.MyApp'.dot_to_hyphen).to eq 'com-acme-myapp'
      expect('Com.Acme.MyApp'.dot_to_folder).to eq 'com/acme/myapp'
      expect('com.acme.myapp'.to_class_name).to eq 'ComAcmeMyapp'
    end

    it 'blank? is true for empty and whitespace-only strings only' do
      expect(['', '  ', "\t\n"]).to all(be_blank)
      expect(['a', ' a ']).to all(satisfy { |str| !str.blank? })
    end

    it 'safe_gsub replaces whole words only, treating dots literally' do
      text = 'com.example.app xcom.example.app com.exampleXapp com.example.app.sub'
      expect(text.safe_gsub('com.example.app', 'a.b')).to eq 'a.b xcom.example.app com.exampleXapp a.b.sub'
    end

    it 'safe_gsub treats - and . as boundaries but not letters, digits or underscores' do
      expect('my-app my-app-gradle my-apps xmy-app my-app_x'.safe_gsub('my-app', 'N')).to eq 'N N-gradle my-apps xmy-app my-app_x'
    end

    it 'safe_gsub matches text that starts or ends with punctuation' do
      expect('a (x) b'.safe_gsub('(x)', 'Y')).to eq 'a Y b'
    end

    it 'safe_gsub treats the replacement literally (no backreferences)' do
      expect('foo'.safe_gsub('foo', '\0\1x')).to eq '\0\1x'
    end
  end

  describe 'File.update_if_content_changed' do
    it 'writes only when the content differs' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'f.txt')
        File.write(path, 'a')

        File.update_if_content_changed(path, 'a')
        mtime = File.mtime(path)
        expect(File.read(path)).to eq 'a'

        File.update_if_content_changed(path, 'b')
        expect(File.read(path)).to eq 'b'
        expect(File.mtime(path)).to be >= mtime
      end
    end
  end

  describe '.load_config / .parse_args' do
    around do |example|
      Dir.mktmpdir('template-cloner-config-') do |dir|
        @dir = dir
        example.run
      end
    end

    def config_file(content)
      path = File.join(@dir, 'config.yml')
      File.write(path, content.is_a?(String) ? content : YAML.dump(content))
      path
    end

    let(:minimal) { { 'source_repository_url' => 'url', 'target_project_name' => 'my-app', 'target_package_name' => 'com.acme', 'source_package_name' => 'com.example.app' } }

    it 'loads a minimal config and defaults the optional keys' do
      expect(described_class.parse_args([config_file(minimal)])).to eq(
        source_repository_url: 'url', target_project_name: 'my-app', target_package_name: 'com.acme', source_package_name: 'com.example.app',
        source_application_class_name: nil, target_application_class_name: nil, skip_git_init: false, replacements: {}
      )
    end

    it 'loads every optional key' do
      full = minimal.merge('source_application_class_name' => 'OldApp', 'target_application_class_name' => 'NewApp', 'skip_git_init' => true,
                           'replacements' => { 'old-name' => '${target_project_name}' })
      expect(described_class.parse_args([config_file(full)])).to include(
        source_application_class_name: 'OldApp', target_application_class_name: 'NewApp', skip_git_init: true, replacements: { 'old-name' => '${target_project_name}' }
      )
    end

    it 'requires exactly one argument' do
      expect { described_class.parse_args([]) }.to raise_error(ArgumentError, /Usage/)
      expect { described_class.parse_args(%w[a b]) }.to raise_error(ArgumentError, /Usage/)
    end

    it 'rejects a missing file, invalid YAML and a non-mapping document' do
      expect { described_class.parse_args([File.join(@dir, 'nope.yml')]) }.to raise_error(ArgumentError, /Config file not found/)
      expect { described_class.parse_args([config_file("a: [unclosed\n")]) }.to raise_error(ArgumentError, /not valid YAML/)
      expect { described_class.parse_args([config_file("- a\n- b\n")]) }.to raise_error(ArgumentError, /must be a YAML mapping/)
      expect { described_class.parse_args([config_file('')]) }.to raise_error(ArgumentError, /must be a YAML mapping/)
    end

    it 'rejects unknown keys (typos) and lists the valid ones' do
      expect { described_class.parse_args([config_file(minimal.merge('packge_name' => 'x'))]) }.to raise_error(ArgumentError, /Unknown config key.*packge_name.*Valid keys/m)
    end

    it 'rejects missing or blank required keys' do
      expect { described_class.parse_args([config_file(minimal.reject { |key, _| key == 'source_package_name' })]) }.to raise_error(ArgumentError, /Missing required config key.*source_package_name/)
      expect { described_class.parse_args([config_file(minimal.merge('source_repository_url' => '  '))]) }.to raise_error(ArgumentError, /Missing required.*source_repository_url/)
    end

    it 'rejects values of the wrong type' do
      expect { described_class.parse_args([config_file(minimal.merge('target_project_name' => 5))]) }.to raise_error(ArgumentError, /'target_project_name' must be a string/)
      expect { described_class.parse_args([config_file(minimal.merge('skip_git_init' => 'yes'))]) }.to raise_error(ArgumentError, /'skip_git_init' must be true or false/)
      expect { described_class.parse_args([config_file(minimal.merge('replacements' => %w[a b]))]) }.to raise_error(ArgumentError, /'replacements' must be a mapping/)
      expect { described_class.parse_args([config_file(minimal.merge('replacements' => { 'a' => 1 }))]) }.to raise_error(ArgumentError, /must be strings/)
      expect { described_class.parse_args([config_file(minimal.merge('replacements' => { ' ' => 'x' }))]) }.to raise_error(ArgumentError, /must not be blank/)
    end

    it 'does not instantiate arbitrary Ruby objects from YAML' do
      expect { described_class.parse_args([config_file("source_repository_url: !ruby/object:Object {}\n")]) }.to raise_error(ArgumentError, /not valid YAML/)
    end
  end

  describe '.validate_inputs' do
    def validate(url = 'u', name = 'my-app', pkg = 'com.acme', source = 'com.example.app', **extra)
      described_class.validate_inputs(source_repository_url: url, target_project_name: name, target_package_name: pkg, source_package_name: source, **extra)
    end

    it 'accepts well-formed input' do
      expect { validate }.not_to raise_error
      expect { validate('u', 'spring-boot-app2', 'a1.b2.c3', 'x1.y2', source_application_class_name: 'SpringBootTemplateApplication', target_application_class_name: 'My_App') }.not_to raise_error
    end

    it 'requires each value' do
      expect { validate('') }.to raise_error(ArgumentError, /Source repository URL is required/)
      expect { validate('u', nil) }.to raise_error(ArgumentError, /Project name is required/)
      expect { validate('u', 'my-app', '  ') }.to raise_error(ArgumentError, /Package name is required/)
      expect { validate('u', 'my-app', 'com.acme', nil) }.to raise_error(ArgumentError, /Source package name is required/)
    end

    it 'rejects project names that are not kebab-case' do
      %w[myapp My-App my_app my-app- -my-app my--app 1-app].each do |bad|
        expect { validate('u', bad) }.to raise_error(ArgumentError, /Invalid target project name/), bad
      end
      expect { validate('u', "my-app\nextra") }.to raise_error(ArgumentError, /Invalid target project name/)
    end

    it 'rejects package names that are not dot-separated lowercase' do
      ['acme', 'Com.acme', 'com-acme', 'com..acme', 'com.acme.', 'comXacme', "com.acme\nx"].each do |bad|
        expect { validate('u', 'my-app', bad) }.to raise_error(ArgumentError, /Invalid target package name/), bad
        expect { validate('u', 'my-app', 'com.acme', bad) }.to raise_error(ArgumentError, /Invalid source package name/), bad
      end
    end

    it 'rejects class names that are not Java identifiers' do
      ['1App', 'My-App', 'a b', "App\nx"].each do |bad|
        expect { validate(source_application_class_name: bad) }.to raise_error(ArgumentError, /Invalid source application class name/), bad
        expect { validate(target_application_class_name: bad) }.to raise_error(ArgumentError, /Invalid application class name/), bad
      end
    end
  end

  describe '.expand_replacements' do
    let(:values) { { 'target_project_name' => 'my-app', 'target_package_name' => 'com.acme', 'target_application_class_name' => 'MyApp' } }

    it 'expands placeholders in values only and keeps order' do
      result = described_class.expand_replacements({ '${target_project_name}' => '${target_project_name}:${target_package_name}', 'b' => 'plain' }, values)
      expect(result).to eq [['${target_project_name}', 'my-app:com.acme'], %w[b plain]]
    end

    it 'rejects an unknown placeholder' do
      expect { described_class.expand_replacements({ 'a' => '${nope}' }, values) }.to raise_error(ArgumentError, /Unknown placeholder '\$\{nope\}'.*target_project_name/)
    end
  end

  describe '.run' do
    around do |example|
      Dir.mktmpdir('template-cloner-spec-') do |dir|
        @tmp = dir
        example.run
      end
    end

    def git(*args, dir: nil)
      out, status = Open3.capture2e('git', *(dir ? ['-C', dir] : []), *args)
      raise "git #{args.join(' ')} failed: #{out}" unless status.success?

      out
    end

    def write(root, rel, content)
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    # A local git repository shaped like the Spring Boot template.
    let(:template) do
      root = File.join(@tmp, 'template')
      FileUtils.mkdir_p(root)
      git('init', '-q', dir: root)
      git('config', 'user.email', 't@example.com', dir: root)
      git('config', 'user.name', 'T', dir: root)
      write(root, "src/main/java/#{source_dir}/SpringBootTemplateApplication.java",
            "package com.example.springboottemplate;\npublic class SpringBootTemplateApplication {}\n")
      write(root, "src/test/java/#{source_dir}/SpringBootTemplateApplicationTests.java",
            "package com.example.springboottemplate;\nclass SpringBootTemplateApplicationTests {}\n")
      write(root, 'build.gradle', "group = 'com.example.springboottemplate'\nmainClass = 'com.example.springboottemplate.SpringBootTemplateApplication'\n")
      write(root, 'src/main/resources/log.xml', "<logger name=\"com.example.springboottemplate\" path=\"#{source_dir}\"/>\n")
      write(root, '.gitignore', "build/\n")
      write(root, 'node_modules/pkg/index.js', "// com.example.springboottemplate\n")
      File.binwrite(File.join(root, 'logo.png'), "\xFF\xFEcom.example.springboottemplate\xFF".b)
      git('add', '-A', '-f', dir: root)
      git('commit', '-q', '-m', 'init', dir: root)
      root
    end

    let(:project) { File.join(@tmp, 'work', 'my-app') }

    def run_cloner(**opts)
      FileUtils.mkdir_p(File.join(@tmp, 'work'))
      described_class.run(**{ source_repository_url: template, target_project_name: 'my-app', target_package_name: package, source_package_name: source_package,
                              source_application_class_name: source_class, base_dir: File.join(@tmp, 'work') }.merge(opts))
    end

    it 'clones, moves the package folders, renames the application class and rewrites contents' do
      expect(run_cloner).to be true

      expect(File).to exist("#{project}/src/main/java/#{target_dir}/ComAcmeMyapp.java")
      expect(File).to exist("#{project}/src/test/java/#{target_dir}/SpringBootTemplateApplicationTests.java")
      expect(File).not_to exist("#{project}/src/main/java/com/example")
      expect(File).not_to exist("#{project}/src/test/java/com/example")
      expect(File.read("#{project}/src/main/java/#{target_dir}/ComAcmeMyapp.java")).to eq "package com.acme.myapp;\npublic class ComAcmeMyapp {}\n"
      expect(File.read("#{project}/build.gradle")).to eq "group = 'com.acme.myapp'\nmainClass = 'com.acme.myapp.ComAcmeMyapp'\n"
      expect(File.read("#{project}/src/main/resources/log.xml")).to eq "<logger name=\"com.acme.myapp\" path=\"#{target_dir}\"/>\n"
    end

    it 'leaves .git, node_modules and non-UTF-8 files untouched' do
      expect(run_cloner).to be true

      expect(File.read("#{project}/node_modules/pkg/index.js")).to eq "// com.example.springboottemplate\n"
      expect(File.binread("#{project}/logo.png")).to eq "\xFF\xFEcom.example.springboottemplate\xFF".b
      expect(git('log', '--format=%s', dir: project).strip).to eq 'init'
    end

    it 'still rewrites dotfiles whose names merely contain "git"' do
      write(template, '.gitlab-ci.yml', "image: com.example.springboottemplate\n")
      git('add', '-A', dir: template)
      git('commit', '-q', '-m', 'ci', dir: template)

      expect(run_cloner).to be true
      expect(File.read("#{project}/.gitlab-ci.yml")).to eq "image: com.acme.myapp\n"
    end

    it 'prunes only ancestors that became empty, never beyond the repo root' do
      expect(run_cloner).to be true

      expect(File).to exist("#{project}/src/main/java/com/acme")
      expect(File).to exist("#{project}/src/main")
      expect(File).to exist(project)
    end

    it 'skips the folder move when the package folder equals the template folder, but still renames the class' do
      expect(run_cloner(target_package_name: 'com.example.springboottemplate')).to be true
      expect(File).to exist("#{project}/src/main/java/#{source_dir}/ComExampleSpringboottemplate.java")
    end

    it 'succeeds when no source application class is configured, leaving class names alone' do
      expect(run_cloner(source_application_class_name: nil)).to be true

      expect(File).to exist("#{project}/src/main/java/#{target_dir}/SpringBootTemplateApplication.java")
      expect(File.read("#{project}/build.gradle")).to include 'com.acme.myapp.SpringBootTemplateApplication'
    end

    it 'uses an explicit target_application_class_name instead of the derived one' do
      expect(run_cloner(target_application_class_name: 'MyAppMain')).to be true

      expect(File).to exist("#{project}/src/main/java/#{target_dir}/MyAppMain.java")
      expect(File.read("#{project}/build.gradle")).to include 'com.acme.myapp.MyAppMain'
    end

    it 'applies configured replacements to contents, expanding placeholders, after the built-in rewrites' do
      write(template, 'README.md', "# old-name\nimage old-name:dev, volume old-name-gradle, Old Name docs\n")
      git('add', '-A', dir: template)
      git('commit', '-q', '-m', 'readme', dir: template)

      expect(run_cloner(replacements: { 'old-name' => '${target_project_name}', 'Old Name' => 'My App (${target_package_name})' })).to be true
      expect(File.read("#{project}/README.md")).to eq "# my-app\nimage my-app:dev, volume my-app-gradle, My App (com.acme.myapp) docs\n"
    end

    it 'does not rewrite file or folder names for configured replacements' do
      write(template, 'old-name.txt', "x\n")
      git('add', '-A', dir: template)
      git('commit', '-q', '-m', 'name', dir: template)

      expect(run_cloner(replacements: { 'old-name' => 'new-name' })).to be true
      expect(File).to exist("#{project}/old-name.txt")
    end

    it 'fails before cloning on an unknown placeholder' do
      expect(described_class).not_to receive(:system)

      expect(run_cloner(replacements: { 'a' => '${nope}' })).to be false
    end

    it 'succeeds when the template has no application class file' do
      git('rm', '-q', "src/main/java/#{source_dir}/SpringBootTemplateApplication.java", dir: template)
      git('commit', '-q', '-m', 'rm', dir: template)

      expect(run_cloner).to be true
    end

    it 'returns false and reports when the clone fails' do
      expect($stdout).to receive(:puts).with(/\[ERROR\] Failed to create repo from template: Failed to clone/).at_least(:once)

      expect(run_cloner(source_repository_url: File.join(@tmp, 'missing'), base_dir: @tmp)).to be false
    end

    it 'returns false without cloning when an input is invalid' do
      expect(described_class).not_to receive(:system)
      expect($stdout).to receive(:puts).with(/\[ERROR\].*Invalid target project name/m).at_least(:once)

      expect(run_cloner(target_project_name: 'MyApp', base_dir: @tmp)).to be false
    end

    it 'does not hand the URL or folder to a shell' do
      expect(described_class).to receive(:system).with('git', 'clone', '--depth', '1', '--single-branch', 'a b; touch x', File.join(@tmp, 'my-app')).and_return(false)

      expect(run_cloner(source_repository_url: 'a b; touch x', base_dir: @tmp)).to be false
      expect(File).not_to exist('x')
    end

    describe 'git initialization' do
      before do
        allow(described_class).to receive(:rename_files_and_folders)
        allow(described_class).to receive(:update_contents)
      end

      it 'initializes and commits when the clone has no .git' do
        expect(described_class).to receive(:system).with('git', 'clone', any_args).and_return(true)
        expect(described_class).to receive(:system).with('git', '-C', project, 'init').and_return(true)
        expect(described_class).to receive(:system).with('git', '-C', project, 'add', '-A').and_return(true)
        expect(described_class).to receive(:system).with('git', '-C', project, 'commit', '-m', 'Initial commit').and_return(true)

        expect(run_cloner).to be true
      end

      it 'does nothing when --skip-git-init is given' do
        expect(described_class).to receive(:system).with('git', 'clone', any_args).and_return(true)
        expect(described_class).not_to receive(:system).with('git', '-C', anything, any_args)

        expect(run_cloner(skip_git_init: true)).to be true
      end

      it 'does nothing when the clone already has a .git' do
        allow(described_class).to receive(:system).with('git', 'clone', any_args) do |*_|
          FileUtils.mkdir_p("#{project}/.git")
          true
        end
        expect(described_class).not_to receive(:system).with('git', '-C', anything, any_args)

        expect(run_cloner).to be true
      end

      it 'fails when git init fails' do
        allow(described_class).to receive(:system).with('git', 'clone', any_args).and_return(true)
        allow(described_class).to receive(:system).with('git', '-C', project, 'init').and_return(false)

        expect(run_cloner).to be false
      end

      it 'fails when the initial commit fails' do
        allow(described_class).to receive(:system).and_return(true)
        allow(described_class).to receive(:system).with('git', '-C', project, 'commit', any_args).and_return(false)

        expect(run_cloner).to be false
      end
    end
  end

  describe 'a myapp-style template driven by a YAML file (end to end)' do
    around do |example|
      Dir.mktmpdir('template-cloner-e2e-') do |dir|
        @tmp = dir
        example.run
      end
    end

    it 'retargets package, folders, class, and the project name via replacements' do
      template = File.join(@tmp, 'template')
      FileUtils.mkdir_p(template)
      write = lambda do |rel, content|
        FileUtils.mkdir_p(File.dirname(File.join(template, rel)))
        File.write(File.join(template, rel), content)
      end
      Open3.capture2e('git', 'init', '-q', template)
      write.call('app/src/main/java/com/example/springboottemplate/SpringBootTemplateApplication.java', "package com.example.springboottemplate;\nclass SpringBootTemplateApplication {}\n")
      write.call('app/src/test/java/com/example/springboottemplate/AppTest.java', "package com.example.springboottemplate;\nclass AppTest { Class<?> c = SpringBootTemplateApplication.class; }\n")
      write.call('app/src/main/resources/application.yml', "spring:\n  application:\n    name: springboot-template\n")
      write.call('docs/architecture.md', "Module `app` owns `com.example.springboottemplate`; image springboot-template:dev, volume springboot-template-gradle\n")
      Open3.capture2e('git', '-C', template, '-c', 'user.email=t@e.com', '-c', 'user.name=T', 'add', '-A')
      Open3.capture2e('git', '-C', template, '-c', 'user.email=t@e.com', '-c', 'user.name=T', 'commit', '-q', '-m', 'init')

      config = File.join(@tmp, 'config.yml')
      File.write(config, <<~YAML)
        source_repository_url: #{template}
        target_project_name: lease-service
        target_package_name: com.myapp
        source_package_name: com.example.springboottemplate
        source_application_class_name: SpringBootTemplateApplication
        target_application_class_name: LeaseApplication
        replacements:
          springboot-template: ${target_project_name}
      YAML

      work = File.join(@tmp, 'work')
      FileUtils.mkdir_p(work)
      expect(described_class.run(**described_class.load_config(config), base_dir: work)).to be true

      project = File.join(work, 'lease-service')
      expect(File.read("#{project}/app/src/main/java/com/myapp/LeaseApplication.java")).to eq "package com.myapp;\nclass LeaseApplication {}\n"
      expect(File.read("#{project}/app/src/test/java/com/myapp/AppTest.java")).to include 'LeaseApplication.class'
      expect(File).not_to exist("#{project}/app/src/main/java/com/example")
      expect(File.read("#{project}/app/src/main/resources/application.yml")).to include 'name: lease-service'
      expect(File.read("#{project}/docs/architecture.md")).to eq "Module `app` owns `com.myapp`; image lease-service:dev, volume lease-service-gradle\n"
    end
  end

  describe 'command line' do
    script = File.expand_path('../scripts/template-repository-cloner.rb', __dir__)

    it 'prints the usage and exits 1 without exactly one argument' do
      out, status = Open3.capture2e(RbConfig.ruby, script)
      expect(status.exitstatus).to eq 1
      expect(out).to include 'Usage: template-repository-cloner.rb <config.yml>'
    end

    it 'exits 1 and names the problem for a bad config file' do
      Dir.mktmpdir do |dir|
        bad = File.join(dir, 'bad.yml')
        File.write(bad, "source_repository_url: x\n")
        out, status = Open3.capture2e(RbConfig.ruby, script, bad)
        expect(status.exitstatus).to eq 1
        expect(out).to match(/Missing required config key.*target_project_name/)
      end
    end
  end
end
