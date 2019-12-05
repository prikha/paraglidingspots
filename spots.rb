#!/usr/bin/env ruby
require "bundler/setup"
require "hanami/cli"
require 'nokogiri'
require 'logger'

class Filesize
  def self.pretty(bytes)
    {
      'B'  => 1024,
      'KB' => 1024 * 1024,
      'MB' => 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024 * 1024
    }.each_pair { |e, s| return "#{(bytes.to_f / (s / 1024)).round(2)}#{e}" if bytes < s }
  end
end

module ParaglidingSpots
  module CLI
    module Commands
      extend Hanami::CLI::Registry

      class Filter < Hanami::CLI::Command
        argument :path, required: true, desc: "Path to KML file"
        option :min_rating, default: "4", values: %w[1 2 3 4 5 6], desc: "Filter spots ranked above that value"
        option :dest, desc: "Path to output file(by default adds _filtered suffix to the input)"
        option :desc, desc: "Provide some substring to be present in the description"
        option :name, desc: "Provide some substring to be present in the name"
        option :without, desc: "Comma separated tag names that have to be cleared out"

        def call(path:, **options)
          logger.info "Path: #{path}"
          logger.info "Options:"
          options.map do |k,v|
            logger.info "\t#{k}: #{v}"
          end
          doc = File.open(path) { |f| Nokogiri::XML(f) }
          dest = options.delete(:dest)
          without = options.delete(:without)
          
          
          measure(doc, ->(d){ d.css('Placemark').count }) do |doc|
            doc.css('Placemark').each do |el|
              el.remove unless satisfy_conditions?(node: el, **options)
            end
          end

          without.split(',').map(&:strip).map do |tag|
            doc.css(tag).map(&:remove)
          end

          dest ||= File.expand_path('../tmp/results.kml', __FILE__)
          File.write(dest, doc.to_xml)
          logger.info "Output file size: #{Filesize.pretty(File.size(dest))}."
        end

        private

        def measure(doc, counter)
          before = counter.call(doc)
          yield doc
          after = counter.call(doc)
          logger.info "Results: #{after}/#{before}"
        end

        def satisfy_conditions?(node:, min_rating:, desc: nil, name: nil)
          conditions(min_rating:min_rating, desc: desc, name: name).all? do |lambda|
            lambda.call(node)
          end
        end

        def conditions(min_rating:, desc:, name:)
          [].tap do |conds|
            conds << ->(placemark) { placemark.css('description').text.match?(/rating [#{min_rating}-6]\/6/) }
            conds << ->(placemark) { placemark.css('description').text.match?(/#{desc}/i) } if desc
            conds << ->(placemark) { placemark.css('name').text.match?(/#{name}/i) } if name
          end
        end

        def logger
          @logger ||= begin 
            l = Logger.new(STDOUT)
            l.level = Logger::INFO
            l
          end
        end
      end
    end
  end
end

class Version < Hanami::CLI::Command
  def call(*)
    puts 'v0.0.1'
  end
end

ParaglidingSpots::CLI::Commands.register "filter", ParaglidingSpots::CLI::Commands::Filter
ParaglidingSpots::CLI::Commands.register "v",  Version

Hanami::CLI.new(ParaglidingSpots::CLI::Commands).call