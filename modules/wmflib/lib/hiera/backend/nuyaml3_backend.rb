# Nuyaml Hiera backend - the yaml backend with some sugar on top
#
# Based on the original yaml_backend from hiera distribution, any
# modification/addition:
# Author: Giuseppe Lavagetto <glavagetto@wikimedia.org>
# Copyright  (c) 2014 Wikimedia Foundation
#
#
# This backend allows some more flexibility over the vanilla yaml
# backend, as path expansion in the lookup.
#
# == Private path
#
# If you define a 'private' data source in hiera, we will look up
# in a data.yaml file in the data dir we've specified as the datadir
# for a 'private' backend, or in the default datadir as a fallback.
#
# == Path expansion
#
# Any hierarchy named in the backend-configuration section
# :expand_path be expanded when looking the file up on disk. This
# allows both to have a more granular set of files, but also to avoid
# unnecessary cache evictions for cached data.
# === Example
#
# Say your hiera.yaml has defined
#
# :nuyaml:
#   :expand_path:
#     - module_data
#
# :hierarchy:
#   - common
#   - module_data
#
# then when searching hiera for say passwords::mysql::s1, hiera will
# first load the #{datadir}/common.yaml file and search for
# passwords::mysql::s1, then if not found, it will search for 's1'
# inside the file #{datadir}/module_data/passwords/mysql.yaml
#
# Unless very small, all files should be split up like this.
#
# == Regexp matching
#
# As multiple hosts may correspond to the same rules/configs in a
# large cluster, we allow to define a self-contained "regex.yaml" file
# in your datadir, where each different class of servers may be
# represented by a label and a corresponding regexp.
#
# === Example
# Say you have a lookup for "cluster", and you have
# "regex/%{hostname}" in your hierarchy; also, let's say that your
# scope contains hostname = "web1001.local". So if your regex.yaml
# file contains:
#
# databases:
#   __regex: !ruby/regex '/db.*\.local/'
#   cluster: db
#
# webservices:
#   __regex: !ruby/regex '/^web.*\.local$/'
#   cluster: www
#
# This will make it so that "cluster" will assume the value "www"
# given the regex matches the "webservices" stanza
#
class Hiera
  module Backend
    # This naming is required by puppet.
    class Nuyaml3_backend
      def initialize(cache = nil)
        require 'yaml'
        @cache = cache || Filecache.new
        config = Config[:nuyaml3]
        @expand_path = config[:expand_path] || []
      end

      def get_path(key, scope, source, context)
        config_section = :nuyaml3
        # Special case: regex
        if %r{^regex/}.match(source)
          Hiera.debug("Regex match going on - using regex.yaml")
          return Backend.datafile(config_section, scope, 'regex', "yaml")
        end

        # Special case: 'private' repository.
        # We use a different datadir in this case.
        # Example: private/common will search in the common source
        # within the private datadir
        if %r{private/(.*)} =~ source
          config_section = :private3
          source = Regexp.last_match(1)
        end

        # Special case: 'secret' repository. This is practically labs only
        # We use a different datadir in this case.
        # Example: private/common will search in the common source
        # within the private datadir
        if %r{secret/(.*)} =~ source
          config_section = :secret3
          source = Regexp.last_match(1)
        end

        Hiera.debug("The source is: #{source}")
        # If the source is in the expand_path list, perform path
        # expansion. This is thought to allow large codebases to live
        # with fairly small yaml files as opposed to a very large one.
        # Example:
        # $apache::mpm::worker will be in common/apache/mpm.yaml
        paths = @expand_path.map{ |x| Backend.parse_string(x, scope, {}, context) }
        if paths.include? source
          namespaces = key.gsub(/^::/, '').split('::')
          namespaces.pop

          unless namespaces.empty?
            source += "/".concat(namespaces.join('/'))
          end
        end

        Backend.datafile(config_section, scope, source, "yaml")
      end

      def plain_lookup(key, data, scope, context)
          return nil unless data.include?(key)
          Backend.parse_answer(data[key], scope, {}, context)
      end

      def regex_lookup(key, matchon, data, scope, context)
        data.each do |label, datahash|
          r = datahash["__regex"]
          Hiera.debug("Scanning label #{label} for matches to '#{r}' in '#{matchon}' ")
          next unless r.match(matchon)
          Hiera.debug("Label #{label} matches; searching within it")
          next unless datahash.include?(key)
          return Backend.parse_answer(datahash[key], scope, {}, context)
        end
        return nil
      rescue => detail
        Hiera.debug(detail)
        return nil
      end

      # Hiera 3 supports "segmented lookup" by splitting keys on dots, to allow looking up values
      # inside nested structures. In this case reconstruct the segmented key into its original form
      # and perform a lookup.
      def lookup_with_segments(segments, scope, order_override, resolution_type, context)
        Hiera.debug("Got a segmented key #{segments}")

        lookup(segments.join('.'), scope, order_override, resolution_type, context)
      end

      def lookup(key, scope, order_override, resolution_type, context)
        answer = nil

        Hiera.debug("Looking up #{key}")

        Backend.datasources(scope, order_override) do |source|
          Hiera.debug("Loading info from #{source} for #{key}")

          yamlfile = get_path(key, scope, source, context)

          Hiera.debug("Searching for #{key} in #{yamlfile}")

          next if yamlfile.nil?

          Hiera.debug("Loading file #{yamlfile}")

          next unless File.exist?(yamlfile)

          data = @cache.read(yamlfile, Hash) do |content|
            YAML.load(content)
          end

          next if data.nil?

          if %r{regex/(.*)$} =~ source
            matchto = Regexp.last_match(1)
            new_answer = regex_lookup(key, matchto, data, scope, context)
          else
            new_answer = plain_lookup(key, data, scope, context)
          end

          next if new_answer.nil?
          # Extra logging that we found the key. This can be outputted
          # multiple times if the resolution type is array or hash but that
          # should be expected as the logging will then tell the user ALL the
          # places where the key is found.
          Hiera.debug("Found #{key} in #{source}")

          # for array resolution we just append to the array whatever
          # we find, we then go onto the next file and keep adding to
          # the array
          #
          # for priority searches we break after the first found data
          # item

          case resolution_type
          when :array
            raise Exception, "Hiera type mismatch: expected Array and got #{new_answer.class}" unless new_answer.kind_of?(Array) || new_answer.kind_of?(String)
            answer ||= []
            answer << new_answer
          when :hash, Hash
            raise Exception, "Hiera type mismatch: expected Hash and got #{new_answer.class}" unless new_answer.kind_of? Hash
            answer ||= {}
            rt = resolution_type
            # If we get :hash as a resolution_type, we will use the defaults.
            rt = nil if resolution_type == :hash

            answer = Backend.merge_answer(new_answer, answer, rt)
          else
            answer = new_answer
            break
          end
        end
        if answer.nil?
          Hiera.debug("No answer! #{key}")
          throw(:no_such_key)
        end
        answer
      end
    end
  end
end
