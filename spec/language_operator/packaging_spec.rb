# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe 'Gem packaging', type: :packaging do
  describe 'built gem' do
    let(:gem_name) { "language-operator-#{LanguageOperator::VERSION}.gem" }
    let(:gem_path) { File.join(__dir__, '../..', gem_name) }

    before(:all) do
      # Build gem once for all tests
      @gem_built = system("cd #{File.join(__dir__, '../..')} && gem build language-operator.gemspec > /dev/null 2>&1")
    end

    it 'builds successfully' do
      expect(@gem_built).to be true
      expect(File.exist?(gem_path)).to be true
    end

    context 'when unpacked' do
      let(:unpack_dir) { Dir.mktmpdir('gem_unpack') }
      let(:unpacked_gem_dir) { File.join(unpack_dir, "language-operator-#{LanguageOperator::VERSION}") }

      before do
        Dir.chdir(unpack_dir) do
          system("gem unpack #{gem_path} > /dev/null 2>&1")
        end
      end

      after do
        FileUtils.rm_rf(unpack_dir)
      end

      it 'includes constants.rb with correct permissions' do
        constants_path = File.join(unpacked_gem_dir, 'lib/language_operator/constants.rb')
        expect(File.exist?(constants_path)).to be true

        stat = File.stat(constants_path)
        permissions = format('%o', stat.mode)
        expect(permissions).to end_with('644')
      end

      it 'includes task_tracer.rb file' do
        task_tracer_path = File.join(unpacked_gem_dir, 'lib/language_operator/instrumentation/task_tracer.rb')
        expect(File.exist?(task_tracer_path)).to be true
      end

      it 'can be required successfully' do
        # Add unpacked gem lib path to load path temporarily
        lib_path = File.join(unpacked_gem_dir, 'lib')
        original_load_path = $LOAD_PATH.dup

        begin
          $LOAD_PATH.unshift(lib_path)

          # Test requiring the main library file
          expect do
            require 'language_operator/version'
            require 'language_operator/constants'
            require 'language_operator/instrumentation/task_tracer'
          end.not_to raise_error
        ensure
          $LOAD_PATH.replace(original_load_path)
        end
      end

      it 'has readable file permissions for all library files' do
        lib_files = Dir[File.join(unpacked_gem_dir, 'lib/**/*.rb')]
        expect(lib_files).not_to be_empty

        lib_files.each do |file|
          stat = File.stat(file)
          permissions = format('%o', stat.mode)

          # Check that file is readable by others (644 or similar)
          expect(permissions).to end_with('644'), "File #{file} has permissions #{permissions}, expected to end with 644"
        end
      end
    end

    after(:all) do
      # Clean up built gem
      gem_file = File.join(__dir__, '../..', "language-operator-#{LanguageOperator::VERSION}.gem")
      FileUtils.rm_f(gem_file)
    end
  end
end