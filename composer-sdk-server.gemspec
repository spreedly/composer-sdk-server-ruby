# frozen_string_literal: true

require_relative 'lib/composer/version'

Gem::Specification.new do |spec|
  spec.name = 'spreedly-composer-sdk-server'
  spec.version = Composer::VERSION
  spec.authors = ['Spreedly']
  spec.email = ['support@spreedly.com']

  spec.summary = 'Spreedly Composer Ruby Server SDK'
  spec.description = 'Server-side SDK for integrating Spreedly Composer into Ruby applications'
  spec.homepage = 'https://github.com/spreedly/composer-sdk-server-ruby'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/spreedly/composer-sdk-server-ruby'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{lib}/**/*') + %w[README.md CHANGELOG.md LICENSE NOTICE THIRD-PARTY-LICENSES]
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'faraday', '~> 2.14', '>= 2.14.3'

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.91.0'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'webmock', '~> 3.18'
end
