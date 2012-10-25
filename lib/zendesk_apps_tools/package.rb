require 'multi_json'
require 'jshintrb'

class ZendeskAppsTools::Package

  LINTER_OPTIONS = {
    # ENFORCING OPTIONS:
    :noarg => true,
    :undef => true,

    # RELAXING OPTIONS:
    :eqnull => true,
    :laxcomma => true,

    # PREDEFINED GLOBALS:
    :predef =>  %w(
                  _ console services helpers alert JSON Base64
                  clearInterval clearTimeout setInterval setTimeout
                )
  }.freeze

  class AppValidationError < StandardError
    class << self
      attr_accessor :key
    end
  end

  class MissingManifestError < AppValidationError
    self.key = :missing_manifest
  end

  class MissingSourceError < AppValidationError
    self.key = :missing_source
  end

  class MissingManifestKeysError < AppValidationError
    self.key = :missing_manifest_keys
  end

  class JSHintError < AppValidationError
    self.key = :jshint_error

    def initialize(warnings)
      super
      errors = warnings.map do |err|
        { "line" => err['line'], "error" => err["reason"], "formatted" => "L#{err['line']}: #{err['reason']}" }
      end

      @detail = {"errors" => errors}
    end
  end

  def initialize(dir)
    @dir           = dir
    @source_path   = File.join(@dir, 'app.js')
    @manifest_path = File.join(@dir, 'manifest.json')
  end

  def validate!
    validate_presence_of_manifest!
    validate_required_manifest_fields!
    validate_presence_of_source!
    validate_jshint_on_source!
    true
  end

  def validate_presence_of_manifest!
    unless File.exist?(@manifest_path)
      raise MissingManifestError
    end
  end

  def validate_presence_of_source!
    unless File.exist?(@source_path)
      raise MissingSourceError
    end
  end

  def validate_required_manifest_fields!
    missing = [
               'default_locale',
               'author'
              ].select do |key|
      self.manifest[key].nil?
    end

    unless missing.empty?
      raise MissingManifestKeysError, missing.join(",")
    end
  end

  def validate_jshint_on_source!
    warnings = linter.lint(src)
    unless warnings.empty?
      raise JSHintError.new(warnings)
    end
  end

  def linter
    Jshintrb::Lint.new(LINTER_OPTIONS)
  end

  def src
    @src ||= File.read(@source_path)
  end

  def templates
    @templates ||= begin
      templates_dir = File.join(@dir, 'templates')
      Dir["#{templates_dir}/*.hdbs"].inject({}) do |h, file|
        str = File.read(file)
        str.chomp!
        h[File.basename(file, File.extname(file))] = str
        h
      end
    end
  end

  def translations
    @translations ||= begin
      translation_dir = File.join(@dir, 'translations')
      default_translations = MultiJson.load(File.read("#{translation_dir}/#{self.default_locale}.json"))

      Dir["#{translation_dir}/*.json"].inject({}) do |h, tr|
        locale = File.basename(tr, File.extname(tr))
        locale_translations = if locale == self.default_locale
                                default_translations
                              else
                                default_translations.deep_merge(MultiJson.load(File.read(tr)))
                              end

        h[locale] = locale_translations
        h
      end
    end
  end

  def locales
    translations.keys
  end

  def default_locale
    manifest["default_locale"]
  end

  def translation(en)
    translations[en]
  end

  def name
    manifest["name"]
  end

  def author
    {
      :name  => manifest['author']['name'],
      :email => manifest['author']['email']
    }
  end

  def assets
    @assets ||= begin
      pwd = Dir.pwd
      Dir.chdir(@dir)
      assets = Dir["assets/**/*"]
      Dir.chdir(pwd)
      assets
    end
  end

  def path_to(file)
    File.join(@dir, file)
  end

  def manifest
    @manifest ||= begin
      path = File.join(@dir, 'manifest.json')
      if !File.exist?(path)
        raise AppValidationError.new(I18n.t('txt.admin.lib.zendesk.app_market.app_package.package.errors.missing_manifest'))
      end
      MultiJson.load(File.read(path))
    end
  end
end
