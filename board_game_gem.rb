require 'nokogiri'
require 'open-uri'
module BoardGameGem
  class BoardGameGem
    def self.get_item(id, statistics = false, options = {})
      options[:id] = id
      options[:stats] = statistics ? 1 : 0
      request_xml = BoardGameGem.request_xml("thing", options)
      item = BGGItem.new(request_xml)
      item.id == 0 ? nil : item
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
        item_list.push(BGGItem.new(item_data))
      end

      item_list
    end

    def self.get_family(id, options = {})
      options[:id] = id
      family = BGGFamily.new(BoardGameGem.request_xml("family", options))
      family.id == 0 ? nil : family
    end

    def self.get_user(username, options = {})
      options[:name] = username
      user = BGGUser.new(BoardGameGem.request_xml("user", options))
      user.id == 0 ? nil : user
    end

    def self.get_collection(username, options = {})
      options[:username] = username
      collection_xml = BoardGameGem.request_xml("collection", options)
      if collection_xml.css("error").length > 0
        nil
      else
        BGGCollection.new(collection_xml)
      end
    end

    def self.search(query, options = {})
      options[:query] = query
      xml = BoardGameGem.request_xml("search", options)
      {
        :total => xml.at_css("items")["total"].to_i,
        :items => xml.css("item").map { |x| BGGSearchResult.new(x) }
      }
    end

    private

    def self.request_xml(method, hash)
      params = BoardGameGem.hash_to_uri(hash)
      api_path = "https://www.boardgamegeek.com/xmlapi2/#{method}?#{params}"
      value = BoardGameGem.retryable(tries: 10, on: OpenURI::HTTPError) do
        URI.open(api_path) do |file|
          if file.status[0] != "200"
            sleep 0.05
            throw OpenURI::HTTPError
          else
            value = Nokogiri::XML(file.read)
          end
        end
      end
      value
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
