#!/usr/bin/env ruby

require 'nokogiri'
require 'rubygems'
require 'yaml'
require 'byebug'


##
# This struct stores all the information needed for a link between passages

Link = Struct.new('Link', :from, :to, :text, :type) do |link|
  def to_s
    "\"#{text}\": #{from} -> #{to} (#{type})"
  end

  def endpoints
    connectors = {
      :NW => [2, 2],
      :SE => [98, 98],
      :NE => [98, 2],
      :SW => [2, 98],
      :N => [50, 0],
      :S => [50, 100],
      :E => [100, 50],
      :W => [0, 50]
    }
    shortest_path = 1000000
    generated_endpoints = []
    connectors.each do |from_key, from_connector|
      ep_from = [from.x + from_connector[0], from.y + from_connector[1]]
      connectors.each do |to_key, to_connector|
        ep_to = [to.x + to_connector[0], to.y + to_connector[1]]
        path = Math.sqrt(((ep_from[0] - ep_to[0]).abs ** 2) + ((ep_from[1] - ep_to[1]).abs ** 2)).to_i
        if path < shortest_path + 25
          shortest_path = path
          generated_endpoints = [ep_from, ep_to]
        end
      end
    end
    return generated_endpoints
  end
end

##
# This class represents a passage in a twine game

class Passage

  # Regular expression for matching a classic link
  @@link_re =
  Regexp.new('\[\[(?<text_or_to>[^\]\]]+?)((->|\|)(?<to>[^\]\]]+?))?\]\]')

  attr_accessor :x, :y, :start
  attr_reader :id, :name, :body, :links

  ##
  # Create a passage given a Nokogiri +node+ and the +twine+ game containing
  # it.

  def initialize(node, twine)
    @twine = twine
    @start = false
    @id = node['pid']
    @name = node['name']
    @tags = node['tags']
    @x = @y = nil
    if node.key?('position')
      @x, @y = node['position'].split(',').map {|e| e.to_i}
    end
    @body = node.text
    @links = []
  end

  ##
  # Parses all of the links contained within the passage's body

  def parse_links
    @body.scan(@@link_re) do |x|
      m = Regexp.last_match
      type = 'link'
      from = self
      text = m['text_or_to']
      to = @twine.passage_from_name(m['to'] ? m['to'] : m['text_or_to'])
      @links << Link.new(from, to, text, type)
    end
  end

  def to_s
    "#{@start ? 'START: ' : ''}#{@name}"
  end

  def to_str
    to_s
  end
end

##
# This class represents a twine game

class Twine
  attr_reader :extentX, :extentY, :passages, :links

  ##
  # Load a twine game from +twine_file+

  def initialize(twine_file)
    twine = Nokogiri::HTML(open(twine_file))
    @twine_data = twine.css('tw-storydata')
    if @twine_data.length == 0
      raise 'No twine data found in that file'
    end

    @title = @twine_data[0]['name']
    @format = @twine_data[0]['format']
    @creator = @twine_data[0]['creator']
    @creator_version = @twine_data[0]['creator_version']
    @ifid = @twine_data[0]['ifid']
    @format = @twine_data[0]['format']
    @options = @twine_data[0]['options']

    # Build passages from each <tw-passagedata> element
    @passages = @twine_data.css('tw-passagedata').collect do |passagedata|
      Passage.new(passagedata, self)
    end

    # Find the starting node and mark it as such
    @start = @passages.find do |e|
      e.id == @twine_data[0]['startnode']
    end
    @start.start = true

    # Normalize the coordinates of all passages (shift them over to start
    # at 0,0) and set the extents
    @extentX = 0
    @extentY = 0
    normalize_coordinates

    # Parse twine links
    @passages.each {|e| e.parse_links}
    @links = @passages.collect {|e| e.links}.flatten.compact
  end

  ##
  # Gets a passage based on its name
  def passage_from_name(name)
    @passages.find {|e| e.name == name}
  end

  def to_s
    {
      @title => {
        'extent' => [[0, 0], [@extentX, @extentY]],
        'passages' => @passages.collect {|e| e.to_s},
        'links' => @links.collect {|e| e.to_s}
      }
    }.to_yaml
  end

  def to_str
    to_s
  end

  private
  ##
  # Shift all boxes over so that they're all positive with the origin at
  # (0,0) and set the extends of the graph
  def normalize_coordinates
    minY = minX = 1000000
    maxX = maxY = -minX
    @passages.each do |passage|
      if passage.x < minX then minX = passage.x end
      if passage.x > maxX then maxX = passage.x end
      if passage.y < minY then minY = passage.y end
      if passage.y > maxY then maxY = passage.y end
    end
    x_distance = 0 - minX
    y_distance = 0 - minY
    @extentX = maxX + x_distance
    @extentY = maxY + y_distance
    @passages.each do |passage|
      passage.x += x_distance
      passage.y += y_distance
    end
  end
end
