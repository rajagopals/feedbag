#!/usr/bin/ruby

# Copyright (c) 2008-2014 David Moreno <david@axiombox.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require "rubygems"
require "nokogiri"
require "open-uri"
require "net/http"
require 'rss'
require 'mechanize'

class Feedbag

  CONTENT_TYPES = [
    'application/x.atom+xml',
    'application/atom+xml',
    'application/xml',
    'text/xml',
    'application/rss+xml',
    'application/rdf+xml',
  ].freeze

  def self.feed?(url)
    new.feed?(url)
  end

  def self.find(url, args = {})
    print 'Processing '
    results = new.find(url, args = {})
    puts "\n"
    results
  end

  def self.title(url)
    new.title(url)
  end


  def initialize

    # Types of feeds that we are not interested in
    blacklist_regexes = [
      /\.yahoo\.co/,
      /\.doubleclick\.net/,
      /\.aol\.com/,
      /\.msn\.com/,
      /(?<!feedproxy)\.google\./,
      /itpc:\/\//,    
      /netvibes\.com/,
      /newsgator\.com/,
      /\.live\.com/,
      /\.weico\.com/,
      /\.bloglines\.com/,
      /hanrss\.com/,  
      /addthis\.co/,
      /planetaki\.com/,
      /\.inezha\.com/,
      /\.newsonfeeds\.com/,
      /\.wikipedia\.org/,
      /\.microsoft\.com/,
      /\.emailrss\.cn/,
      /\.zhuaxia\.com/,
      /\.exe$/,
      /\.reddit\.com/,
      /\.facebook\.com/,
      /\.campbellrivermirror\.com\/contact_us/,
      /xianguo\.com/,
      /youdao\.com/,
      /\.mail\.qq\.com/,
      /\.modernhealthcare\.com/,
      /\.egroups\.com/,
      /\.tutorialspoint\.com/,
      /\.github\.com/,
      /\.sourceforge\.net/,
      /\.rssboard\.org/,
      /\.heise\.de/,
      /\.rss-verzeichnis\.de/,
      /\.cityjobs\.com/,
      /\.rojo\.com/,
      /\.pageflakes\.com/,
      /\.wikio\./,
      /\.bubbledock\.com/,
      /\.feedvalidator\.org/,
      /\.validator\.w3\.org/,
      /\.plusmo\.com/,
      /utm_source=(rss|feeds|rssfeed|rssfeeds|urss)/,
      /\.apple\.com/,
      /\.adobe\.com/,
      /\.yelp\.com/,
      /\.cnet\.com/,
      /\.npr\.org/,
      /\.gov[^a-zA-Z]/,
      /\.baidu\.com/,
      /\.dell\.com/,
      /\.qq\.com/,
      /\.about\.com/,
      /\.xml\.com/,
      /oreilly\.com/,
      /\.ibm\.com/,
      /rss\.com/,
      /webreference\.com/,
      /w3schools\.com/,
      /\.resource\.org/,
      /\.dmoz\.org/,
      /wikimedia\.org/,
      /purl\.org/,
      /inamidst\.com/,
      /userland\.com/,
      /netscape\.com/,
      /perl\.com/,
      /blogspace\.com/,
      /soapclient\.com/,
      /\.computerworld\.com/,
      /clickz\.com/,
      /freecode\.com/,
      /pluck\.com/,
      /app\.readspeaker\.com/,
      /api\.twitter\.com/,
      /\?alt=rss$/,
      /lesechos\.fr\/mesechos/
    ]

    @exclude = Regexp.union(blacklist_regexes)
    @feeds = []
    @recurse = Set.new
    @agent = Mechanize.new

    # TODO: fix mechanize meta refresh sleep bug! This causes issues!!!!! try to get http://ceweekly.cn with and without!!!
    # @agent.follow_meta_refresh = true

    @agent.open_timeout = 15
    @agent.read_timeout = 15
    @agent.redirection_limit=10
    @agent.keep_alive = false
    @agent.user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.65 Safari/537.36"
    
  end

  def feed?(url)
    # use LWR::Simple.normalize some time
    url_uri = URI.parse(url)
    url = "#{url_uri.scheme or 'http'}://#{url_uri.host}#{url_uri.path}"
    url << "?#{url_uri.query}" if url_uri.query
    
    # hack:
    url.sub!(/^feed:\/\//, 'http://')

    res = Feedbag.find(url)
    if res.size == 1 and res.first == url
      return true
    else
      return false
    end
  end

  def title(url)
    url_uri = URI.parse(url)
    url = nil
    if url_uri.scheme.nil?
      url = "http://#{url_uri.to_s}"
    else
      url = url_uri.to_s
    end 
    @agent.get(url).title
  end

  def find(url, args = {})
    if args[:recurse].nil?
      rlength = 0
    else
      rlength = args[:recurse]
    end
    
    #puts "\nFinding RSS for ...#{url} with rlength: #{rlength} with current length #{@feeds.length}"

    @recurse << url

    begin
      url_uri = URI.parse(url)
      url = nil
      if url_uri.scheme.nil?
        url = "http://#{url_uri.to_s}"
      elsif url_uri.scheme == "feed"
        return self.add_feed(url_uri.to_s.sub(/^feed:\/\//, 'http://'), nil)
      else
        url = url_uri.to_s
      end
    rescue
      puts "error in url #{url}"
      return
    end
    
    # check if feed_valid is avail
    begin
      require "feed_validator"
      v = W3C::FeedValidator.new
      v.validate_url(url)
      return self.add_feed(url, nil) if v.valid?
    rescue LoadError
      # scoo
    rescue REXML::ParseException
      # usually indicates timeout
      # TODO: actually find out timeout. use Terminator?
      # $stderr.puts "Feed looked like feed but might not have passed validation or timed out"
    rescue => ex
      $stderr.puts "#{ex.class} error ocurred with: `#{url}': #{ex.message}"
    end

    if rlength > 30 or @feeds.length > 500
      exit 1
    end

    begin
      doc = @agent.get(url)
      url = doc.uri.to_s
      
      if doc.class == Mechanize::XmlFile
        name = doc.at('title')
        name = CGI.unescapeHTML(name.text) unless name.nil?
        return self.add_feed(url, nil, name)
      elsif doc.class == Mechanize::File
        content_type = doc.response['content-type']
        content_type.to_s.gsub!(/;.*/, '').to_s.strip!
        if CONTENT_TYPES.include?(content_type)
          return self.add_feed(url)
        else
          return []
        end
      else
        begin
          return self.add_feed(url) unless RSS::Parser.parse(doc.content, false).nil?
        rescue Exception => ex
          # Not an rss. continuing to check links...
        end
      end

      # first with links
      (doc/"atom:link").each do |l|
        next unless l["rel"]
        if l["type"] and CONTENT_TYPES.include?(l["type"].downcase.strip) and l["rel"].downcase == "self"
          self.add_feed(l["href"], url, l["title"])
        end
      end

      (doc/"link").each do |l|
        next unless l["rel"]
        if l["type"] and CONTENT_TYPES.include?(l["type"].downcase.strip) and (l["rel"].downcase =~ /alternate/i or l["rel"] == "service.feed")
          self.add_feed(l["href"], url, l["title"])
        end
      end

      (doc/"a").each do |a|
        next unless a["href"]
        txt = a.text.to_s.strip
        txt = a["alt"].to_s.strip if (txt.nil? or txt.empty?)
        txt = a["title"].to_s.strip if (txt.nil? or txt.empty?)       
        if self.looks_like_feed?(a["href"])
          self.add_feed(a["href"], url, txt)
        end
      end

      # Added support for feeds like http://tabtimes.com/tbfeed/mashable/full.xml
      if url.match(/.xml$/) and doc.root and doc.root["xml:base"] and doc.root["xml:base"].strip == url.strip
        self.add_feed(url, nil)
      end

      if rlength <= 1
        (doc/"a").each do |a|
          next unless a["href"]
          # txt = a.text.to_s.strip
          # alt = a["alt"].to_s.strip
          # title = a["title"].to_s.strip
          
          a["href"] = "/" + a["href"] if a["href"][0] != '/' and a["href"][0..3] != 'http'
          begin
            absolute_uri = URI.join(url, a['href']).to_s
          rescue => ex
            # puts "Error with #{url} #{ex.message}"
            next
          end

          if absolute_uri =~ /(^|[^a-zA-Z%])(rss|feeds|rssfeed|rssfeeds|urss|collectionRss|syndication|feed|articlefeeds)([^a-zA-Z%]|$)/i
                # or absolute_uri =~ /blogs\.wsj\.com\/[^\/]*\/?$/i
                # or absolute_uri =~ /www\.fortmilltimes\.com\/[^\/]*\/[^\/]*\/?$/i
                # or absolute_uri =~ /[^\/]*\.techtarget\.com\/?$/i
                # or absolute_uri =~ /online\.wsj\.com\/public\/page\/[^\/]*\/?$/i \
                # or absolute_uri =~ /venturebeat\.com\/category\/[^\/]*\/?$/i
                # or absolute_uri =~ /fastcompany\.com\/user\/[^\/]*\/?$/i 
                # or txt.to_s =~ /(^|[^a-zA-Z%])(rss|feeds|rssfeed|rssfeeds)([^a-zA-Z%]|$)/i \
                # or alt.to_s =~ /(^|[^a-zA-Z%])(rss|feeds|rssfeed|rssfeeds)([^a-zA-Z%]|$)/i \
                # or title.to_s =~ /(^|[^a-zA-Z%])(rss|feeds|rssfeed|rssfeeds)([^a-zA-Z%]|$)/i \
                # or absolute_uri =~ /businessinsider\.com\/[^\/-]*\/?$/ 
                #or absolute_uri =~ /^http:\/\/www\.theguardian\.com\/[^\/]*((\/[^\/]*\/?$)|$)/
            unless @recurse.include?(absolute_uri)
              next unless absolute_uri.match(@exclude).nil? #Ignore the links if it is part of blacklisted regexes
              # puts "-- Recursing into: #{absolute_uri}"
              print '.'
              self.find(absolute_uri, {:recurse => rlength + 1}) #Otherwise, recurse and find RSS feeds inside that link
            end
          end
        end
      end

      if @recurse.length == 1 && @feeds.count == 0
        @recurse << ["dummy"]
        self.find(url)
      end
      
    rescue Timeout::Error => err
      $stderr.puts "Timeout error ocurred with `#{url}: #{err}'"
    rescue OpenURI::HTTPError => the_error
      $stderr.puts "Error ocurred with `#{url}': #{the_error}"
    rescue SocketError => err
      $stderr.puts "Socket error ocurred with: `#{url}': #{err}"
    rescue => ex
      $stderr.puts "#{ex.class} error ocurred with: `#{url}': #{ex.message}"
    ensure
      return @feeds
    end
    
  end

  def looks_like_feed?(url)
    if url =~ /(\.(rdf|xml|rdf|rss)$|feed=(rss|atom)\/?$)/i
      return false unless url.match(@exclude).nil?
      return true
    else
      return false
    end
  end

  def add_feed(feed_url, base_uri = nil, feed_name = nil)
    # puts "#{feed_url} - #{orig_url}"
    url = feed_url.sub(/^feed:/, '').strip

    if base_uri
      begin
        # url = base_uri + feed_url
        url = URI.join(base_uri, feed_url).to_s
      rescue => ex
        puts "Error with `#{url}' #{ex.message}"
        return
      end
    end

    # unless uri.absolute?
    #   orig = URI.parse(orig_url)
    #   url = orig.merge(url).to_s
    # end
    if !feed_name.nil?
      feed_name.gsub!(/\t|\n/, '')
      feed_name.strip!
    end
    if !url.nil?
      url.gsub!(/"/, '')
    end

    # verify url is really valid
    @feeds.push([url,feed_name]) unless @feeds.map{|k| k[0]}.include?(url)# if self._is_http_valid(URI.parse(url), orig_url)
  end

  # not used. yet.
  def _is_http_valid(uri, orig_url)
    req = Net::HTTP.get_response(uri)
    orig_uri = URI.parse(orig_url)
    case req
      when Net::HTTPSuccess then
        return true
      else
        return false
    end
  end
end

if __FILE__ == $0
  if ARGV.size == 0
    puts 'usage: feedbag url'
  else
    puts Feedbag.find ARGV.first
  end
end