# frozen_string_literal: true

require 'nokogiri'

module BoardGameGem
  class BoardGameGem < BggBase
    BGG_API_BASE = 'https://boardgamegeek.com/xmlapi2'
    REQUEST_TIMEOUT = 10
    # BGG API requires authentication - this token is from BGG developer account
    BGG_API_TOKEN = '5c65b3d4-058e-4a1a-92e8-109d3e7658ac'

    class BggApiError < StandardError; end

    # BGG API rate limit: max 2 requests/second.
    # We enforce a minimum interval of 0.5s between requests globally
    # using a class-level mutex and timestamp.
    MAX_REQUESTS_PER_SECOND = 2
    MIN_REQUEST_INTERVAL = 1.0 / MAX_REQUESTS_PER_SECOND

    @last_request_at = nil
    @rate_limit_mutex = Mutex.new

    # Public throttle method for callers that make direct BGG API requests
    # outside of BoardGameGem (e.g. BggInformation).
    def self.throttle!
      @rate_limit_mutex.synchronize do
        if @last_request_at
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at
          sleep(MIN_REQUEST_INTERVAL - elapsed) if elapsed < MIN_REQUEST_INTERVAL
        end
        @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    def self.get_item(id, statistics = false, options = {})
      options[:id] = id
      options[:stats] = statistics ? 1 : 0
      BggItem.new(request_xml('thing', options))
    end

    def self.get_items(ids, statistics = false, options = {})
      options[:id] = ids.join(',')
      options[:stats] = statistics ? 1 : 0

      item_xml = request_xml('thing', options)
      item_xml.css('item').map { |item_data| BggItem.new(item_data) }
    end

    def self.get_family(id, options = {})
      options[:id] = id
      family = BggFamily.new(request_xml('family', options))
      family.id.zero? ? nil : family
    end

    def self.get_user(username, options = {})
      options[:name] = username
      user = BggUser.new(request_xml('user', options))
      user.id.zero? ? nil : user
    end

    def self.get_collection(username, options = {})
      options[:username] = username
      collection_xml = request_xml('collection', options)
      collection_xml.css('error').any? ? nil : BggCollection.new(collection_xml)
    end

    def self.search(query, options = {})
      options[:query] = query
      xml = request_xml('search', options)
      items_node = xml.at_css('items')
      {
        total: items_node ? items_node['total'].to_i : 0,
        items: xml.css('item').map { |x| BggSearchResult.new(x) }
      }
    end

    class << self
      private

      def request_xml(method, params)
        url = build_url(method, params)
        response = make_request(url)
        Nokogiri::XML(response)
      rescue Excon::Error => e
        Rails.logger.error("[BoardGameGem] API request failed: #{e.message}")
        raise BggApiError, "BGG API request failed: #{e.message}"
      end

      def build_url(method, params)
        query_string = URI.encode_www_form(params)
        "#{BGG_API_BASE}/#{method}?#{query_string}"
      end

      def make_request(url, retries = 3)
        throttle_request

        response = Excon.get(
          url,
          headers: default_headers,
          read_timeout: REQUEST_TIMEOUT,
          connect_timeout: REQUEST_TIMEOUT,
          ssl_verify_peer: false
        )

        # BGG API returns 202 when data is being prepared, retry after delay
        if response.status == 202
          sleep 2
          return make_request(url, retries)
        end

        # Handle rate limiting with exponential backoff
        if response.status == 429 && retries > 0
          sleep_time = (4 - retries) * 2 # 2, 4, 6 seconds
          Rails.logger.warn "[BoardGameGem] Rate limited, retrying in #{sleep_time}s (#{retries} retries left)"
          sleep sleep_time
          return make_request(url, retries - 1)
        end

        raise BggApiError, "BGG API returned status #{response.status}" unless response.status == 200

        response.body
      end

      def default_headers
        {
          'User-Agent' => "Bordspellenvergelijken/1.0 (#{Rails.env})",
          'Accept' => 'application/xml',
          'Authorization' => "Bearer #{BGG_API_TOKEN}"
        }
      end

      # Ensures we never exceed 2 requests/second to the BGG API.
      def throttle_request
        BoardGameGem.throttle!
      end
    end
  end
end
