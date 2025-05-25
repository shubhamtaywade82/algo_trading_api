module Positions
  class ActiveCache
    KEY = 'active_positions'.freeze

    def self.add(sec_id)
      Rails.cache.write("#{KEY}_#{sec_id}", true, expires_in: 1.hour)
    end

    def self.remove(sec_id)
      Rails.cache.delete("#{KEY}_#{sec_id}")
    end

    def self.include?(sec_id)
      Rails.cache.read("#{KEY}_#{sec_id}")
    end
  end
end
