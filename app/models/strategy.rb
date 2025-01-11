# frozen_string_literal: true

class Strategy < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
