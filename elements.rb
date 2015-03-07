require 'logger'
require 'httpclient'

module Elements
  module Network
    DOMAIN = 'http://www.elementsthegame.com'

    def logger
      @@logger ||= Logger.new($stdout)
    end

    def login_url; "#{DOMAIN}/testo5.php"; end

    def sync_url; "#{DOMAIN}/dev7.php"; end

    def swf_url; "#{DOMAIN}/elt133rt.swf"; end

    def default_request_headers
      {
        'Connection' => 'keep-alive',
        'Origin' => DOMAIN,
        'User-Agent' => 'Mozilla/5.0',
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Accept' => '*/*',
        'DNT' => 1,
        'Referer' => swf_url,
        'Accept-Language' => 'en-US,en;q=0.8'
      }
    end

    def url_encode_to_hash(string)
      string.split('&').inject({}) {|h, pair| parts = pair.split('='); h[parts[0]] = parts[1]; h }
    end

    def request(url, params, headers = {})
      resp = HTTPClient.new.post(url, params, default_request_headers.merge(headers))
      url_encode_to_hash(resp.content)
    end

    def self.included(base)
      base.send :extend, self
    end
  end
end

module Elements
  class Player
    include Network

    attr_accessor :attributes

    def initialize(attributes)
      self.attributes = attributes
    end

    def sync_attributes
      {
        'errorcode' => -1,
        'deck2n' => 0, #wtf?
        'deck3' => nil, #wtf?
        'newemail' => nil,
        'newpsw' => nil,
        'cardo' => 0
      }
    end

    def compute_fhcv_checksum
      fhcv = 0
      deckall = attributes['decka']
      deckalln = (deckall.size / 4.0).floor

      deckalln.times do |i|
        cardnum = deckall[4*i..4*i+3].to_i
        fhcv = fhcv + 10 + (cardnum / 2000).floor * 1500
        if cardnum - (cardnum / 100.0).floor * 100 == 20
          fhcv = fhcv + 1000
        end
      end

      logger.debug "computed fhcv: #{fhcv}"
      attributes['fhcv'] = fhcv
    end

    def compute_fh_checksum
      electrum = attributes['electrum'].to_i

      attributes['deck2'] = "fhh" if electrum > 4

      ranrr = 100.0 + rand * 600.0;
      fhcv = compute_fhcv_checksum.to_i
      score = attributes['score'].to_i
      lonelyt = attributes['lonelyt'].to_i
      fhrr = -(Math.sin(ranrr / 314.0) * Math.sin(ranrr / 314.0) + Math.cos(ranrr / 314.0) *
              Math.cos(ranrr / 314.0)).round * (10 ** (ranrr / 100.0).floor)
      fhrr += fhcv + electrum * 3
      fh = fhrr + fhcv + electrum + score + lonelyt/2

      logger.debug "computed fh: #{fh}"
      attributes['fh'] = fh
    end

    def valid?
      if attributes['decka'].size > 16000
        logger.error 'A maximum of 4000 cards can be saved'
        return false
      end
      true
    end

    def sync
      return unless valid?
      compute_fh_checksum
      logger.info "Syncing player data"
      params = attributes.merge(sync_attributes)
      result = request(sync_url, params)
      logger.info "Sync result: #{result['errorcode']}"
    end

    def self.login username, password
      params = {user: username, psw: password, errorcode: -1}

      logger.info "Logging in as #{username}"
      attributes = request(login_url, params)

      if attributes['errorcode'] != '0'
        logger.error "Auth failed"
        exit(1)
      end

      logger.info "Logged in!"
      new(attributes.merge('user' => username, 'psw' => password))
    end
  end
end

def usage
  puts "Usage: ruby elements.rb user psw [[electrum=XXX] [won=XXX] [lost=XXX] [score=XXX]]"
  exit(0)
end

usage if ARGV.size < 3

whitelist = %w[electrum won lost score]

attributes = ARGV[2..-1].inject({}) do |h, str|
  key, value = str.split('=').map(&:downcase)
  h[key] = whitelist.include?(key) && value.to_i || usage
  h
end

player = Elements::Player.login ARGV[0], ARGV[1]
player.attributes.merge!(attributes)
player.sync
