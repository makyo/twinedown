#!/usr/bin/env ruby

require 'nokogiri'
require 'optparse'
require 'rubygems'

require './twine.rb'

$VERSION = '0.0.1'

$options = {
  :title => false,
  :ids => false,
  :embed => false,
  :stroke => '#000',
  :fill => '#fff',
  :style => true,
}

##
# Builds $options from command line options

OptionParser.new do |opts|
  opts.banner = "#{$0} #{$VERSION}- convert a twine file to an SVG map"
  opts.separator ''
  opts.separator "Usage: #{$0} [options] twine_file\n\n"

  opts.on('-t', '--with-title', 'add passage title to passages') do |v|
    $options[:title] = v
  end

  opts.on('-i', '--ids', 'add passage IDs to passages') do |v|
    $options[:ids]
  end

  opts.on('-e', '--embed', 'generate an SVG for embedding (just the <svg> tag)') do |v|
    $options[:embed] = v
  end

  opts.on('-s COLOR', '--stroke=COLOR', 'sets the stroke color') do |v|
    $options[:stroke] = v
  end

  opts.on('-f COLOR', '--fill=COLOR', 'sets the fill color') do |v|
    $options[:fill] = v
  end

  opts.on('--no-style', 'do not embed style information') do |v|
    $options[:style] = v
  end

  opts.on('-h', '--help', 'prints this help') do
    puts opts
    exit
  end
end.parse!

##
# Fakes word-wrapping for a given bit of text, max width of +width, max lines
# of +max+.
#
# SVG doesn't do word wrapping. Like, at all. So we fake it by breaking text
# into lines as best as we can without knowing the width of the output.

def fakewrap(str, width, max)
  parts = str.split(/\s+/)
  result = []

  # Work until were out of words
  until parts.length == 0 do
    part = ''

    # Work as long as we're under the character limit
    while part.length < width do
      part = [part, parts.shift].join(' ')
    end
    result << part.strip
  end

  # If we're over the max lines, ellipsis the last line
  if result.length > max
    result = result[0..max - 1]
    result << '...'
  end
  return result
end

##
# Builds an SVG from a twine object +twine+

def twine2svg(twine)
  save_with = Nokogiri::XML::Node::SaveOptions::FORMAT
  # Generate an SVG header only if requested
  if $options[:embed]
    save_with += Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
  end

  # Generate default styles (only used if requested)
  style = <<-STYLE
  .twine .passage rect {
    fill: #{$options[:fill]};
    stroke: #{$options[:stroke]};
    stroke-width: 2px;
  }
  .twine .passage.start rect {
    stroke-width: 4px;
  }
  .twine .link {
    stroke: #{$options[:stroke]};
    stroke-width: 2px;
  }
  .twine text {
    fill: #{$options[:stroke]};
  }
  STYLE

  # For each link, generate a line for the path specification
  path_contents = twine.links.inject([]) do |memo, link|
    fromX = link.from.x + 54
    fromY = link.from.y + 54
    toX = link.to.x + 54
    toY = link.to.y + 54
    memo << "M#{fromX} #{fromY} L #{toX} #{toY}"
  end

  svg = Nokogiri::XML::Builder.new do |xml|

    # If we request a header, include a docstring
    if !$options[:embed]
      xml.doc.create_internal_subset(
        'svg',
        '-//W3C//DTD SVG 1.1//EN',
        'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd'
      )
    end

    xml.svg(
      'xmlns' => 'http://www.w3.org/2000/svg',
      'xmlns:xlink' => 'http://www.w3.org/1999/xlink',
      :width => twine.extentX + 110,
      :height => twine.extentY + 110,
      :viewbox => "0 0 #{twine.extentX + 110} #{twine.extentY + 110}"
    ) {

      # Comment about generator
      xml << "<!-- Genereated with twine2svg #{$VERSION} -->"

      # Include style if requested
      if $options[:style]
        xml.style style
      end

      xml.g(:class => 'twine') {

        # Include all the links first, so that the passages overlay
        # them; SVG works on a painterly algorithm
        xml.path(:class => 'link', :d => path_contents.join(' '))

        # Write each passage
        twine.passages.each do |passage|
          xml.g(:class => "passage#{passage.start ? ' start': ''}") {
            xml.title passage.name
            xml.rect(:x => passage.x + 4,
                     :y => passage.y + 4,
                     :width => 100, :height => 100)

            # Write the title of the passage if requested
            if $options[:title]
              fakewrap(passage.name, 10, 5).each_with_index do |word, i|
                xml.text_(
                  :x => passage.x + 54,
                  :y => passage.y + 5 + 16 * i,
                  'text-anchor' => 'middle',
                  'alignment-baseline' => 'before-edge'
                ) {
                  xml.text word
                }
              end
            end

            # Write the ID of the passage if requested
            if $options[:ids]
              xml.text_(
                :x => passage.x + 10,
                :y => passage.y + 10,
                'text-anchor' => 'start',
                'alignment-baseline' => 'before-edge'
              ) {
                xml.text passage.id
              }
            end
          }
        end
      }
    }
  end

  # Print it out to the user
  puts svg.to_xml(:save_with => save_with)
end

if ARGV.length != 1
  raise 'Must specify a single twine file'
else
  twine2svg(Twine.new(ARGV[0]))
end
