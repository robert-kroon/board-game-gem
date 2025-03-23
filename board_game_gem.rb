require 'nokogiri'
require 'open-uri'

module BoardGameGem
  class BoardGameGem < BggBase
    MAX_ATTEMPTS = 10

    def self.get_item(id, statistics = false, options = {})
      options[:id] = id
      options[:stats] = statistics ? 1 : 0
      item = BggItem.new(self.request_xml("thing", options))
      item
    end

    def self.get_items(ids, statistics = false, options = {})
      options[:id] = ids.join(",")
      options[:stats] = statistics ? 1 : 0
      item_list = []
      path = "thing"
      element = "item"

      item_xml = BoardGameGem.request_xml(path, options)
      item_xml.css(element).wrap("<item_data></item_data>")
      item_xml.css("item_data").each do |item_data|
        item_list.push(BggItem.new(item_data))
      end

      item_list
    end

    def self.get_family(id, options = {})
      options[:id] = id
      family = BggFamily.new(BoardGameGem.request_xml("family", options))
      family.id == 0 ? nil : family
    end

    def self.get_user(username, options = {})
      options[:name] = username
      user = BggUser.new(BoardGameGem.request_xml("user", options))
      user.id == 0 ? nil : user
    end

    def self.get_collection(username, options = {})
      options[:username] = username
      collection_xml = BoardGameGem.request_xml("collection", options)
      if collection_xml.css("error").length > 0
        nil
      else
        BggCollection.new(collection_xml)
      end
    end

    def self.search(query, options = {})
      options[:query] = query
      xml = BoardGameGem.request_xml("search", options)
      {
        :total => xml.at_css("items")["total"].to_i,
        :items => xml.css("item").map { |x| BggSearchResult.new(x) }
      }
    end

    private

    def self.request_xml(method, hash)
      params = BoardGameGem.hash_to_uri(hash)
      url = "https://boardgamegeek.com/xmlapi2/#{method}?#{params}"
      response = RestClient::Request.execute(method: :get, url: url, verify_ssl: false, max_redirects: 0).body
      Nokogiri::XML(response)
    end

    def self.hash_to_uri(hash)
      return hash.to_a.map { |x| "#{x[0]}=#{x[1]}" }.join("&")
    end

    def self.retryable(options = {}, &block)
      opts = { :tries => 1, :on => Exception }.merge(options)

      retry_exception, retries = opts[:on], opts[:tries]

      begin
        return yield
      rescue retry_exception
        retry if (retries -= 1) > 0
      end

      yield
    end
  end
end